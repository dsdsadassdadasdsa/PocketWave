import Foundation
import AVFoundation
import UniformTypeIdentifiers
import SwiftUI

@MainActor
final class MusicLibrary: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published var playlists: [MusicPlaylist] = []
    @Published var importMessage: String?
    private let tracksKey = "PocketWaveTracks_v1"
    private let playlistsURL: URL
    private let bookmarkURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        playlistsURL = docs.appendingPathComponent("playlists.json")
        bookmarkURL = docs.appendingPathComponent("music-folder.bookmark")
        if let data = UserDefaults.standard.data(forKey: tracksKey), let saved = try? JSONDecoder().decode([Track].self, from: data) { tracks = saved }
        if let data = try? Data(contentsOf: playlistsURL), let saved = try? JSONDecoder().decode([MusicPlaylist].self, from: data) { playlists = saved }
        restoreFolderBookmark()
        scanDocuments()
    }

    func importURLs(_ urls: [URL]) {
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if url.hasDirectoryPath { scanFolder(url, makeBookmark: true) }
            else if Self.isAudio(url) { addTrack(url) }
        }
        persistTracks()
    }

    func scanFolder(_ folder: URL, makeBookmark: Bool = false) {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        if makeBookmark, let data = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) { try? data.write(to: bookmarkURL, options: .atomic) }
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        while let file = enumerator.nextObject() as? URL { if Self.isAudio(file) { addTrack(file) } }
        persistTracks()
    }

    private func restoreFolderBookmark() {
        guard let data = try? Data(contentsOf: bookmarkURL) else { return }
        var stale = false
        if let folder = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) { scanFolder(folder, makeBookmark: stale) }
    }

    func scanDocuments() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) else { return }
        files.filter(Self.isAudio).forEach(addTrack)
        persistTracks()
    }

    private static func isAudio(_ url: URL) -> Bool { ["mp3", "m4a", "wav", "flac"].contains(url.pathExtension.lowercased()) }

    private func addTrack(_ url: URL) {
        guard !tracks.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { return }
        let asset = AVURLAsset(url: url)
        let metadata = asset.commonMetadata
        func value(_ key: AVMetadataIdentifier) -> String { AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: key).first?.stringValue ?? "" }
        let artwork = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first?.dataValue
        let duration = CMTimeGetSeconds(asset.duration)
        tracks.append(Track(title: value(.commonIdentifierTitle), artist: value(.commonIdentifierArtist), album: value(.commonIdentifierAlbumName), url: url, duration: duration.isFinite ? duration : 0, artworkData: artwork))
        tracks.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    func remove(_ track: Track) {
        tracks.removeAll { $0.id == track.id }
        playlists.indices.forEach { playlists[$0].trackIDs.removeAll { $0 == track.id } }
        persistTracks(); persistPlaylists()
    }

    func createPlaylist(name: String) { let clean = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !clean.isEmpty else { return }; playlists.append(MusicPlaylist(name: clean)); persistPlaylists() }
    func toggle(_ track: Track, in playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        if let j = playlists[i].trackIDs.firstIndex(of: track.id) { playlists[i].trackIDs.remove(at: j) } else { playlists[i].trackIDs.append(track.id) }
        persistPlaylists()
    }
    func setArtwork(_ data: Data, for playlistID: UUID) { guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }; playlists[i].artworkData = data; persistPlaylists() }
    func orderedTracks(for playlist: MusicPlaylist) -> [Track] { playlist.trackIDs.compactMap { id in tracks.first { $0.id == id } } }
    func movePlaylistTrack(playlistID: UUID, from: IndexSet, to: Int) { guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }; playlists[i].trackIDs.move(fromOffsets: from, toOffset: to); persistPlaylists() }
    private func persistTracks() { if let data = try? JSONEncoder().encode(tracks) { UserDefaults.standard.set(data, forKey: tracksKey) } }
    private func persistPlaylists() { if let data = try? JSONEncoder().encode(playlists) { try? data.write(to: playlistsURL, options: .atomic) } }
}
