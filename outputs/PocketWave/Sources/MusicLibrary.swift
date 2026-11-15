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
    private let importedAudioURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        playlistsURL = docs.appendingPathComponent("playlists.json")
        bookmarkURL = docs.appendingPathComponent("music-folder.bookmark")
        importedAudioURL = docs.appendingPathComponent("ImportedAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: importedAudioURL, withIntermediateDirectories: true)
        if let data = UserDefaults.standard.data(forKey: tracksKey), let saved = try? JSONDecoder().decode([Track].self, from: data) { tracks = saved }
        if let data = try? Data(contentsOf: playlistsURL), let saved = try? JSONDecoder().decode([MusicPlaylist].self, from: data) { playlists = saved }
        restoreFolderBookmark()
        scanDocuments()
    }

    func importURLs(_ urls: [URL]) {
        importMessage = nil
        guard !urls.isEmpty else { importMessage = "Files did not return a selected item."; return }
        let oldCount = tracks.count
        for url in urls {
            let hasScopedAccess = url.startAccessingSecurityScopedResource()
            do {
                defer { if hasScopedAccess { url.stopAccessingSecurityScopedResource() } }
                if Self.isDirectory(url) {
                    scanFolder(url, makeBookmark: true, alreadyAccessing: hasScopedAccess)
                } else if Self.isAudio(url) {
                    importAudioFile(url)
                } else {
                    importMessage = "The selected item is not a supported audio file or folder."
                }
            }
        }
        persistTracks()
        if tracks.count == oldCount, importMessage == nil {
            importMessage = "No playable audio files were imported. Check that the folder contains MP3, M4A, WAV or FLAC files."
        }
    }

    func scanFolder(_ folder: URL, makeBookmark: Bool = false, alreadyAccessing: Bool = false) {
        let startedAccess = alreadyAccessing || folder.startAccessingSecurityScopedResource()
        guard startedAccess else { importMessage = "Folder access was not granted by Files."; return }
        defer { if !alreadyAccessing { folder.stopAccessingSecurityScopedResource() } }
        if makeBookmark, let data = try? folder.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil) { try? data.write(to: bookmarkURL, options: .atomic) }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var foundAudioFiles = 0
        let oldCount = tracks.count
        coordinator.coordinate(readingItemAt: folder, options: [], error: &coordinationError) { coordinatedFolder in
            guard let enumerator = FileManager.default.enumerator(at: coordinatedFolder, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { importMessage = "Files could not list this folder."; return }
            while let file = enumerator.nextObject() as? URL {
                guard Self.isAudio(file) else { continue }
                foundAudioFiles += 1
                // A folder picker grants access to the selected folder tree, not a separate
                // security-scoped URL for each child. Read and copy children while the
                // coordinated folder access remains active.
                importAudioFile(file, alreadyCoordinated: true)
            }
        }
        if let coordinationError { importMessage = "Folder access failed: \(coordinationError.localizedDescription)" }
        else if foundAudioFiles == 0 { importMessage = "No MP3, M4A, WAV or FLAC files were found in the selected folder." }
        else if tracks.count == oldCount, importMessage == nil { importMessage = "Audio files were found, but none could be copied into the app. Re-select the folder in Files and try again." }
        persistTracks()
    }

    private func restoreFolderBookmark() {
        guard let data = try? Data(contentsOf: bookmarkURL) else { return }
        var stale = false
        if let folder = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) { scanFolder(folder, makeBookmark: stale) }
    }

    func scanDocuments() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let enumerator = FileManager.default.enumerator(at: docs, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        while let file = enumerator.nextObject() as? URL { if Self.isAudio(file) { addTrack(file) } }
        persistTracks()
    }

    private func importAudioFile(_ source: URL, alreadyCoordinated: Bool = false) {
        if alreadyCoordinated {
            importAudioFileContent(source)
            return
        }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinatedSource in
            importAudioFileContent(coordinatedSource)
        }
        if let coordinationError { importMessage = "Could not read \(source.lastPathComponent): \(coordinationError.localizedDescription)" }
    }

    private func importAudioFileContent(_ source: URL) {
        let sourceSize = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value
        if let index = tracks.firstIndex(where: { track in
            guard track.url.lastPathComponent == source.lastPathComponent, let sourceSize,
                  let trackSize = (try? FileManager.default.attributesOfItem(atPath: track.url.path)[.size] as? NSNumber)?.int64Value else { return false }
            return sourceSize == trackSize
        }) {
            if tracks[index].url.path.hasPrefix(importedAudioURL.path) { return }
            if let localCopy = copyIntoLibrary(source) { tracks[index].url = localCopy; persistTracks() }
            return
        }
        if let localCopy = copyIntoLibrary(source) { addTrack(localCopy) }
    }

    private func copyIntoLibrary(_ source: URL) -> URL? {
        var destination = importedAudioURL.appendingPathComponent(source.lastPathComponent)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = importedAudioURL.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(suffix).\(source.pathExtension)")
            suffix += 1
        }
        do {
            try FileManager.default.createDirectory(at: importedAudioURL, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            importMessage = "Could not import \(source.lastPathComponent): \(error.localizedDescription)"
            return nil
        }
    }

    private static func isAudio(_ url: URL) -> Bool { ["mp3", "m4a", "wav", "flac"].contains(url.pathExtension.lowercased()) }

    private static func isDirectory(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true { return true }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

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
