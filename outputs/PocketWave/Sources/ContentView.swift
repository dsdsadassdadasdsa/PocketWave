import SwiftUI
import UniformTypeIdentifiers

private enum PlayerTab: String, CaseIterable { case now = "NOW", tracks = "TRACKS", folders = "FOLDERS", albums = "ALBUMS" }

struct ContentView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var player: AudioPlayerManager
    @Namespace private var artworkSpace
    @State private var tab: PlayerTab = .now
    @State private var showPicker = false
    @State private var pickerFolders = false
    @State private var showCreate = false
    @State private var showFullPlayer = false
    @State private var locked = false
    @State private var unlockStart: Date?
    @State private var showArtworkPicker = false
    @State private var selectedPlaylistID: UUID?
    @State private var selectedImage: UIImage?

    private let orange = Color(red: 1, green: 0.36, blue: 0.12)
    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.06, blue: 0.065).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Group {
                    switch tab {
                    case .now: nowPlaying
                    case .tracks: trackList(library.tracks)
                    case .folders: foldersView
                    case .albums: albumsView
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                miniPlayer
                tabBar
            }.padding(.horizontal, 20).padding(.top, 9)
            if locked { lockOverlay }
        }
        .sheet(isPresented: $showPicker) { DocumentPicker(folders: pickerFolders) { urls in library.importURLs(urls) } .ignoresSafeArea() }
        .sheet(isPresented: $showCreate) { CreatePlaylistSheet { library.createPlaylist(name: $0) } }
        .sheet(isPresented: $showArtworkPicker, onDismiss: saveSelectedArtwork) { ImagePicker(image: $selectedImage) }
        .sheet(isPresented: $showFullPlayer) { fullPlayer }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) { Text("POCKETWAVE").font(.system(size: 12, weight: .black, design: .rounded)).kerning(2.2).foregroundColor(orange); Text("PORTABLE SOUND SYSTEM").font(.system(size: 8, weight: .medium, design: .monospaced)).kerning(1.3).foregroundColor(.white.opacity(0.42)) }
            Spacer()
            Button { pickerFolders = true; showPicker = true; impact() } label: { Image(systemName: "folder.badge.plus").font(.system(size: 17, weight: .semibold)).foregroundColor(.white).frame(width: 42, height: 42).background(.white.opacity(0.07), in: Circle()).overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1)) }
            Button { locked = true; impact() } label: { Image(systemName: "lock.fill").font(.system(size: 15, weight: .semibold)).foregroundColor(orange).frame(width: 42, height: 42).background(orange.opacity(0.1), in: Circle()) }
        }.padding(.bottom, 16)
    }

    private var nowPlaying: some View {
        VStack(spacing: 8) {
            HStack { Text("SIGNAL / 001").font(.system(size: 9, weight: .bold, design: .monospaced)).kerning(1.8).foregroundColor(.white.opacity(0.45)); Spacer(); equalizer.tint(orange) }
            Spacer(minLength: 3)
            Button { showFullPlayer = true; impact() } label: { albumArt(size: 255, track: player.currentTrack).matchedGeometryEffect(id: "albumArt", in: artworkSpace) }
                .buttonStyle(.plain)
            VStack(spacing: 5) {
                Text(player.currentTrack?.displayTitle ?? "NOTHING PLAYING").font(.system(size: 24, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75).foregroundColor(.white)
                Text(player.currentTrack?.artist.isEmpty == false ? player.currentTrack!.artist : "ADD TRACKS TO BEGIN").font(.system(size: 11, weight: .medium, design: .monospaced)).kerning(1.5).foregroundColor(.white.opacity(0.48)).lineLimit(1)
            }.padding(.top, 8)
            timeline
            controls
            Spacer(minLength: 8)
        }.padding(.top, 4)
    }

    private var timeline: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }), in: 0...max(player.duration, 1)).tint(orange).accessibilityLabel("Track position")
            HStack { Text(time(player.currentTime)); Spacer(); Text(time(max(0, player.duration - player.currentTime))) }.font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.42))
        }.padding(.horizontal, 2).padding(.top, 4)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Button { player.toggleShuffle(); impact() } label: { Image(systemName: "shuffle").font(.system(size: 17, weight: .semibold)).foregroundColor(player.isShuffle ? orange : .white.opacity(0.42)).frame(width: 44, height: 54) }
            Spacer()
            Button { player.previous(); impact() } label: { Image(systemName: "backward.end.fill").font(.system(size: 21)).foregroundColor(.white).frame(width: 48, height: 54) }
            Button { player.togglePlayPause(); impact() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 23, weight: .bold)).foregroundColor(.black).offset(x: player.isPlaying ? 0 : 2).frame(width: 68, height: 68).background(orange, in: Circle()).shadow(color: orange.opacity(0.28), radius: 18, y: 5) }.buttonStyle(PressButtonStyle())
            Button { player.next(); impact() } label: { Image(systemName: "forward.end.fill").font(.system(size: 21)).foregroundColor(.white).frame(width: 48, height: 54) }
            Spacer()
            Button { player.cycleRepeat(); impact() } label: { VStack(spacing: 2) { Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat").font(.system(size: 17, weight: .semibold)); Text(player.repeatMode == .off ? "" : "ON").font(.system(size: 7, weight: .black, design: .monospaced)) }.foregroundColor(player.repeatMode == .off ? .white.opacity(0.42) : orange).frame(width: 44, height: 54) }
        }.padding(.horizontal, 2).padding(.top, 6)
    }

    private var miniPlayer: some View {
        Group {
            if tab != .now {
                HStack(spacing: 11) {
                    albumArt(size: 42, track: player.currentTrack)
                    VStack(alignment: .leading, spacing: 3) { Text(player.currentTrack?.displayTitle ?? "Choose a track").font(.system(size: 12, weight: .bold)).lineLimit(1); Text(player.currentTrack?.artist ?? "POCKETWAVE LIBRARY").font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.42)).lineLimit(1) }
                    Spacer()
                    Button { player.togglePlayPause(); impact() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 17, weight: .bold)).foregroundColor(orange).frame(width: 42, height: 46) }
                    Button { player.next(); impact() } label: { Image(systemName: "forward.end.fill").font(.system(size: 15)).foregroundColor(.white).frame(width: 30, height: 46) }
                }.padding(8).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.07), lineWidth: 1)).onTapGesture { showFullPlayer = true }
            }
        }.padding(.bottom, 12)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PlayerTab.allCases, id: \.self) { item in
                Button { withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) { tab = item }; impact() } label: {
                    VStack(spacing: 5) { Image(systemName: icon(for: item)).font(.system(size: 16, weight: .semibold)); Text(item.rawValue).font(.system(size: 8, weight: .black, design: .monospaced)).kerning(0.8) }.foregroundColor(tab == item ? orange : .white.opacity(0.36)).frame(maxWidth: .infinity).frame(height: 51).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.padding(.top, 4).overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }

    private var foldersView: some View {
        VStack(spacing: 14) {
            Text("YOUR MUSIC FILES").font(.system(size: 10, weight: .black, design: .monospaced)).kerning(1.5).foregroundColor(.white.opacity(0.48)).frame(maxWidth: .infinity, alignment: .leading)
            Button { pickerFolders = true; showPicker = true } label: { VStack(spacing: 12) { Image(systemName: "folder.badge.plus").font(.system(size: 32)).foregroundColor(orange); Text("Choose music folder").font(.system(size: 15, weight: .bold)); Text("MP3 · M4A · WAV · FLAC").font(.system(size: 9, weight: .medium, design: .monospaced)).kerning(1).foregroundColor(.white.opacity(0.42)) }.frame(maxWidth: .infinity).padding(.vertical, 30).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))) }
            Button { pickerFolders = false; showPicker = true } label: { Text("OR SELECT AUDIO FILES").font(.system(size: 10, weight: .bold, design: .monospaced)).kerning(1.2).foregroundColor(orange).frame(maxWidth: .infinity).padding(15).background(orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)) }
            Spacer()
            Text("Files shared from a computer appear in the app's Documents folder.").font(.system(size: 10)).foregroundColor(.white.opacity(0.3)).multilineTextAlignment(.center)
        }.padding(.top, 12)
    }

    private var albumsView: some View {
        VStack(spacing: 12) {
            HStack { Text("YOUR MIXTAPES").font(.system(size: 10, weight: .black, design: .monospaced)).kerning(1.5).foregroundColor(.white.opacity(0.48)); Spacer(); Button { showCreate = true; impact() } label: { Label("NEW", systemImage: "plus").font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(orange).padding(.horizontal, 12).padding(.vertical, 8).background(orange.opacity(0.12), in: Capsule()) } }
            if library.playlists.isEmpty { Spacer(); Image(systemName: "square.stack.3d.up").font(.system(size: 35)).foregroundColor(.white.opacity(0.18)); Text("No albums yet").font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.5)); Text("Make a mixtape from your tracks").font(.system(size: 11)).foregroundColor(.white.opacity(0.3)); Spacer() }
            else { ScrollView { LazyVStack(spacing: 10) { ForEach(library.playlists) { playlist in playlistRow(playlist) } }.padding(.vertical, 2) } }
            Spacer(minLength: 0)
        }.padding(.top, 12)
    }

    private func playlistRow(_ playlist: MusicPlaylist) -> some View {
        let list = library.orderedTracks(for: playlist)
        return VStack(spacing: 9) {
            HStack(spacing: 11) {
                Button { selectedPlaylistID = playlist.id; showArtworkPicker = true } label: { playlistArt(playlist, size: 52) }
                VStack(alignment: .leading, spacing: 4) { Text(playlist.name).font(.system(size: 14, weight: .bold)).lineLimit(1); Text("\(list.count) TRACKS").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.4)) }
                Spacer()
                Button { if let first = list.first { player.play(first, from: list); tab = .now } } label: { Image(systemName: "play.fill").font(.system(size: 15)).foregroundColor(orange).frame(width: 42, height: 42) }
                Menu { ForEach(library.tracks) { track in Button(library.orderedTracks(for: playlist).contains(where: { $0.id == track.id }) ? "Remove · \(track.displayTitle)" : "Add · \(track.displayTitle)") { library.toggle(track, in: playlist.id) } } } label: { Image(systemName: "plus.circle").font(.system(size: 18)).foregroundColor(.white.opacity(0.55)).frame(width: 30, height: 42) }
            }
            if !list.isEmpty { ForEach(list) { track in HStack { Text(track.displayTitle).font(.system(size: 11, weight: .medium)).lineLimit(1); Spacer(); Button { library.toggle(track, in: playlist.id) } label: { Image(systemName: "minus.circle").foregroundColor(.white.opacity(0.35)) } }.padding(.leading, 63).padding(.trailing, 6) }.onMove { library.movePlaylistTrack(playlistID: playlist.id, from: $0, to: $1) } }
        }.padding(11).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }

    private func trackList(_ tracks: [Track]) -> some View {
        VStack(spacing: 12) {
            HStack { Text("LIBRARY / \(tracks.count)").font(.system(size: 10, weight: .black, design: .monospaced)).kerning(1.5).foregroundColor(.white.opacity(0.48)); Spacer(); Button { pickerFolders = false; showPicker = true } label: { Image(systemName: "plus").foregroundColor(orange).frame(width: 34, height: 34).background(orange.opacity(0.1), in: Circle()) } }
            if tracks.isEmpty { Spacer(); Image(systemName: "waveform").font(.system(size: 34)).foregroundColor(.white.opacity(0.2)); Text("Your library is quiet").font(.system(size: 15, weight: .semibold)).foregroundColor(.white.opacity(0.5)); Button("IMPORT MUSIC") { pickerFolders = true; showPicker = true }.font(.system(size: 10, weight: .black, design: .monospaced)).kerning(1).foregroundColor(orange).padding(.top, 4); Spacer() }
            else { ScrollView { LazyVStack(spacing: 5) { ForEach(tracks) { track in trackRow(track) } }.padding(.vertical, 2) } }
        }.padding(.top, 12)
    }

    private func trackRow(_ track: Track) -> some View {
        HStack(spacing: 11) {
            albumArt(size: 46, track: track)
            VStack(alignment: .leading, spacing: 4) { Text(track.displayTitle).font(.system(size: 13, weight: .bold)).lineLimit(1); Text(track.artist.isEmpty ? track.url.deletingPathExtension().lastPathComponent : track.artist).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.42)).lineLimit(1) }
            Spacer(minLength: 0)
            Text(time(track.duration)).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.38))
            Menu { ForEach(library.playlists) { playlist in Button("Add to \(playlist.name)") { library.toggle(track, in: playlist.id) } }; Button("Remove from library", role: .destructive) { library.remove(track) } } label: { Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold)).foregroundColor(.white.opacity(0.5)).frame(width: 28, height: 42) }
        }.padding(7).background(player.currentTrack?.id == track.id ? orange.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle()).onTapGesture { player.play(track, from: library.tracks); withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { tab = .now } }
    }

    private var fullPlayer: some View {
        ZStack { Color(red: 0.055, green: 0.06, blue: 0.065).ignoresSafeArea(); VStack(spacing: 12) {
            Capsule().fill(.white.opacity(0.18)).frame(width: 35, height: 4).padding(.top, 9)
            HStack { Text("NOW / PLAYING").font(.system(size: 9, weight: .black, design: .monospaced)).kerning(1.8).foregroundColor(orange); Spacer(); Button { showFullPlayer = false } label: { Image(systemName: "chevron.down").foregroundColor(.white.opacity(0.6)).frame(width: 34, height: 34) } }.padding(.top, 5)
            Spacer(minLength: 4); albumArt(size: 290, track: player.currentTrack).matchedGeometryEffect(id: "albumArt", in: artworkSpace).rotationEffect(.degrees(player.isPlaying ? 4 : 0)).animation(.spring(response: 0.6, dampingFraction: 0.62).repeatForever(autoreverses: true), value: player.isPlaying)
            VStack(spacing: 5) { Text(player.currentTrack?.displayTitle ?? "NOTHING PLAYING").font(.system(size: 24, weight: .bold, design: .rounded)).lineLimit(1); Text(player.currentTrack?.artist ?? "ADD TRACKS TO BEGIN").font(.system(size: 10, weight: .medium, design: .monospaced)).kerning(1).foregroundColor(.white.opacity(0.48)) }.padding(.top, 6)
            timeline.padding(.horizontal, 3); controls.padding(.top, 7); Spacer(minLength: 3)
        }.padding(.horizontal, 24) }
    }

    private var lockOverlay: some View {
        ZStack { Color.black.opacity(0.93).ignoresSafeArea(); VStack(spacing: 20) { Image(systemName: "lock.fill").font(.system(size: 35)).foregroundColor(orange); Text("PLAYER LOCKED").font(.system(size: 13, weight: .black, design: .monospaced)).kerning(2); Text("Touch and hold to unlock").font(.system(size: 11)).foregroundColor(.white.opacity(0.42)); Circle().fill(orange.opacity(0.13)).frame(width: 88, height: 88).overlay(Image(systemName: "lock.open").font(.system(size: 25)).foregroundColor(orange)).onLongPressGesture(minimumDuration: 1.4, pressing: { pressing in if pressing { unlockStart = Date() } }, perform: { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { locked = false }; impact() }) }.contentShape(Rectangle()) }
    }

    private func albumArt(size: CGFloat, track: Track?) -> some View {
        ZStack {
            if let image = track?.artwork { Image(uiImage: image).resizable().scaledToFill() }
            else { LinearGradient(colors: [Color(red: 0.34, green: 0.14, blue: 0.1), Color(red: 0.08, green: 0.08, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing); Circle().stroke(.white.opacity(0.12), lineWidth: 1).padding(size * 0.12); Circle().stroke(.white.opacity(0.1), lineWidth: 1).padding(size * 0.22); Image(systemName: "waveform").font(.system(size: size * 0.25, weight: .light)).foregroundColor(orange) }
            if player.isPlaying { VinylLines().stroke(.white.opacity(0.11), lineWidth: 1) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size > 100 ? 20 : 9)).overlay(RoundedRectangle(cornerRadius: size > 100 ? 20 : 9).stroke(.white.opacity(0.14), lineWidth: 1)).shadow(color: .black.opacity(0.38), radius: size > 100 ? 24 : 5, y: 9).clipped()
    }
    private func playlistArt(_ playlist: MusicPlaylist, size: CGFloat) -> some View { Group { if let data = playlist.artworkData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() } else { LinearGradient(colors: [orange.opacity(0.8), Color.purple.opacity(0.65), .black], startPoint: .topLeading, endPoint: .bottomTrailing).overlay(Image(systemName: "waveform").foregroundColor(.white.opacity(0.8))) } }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 11)) }
    private var equalizer: some View { HStack(spacing: 3) { ForEach(0..<4) { i in Capsule().fill(orange.opacity(player.isPlaying ? 0.95 : 0.35)).frame(width: 3, height: player.isPlaying ? CGFloat([8, 15, 10, 18][i]) : 4).animation(.easeInOut(duration: Double(0.22 + Double(i) * 0.12)).repeatForever(autoreverses: true), value: player.isPlaying) } }.frame(height: 19, alignment: .center) }
    private func time(_ value: Double) -> String { guard value.isFinite else { return "0:00" }; return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
    private func icon(for tab: PlayerTab) -> String { switch tab { case .now: return "waveform"; case .tracks: return "music.note.list"; case .folders: return "folder"; case .albums: return "square.stack.3d.up" } }
    private func impact() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    private func saveSelectedArtwork() { guard let id = selectedPlaylistID, let data = selectedImage?.jpegData(compressionQuality: 0.85) else { return }; library.setArtwork(data, for: id); selectedImage = nil }
}

private struct VinylLines: Shape { func path(in rect: CGRect) -> Path { var p = Path(); for inset in stride(from: rect.width * 0.08, to: rect.width * 0.49, by: rect.width * 0.055) { p.addEllipse(in: rect.insetBy(dx: inset, dy: inset)) }; return p } }
private struct PressButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.scaleEffect(configuration.isPressed ? 0.91 : 1).animation(.spring(response: 0.25, dampingFraction: 0.52), value: configuration.isPressed) } }

private struct DocumentPicker: UIViewControllerRepresentable {
    let folders: Bool
    let onPick: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = folders ? [.folder] : [.audio, UTType(filenameExtension: "flac") ?? .audio]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = !folders; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { }
    final class Coordinator: NSObject, UIDocumentPickerDelegate { let onPick: ([URL]) -> Void; init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }; func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls) } }
}

private struct CreatePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    let onCreate: (String) -> Void
    var body: some View { VStack(alignment: .leading, spacing: 16) { Text("NEW MIXTAPE").font(.system(size: 12, weight: .black, design: .monospaced)).kerning(1.4); TextField("Album name", text: $name).padding(13).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11)); Button { onCreate(name); dismiss() } label: { Text("CREATE ALBUM").font(.system(size: 11, weight: .black, design: .monospaced)).kerning(1.2).frame(maxWidth: .infinity).padding(15).background(Color(red: 1, green: 0.36, blue: 0.12), in: RoundedRectangle(cornerRadius: 12)).foregroundColor(.black) }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }.padding(22).background(Color(red: 0.07, green: 0.07, blue: 0.08)).preferredColorScheme(.dark) }
}

private struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController { let picker = UIImagePickerController(); picker.sourceType = .photoLibrary; picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate { let parent: ImagePicker; init(_ parent: ImagePicker) { self.parent = parent }; func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { parent.image = info[.originalImage] as? UIImage; parent.dismiss() }; func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() } }
}
