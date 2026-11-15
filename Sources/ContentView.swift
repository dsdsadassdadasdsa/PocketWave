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
    @AppStorage("PocketWaveLightTheme") private var lightTheme = false
    @AppStorage("PocketWaveLanguage") private var languageCode = "ru"
    @AppStorage("PocketWaveAccentIndex") private var accentIndex = 0

    private let accentOptions: [Color] = [Color(red: 1, green: 0.36, blue: 0.12), Color(red: 0.68, green: 0.91, blue: 0.16), Color(red: 0.22, green: 0.64, blue: 1), Color(red: 0.76, green: 0.42, blue: 1), .white, .black]
    private var accent: Color {
        switch accentIndex { case 4: return lightTheme ? Color(red: 0.16, green: 0.17, blue: 0.18) : .white; case 5: return lightTheme ? .black : Color(red: 0.88, green: 0.89, blue: 0.90); default: return accentOptions[min(max(accentIndex, 0), 3)] }
    }
    private var accentForeground: Color { accentIndex >= 4 && lightTheme ? .white : .black }
    private var canvas: Color { lightTheme ? Color(red: 0.94, green: 0.94, blue: 0.92) : Color(red: 0.055, green: 0.06, blue: 0.065) }
    private var ink: Color { lightTheme ? Color(red: 0.08, green: 0.09, blue: 0.10) : .white }
    private func text(_ key: String) -> String { playerText(key, language: languageCode) }
    var body: some View {
        ZStack {
            canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Group {
                    switch tab {
                    case .now: nowPlaying
                    case .tracks: trackList(library.tracks)
                    case .folders: foldersView
                    case .albums: albumsView
                    }
                }.id(tab).transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity)).frame(maxWidth: .infinity, maxHeight: .infinity)
                miniPlayer
                tabBar
            }.padding(.horizontal, 20).padding(.top, 9)
            if locked { lockOverlay }
        }
        .sheet(isPresented: $showPicker) { DocumentPicker(folders: pickerFolders) { urls in library.importURLs(urls) } .ignoresSafeArea() }
        .sheet(isPresented: $showCreate) { CreatePlaylistSheet(isLight: lightTheme, languageCode: languageCode, accentColor: accent) { library.createPlaylist(name: $0) } }
        .sheet(isPresented: $showArtworkPicker, onDismiss: saveSelectedArtwork) { ImagePicker(image: $selectedImage) }
        .sheet(isPresented: $showFullPlayer) { fullPlayer }
        .alert(text("error_title"), isPresented: Binding(get: { library.importMessage != nil || player.playbackError != nil }, set: { if !$0 { library.importMessage = nil; player.playbackError = nil } })) {
            Button(text("ok"), role: .cancel) { library.importMessage = nil; player.playbackError = nil }
        } message: { Text(player.playbackError ?? library.importMessage ?? "") }
        .preferredColorScheme(lightTheme ? .light : .dark)
        .animation(.easeInOut(duration: 0.24), value: lightTheme)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) { Text("POCKETWAVE").font(.system(size: 12, weight: .black, design: .rounded)).foregroundColor(accent); Text(text("subtitle")).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(ink.opacity(0.48)) }
            Spacer()
            Button { pickerFolders = true; showPicker = true; impact() } label: { Image(systemName: "folder.badge.plus").font(.system(size: 17, weight: .semibold)).foregroundColor(ink).frame(width: 42, height: 42).background(ink.opacity(0.07), in: Circle()).overlay(Circle().stroke(ink.opacity(0.1), lineWidth: 1)) }
            Button { locked = true; impact() } label: { Image(systemName: "lock.fill").font(.system(size: 15, weight: .semibold)).foregroundColor(accent).frame(width: 42, height: 42).background(accent.opacity(0.1), in: Circle()) }
            settingsMenu
        }.padding(.bottom, 16)
    }

    private var settingsMenu: some View {
        Menu {
            Section(text("theme")) {
                Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.76)) { lightTheme = false } } label: { Label(text("dark"), systemImage: "moon.stars.fill") }
                Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.76)) { lightTheme = true } } label: { Label(text("light"), systemImage: "sun.max.fill") }
            }
            Section(text("accent")) {
                ForEach(0..<accentOptions.count, id: \.self) { index in
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { accentIndex = index }; impact() } label: {
                        HStack { Circle().fill(accentOptions[index]).frame(width: 13, height: 13); Text(text("color_\(index)")); if accentIndex == index { Image(systemName: "checkmark") } }
                    }
                }
            }
            Section(text("language")) {
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) { languageCode = "en" } } label: { Text("English") }
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) { languageCode = "ru" } } label: { Text("Русский") }
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) { languageCode = "uk" } } label: { Text("Українська") }
            }
        } label: {
            Image(systemName: "slider.horizontal.3").font(.system(size: 16, weight: .semibold)).foregroundColor(accent).frame(width: 42, height: 42).background(ink.opacity(0.07), in: Circle()).overlay(Circle().stroke(ink.opacity(0.1), lineWidth: 1))
        }.accessibilityLabel(text("settings"))
    }

    private var nowPlaying: some View {
        VStack(spacing: 8) {
            HStack { Text(text("signal")).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(ink.opacity(0.45)); Spacer(); equalizer.tint(accent) }
            Spacer(minLength: 3)
            Button { showFullPlayer = true; impact() } label: { albumArt(size: 255, track: player.currentTrack).matchedGeometryEffect(id: "albumArt", in: artworkSpace) }
                .buttonStyle(.plain)
            VStack(spacing: 5) {
                Text(player.currentTrack?.displayTitle ?? text("nothing_playing")).font(.system(size: 24, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75).foregroundColor(ink)
                Text(player.currentTrack?.artist.isEmpty == false ? player.currentTrack!.artist : text("add_tracks")).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(ink.opacity(0.48)).lineLimit(1)
            }.padding(.top, 8)
            timeline
            controls
            Spacer(minLength: 8)
        }.padding(.top, 4)
    }

    private var timeline: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }), in: 0...max(player.duration, 1)).tint(accent).accessibilityLabel(text("track_position"))
            HStack { Text(time(player.currentTime)); Spacer(); Text(time(max(0, player.duration - player.currentTime))) }.font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(ink.opacity(0.42))
        }.padding(.horizontal, 2).padding(.top, 4)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Button { player.toggleShuffle(); impact() } label: { Image(systemName: "shuffle").font(.system(size: 17, weight: .semibold)).foregroundColor(player.isShuffle ? accent : ink.opacity(0.42)).frame(width: 44, height: 54) }
            Spacer()
            Button { player.previous(); impact() } label: { Image(systemName: "backward.end.fill").font(.system(size: 21)).foregroundColor(ink).frame(width: 48, height: 54) }
            Button { player.togglePlayPause(); impact() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 23, weight: .bold)).foregroundColor(accentForeground).offset(x: player.isPlaying ? 0 : 2).frame(width: 68, height: 68).background(accent, in: Circle()).overlay(Circle().stroke(ink.opacity(accentIndex == 5 ? 0.3 : 0), lineWidth: 1)).shadow(color: accent.opacity(0.28), radius: 18, y: 5) }.buttonStyle(PressButtonStyle())
            Button { player.next(); impact() } label: { Image(systemName: "forward.end.fill").font(.system(size: 21)).foregroundColor(ink).frame(width: 48, height: 54) }
            Spacer()
            Button { player.cycleRepeat(); impact() } label: { VStack(spacing: 2) { Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat").font(.system(size: 17, weight: .semibold)); Text(player.repeatMode == .off ? "" : "ON").font(.system(size: 7, weight: .black, design: .monospaced)) }.foregroundColor(player.repeatMode == .off ? ink.opacity(0.42) : accent).frame(width: 44, height: 54) }
        }.padding(.horizontal, 2).padding(.top, 6)
    }

    private var miniPlayer: some View {
        Group {
            if tab != .now {
                HStack(spacing: 11) {
                    albumArt(size: 42, track: player.currentTrack)
                    VStack(alignment: .leading, spacing: 3) { Text(player.currentTrack?.displayTitle ?? text("choose_track")).font(.system(size: 12, weight: .bold)).lineLimit(1); Text(player.currentTrack?.artist ?? text("library")).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(ink.opacity(0.42)).lineLimit(1) }
                    Spacer()
                    Button { player.togglePlayPause(); impact() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 17, weight: .bold)).foregroundColor(accent).frame(width: 42, height: 46) }
                    Button { player.next(); impact() } label: { Image(systemName: "forward.end.fill").font(.system(size: 15)).foregroundColor(ink).frame(width: 30, height: 46) }
                }.padding(8).background(ink.opacity(0.055), in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(ink.opacity(0.07), lineWidth: 1)).onTapGesture { showFullPlayer = true }
            }
        }.padding(.bottom, 12)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PlayerTab.allCases, id: \.self) { item in
                Button { withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) { tab = item }; impact() } label: {
                    VStack(spacing: 5) { Image(systemName: icon(for: item)).font(.system(size: 16, weight: .semibold)); Text(tabTitle(item)).font(.system(size: 8, weight: .black, design: .monospaced)) }.foregroundColor(tab == item ? accent : ink.opacity(0.36)).frame(maxWidth: .infinity).frame(height: 51).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.padding(.top, 4).overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.08)).frame(height: 1) }
    }

    private var foldersView: some View {
        VStack(spacing: 14) {
            Text(text("music_files")).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(ink.opacity(0.48)).frame(maxWidth: .infinity, alignment: .leading)
            Button { pickerFolders = true; showPicker = true } label: { VStack(spacing: 12) { Image(systemName: "folder.badge.plus").font(.system(size: 32)).foregroundColor(accent); Text(text("choose_folder")).font(.system(size: 15, weight: .bold)); Text("MP3 · M4A · WAV · FLAC").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(ink.opacity(0.42)) }.frame(maxWidth: .infinity).padding(.vertical, 30).background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(ink.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))) }
            Button { pickerFolders = false; showPicker = true } label: { Text(text("choose_files")).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(accent).frame(maxWidth: .infinity).padding(15).background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)) }
            Spacer()
            Text(text("documents_hint")).font(.system(size: 10)).foregroundColor(ink.opacity(0.3)).multilineTextAlignment(.center)
        }.padding(.top, 12)
    }

    private var albumsView: some View {
        VStack(spacing: 12) {
            HStack { Text(text("mixtapes")).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(ink.opacity(0.48)); Spacer(); Button { showCreate = true; impact() } label: { Label(text("new"), systemImage: "plus").font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(accent).padding(.horizontal, 12).padding(.vertical, 8).background(accent.opacity(0.12), in: Capsule()) } }
            if library.playlists.isEmpty { Spacer(); Image(systemName: "square.stack.3d.up").font(.system(size: 35)).foregroundColor(ink.opacity(0.18)); Text(text("no_albums")).font(.system(size: 14, weight: .semibold)).foregroundColor(ink.opacity(0.5)); Text(text("make_mixtape")).font(.system(size: 11)).foregroundColor(ink.opacity(0.3)); Spacer() }
            else { ScrollView { LazyVStack(spacing: 10) { ForEach(library.playlists) { playlist in playlistRow(playlist) } }.padding(.vertical, 2) } }
            Spacer(minLength: 0)
        }.padding(.top, 12)
    }

    private func playlistRow(_ playlist: MusicPlaylist) -> some View {
        let list = library.orderedTracks(for: playlist)
        return VStack(spacing: 9) {
            HStack(spacing: 11) {
                Button { selectedPlaylistID = playlist.id; showArtworkPicker = true } label: { playlistArt(playlist, size: 52) }
                VStack(alignment: .leading, spacing: 4) { Text(playlist.name).font(.system(size: 14, weight: .bold)).lineLimit(1); Text(String(format: text("track_count"), list.count)).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(ink.opacity(0.4)) }
                Spacer()
                Button { if let first = list.first { player.play(first, from: list); tab = .now } } label: { Image(systemName: "play.fill").font(.system(size: 15)).foregroundColor(accent).frame(width: 42, height: 42) }
                Menu { ForEach(library.tracks) { track in Button("\(library.orderedTracks(for: playlist).contains(where: { $0.id == track.id }) ? text("remove") : text("add")) · \(track.displayTitle)") { library.toggle(track, in: playlist.id) } } } label: { Image(systemName: "plus.circle").font(.system(size: 18)).foregroundColor(ink.opacity(0.55)).frame(width: 30, height: 42) }
            }
            if !list.isEmpty { ForEach(list) { track in HStack { Text(track.displayTitle).font(.system(size: 11, weight: .medium)).lineLimit(1); Spacer(); Button { library.toggle(track, in: playlist.id) } label: { Image(systemName: "minus.circle").foregroundColor(ink.opacity(0.35)) } }.padding(.leading, 63).padding(.trailing, 6) }.onMove { library.movePlaylistTrack(playlistID: playlist.id, from: $0, to: $1) } }
        }.padding(11).background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }

    private func trackList(_ tracks: [Track]) -> some View {
        VStack(spacing: 12) {
            HStack { Text("\(text("library_title")) / \(tracks.count)").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(ink.opacity(0.48)); Spacer(); Button { pickerFolders = false; showPicker = true } label: { Image(systemName: "plus").foregroundColor(accent).frame(width: 34, height: 34).background(accent.opacity(0.1), in: Circle()) } }
            if tracks.isEmpty { Spacer(); Image(systemName: "waveform").font(.system(size: 34)).foregroundColor(ink.opacity(0.2)); Text(text("quiet_library")).font(.system(size: 15, weight: .semibold)).foregroundColor(ink.opacity(0.5)); Button(text("import_music")) { pickerFolders = true; showPicker = true }.font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(accent).padding(.top, 4); Spacer() }
            else { ScrollView { LazyVStack(spacing: 5) { ForEach(tracks) { track in trackRow(track) } }.padding(.vertical, 2) } }
        }.padding(.top, 12)
    }

    private func trackRow(_ track: Track) -> some View {
        HStack(spacing: 11) {
            albumArt(size: 46, track: track)
            VStack(alignment: .leading, spacing: 4) { Text(track.displayTitle).font(.system(size: 13, weight: .bold)).lineLimit(1); Text(track.artist.isEmpty ? track.url.deletingPathExtension().lastPathComponent : track.artist).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(ink.opacity(0.42)).lineLimit(1) }
            Spacer(minLength: 0)
            Text(time(track.duration)).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(ink.opacity(0.38))
            Menu { ForEach(library.playlists) { playlist in Button("\(text("add_to")) \(playlist.name)") { library.toggle(track, in: playlist.id) } }; Button(text("remove_library"), role: .destructive) { library.remove(track) } } label: { Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold)).foregroundColor(ink.opacity(0.5)).frame(width: 28, height: 42) }
        }.padding(7).background(player.currentTrack?.id == track.id ? accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle()).onTapGesture { player.play(track, from: library.tracks); withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { tab = .now } }
    }

    private var fullPlayer: some View {
        ZStack { canvas.ignoresSafeArea(); VStack(spacing: 12) {
            Capsule().fill(ink.opacity(0.18)).frame(width: 35, height: 4).padding(.top, 9)
            HStack { Text(text("now_playing")).font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(accent); Spacer(); Button { showFullPlayer = false } label: { Image(systemName: "chevron.down").foregroundColor(ink.opacity(0.6)).frame(width: 34, height: 34) } }.padding(.top, 5)
            Spacer(minLength: 4); albumArt(size: 290, track: player.currentTrack).matchedGeometryEffect(id: "albumArt", in: artworkSpace).rotationEffect(.degrees(player.isPlaying ? 4 : 0)).animation(.spring(response: 0.6, dampingFraction: 0.62).repeatForever(autoreverses: true), value: player.isPlaying)
            VStack(spacing: 5) { Text(player.currentTrack?.displayTitle ?? text("nothing_playing")).font(.system(size: 24, weight: .bold, design: .rounded)).lineLimit(1); Text(player.currentTrack?.artist ?? text("add_tracks")).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(ink.opacity(0.48)) }.padding(.top, 6)
            timeline.padding(.horizontal, 3); controls.padding(.top, 7); Spacer(minLength: 3)
        }.padding(.horizontal, 24) }
    }

    private var lockOverlay: some View {
        ZStack { Color.black.opacity(0.93).ignoresSafeArea(); VStack(spacing: 20) { Image(systemName: "lock.fill").font(.system(size: 35)).foregroundColor(accent); Text(text("player_locked")).font(.system(size: 13, weight: .black, design: .monospaced)); Text(text("hold_unlock")).font(.system(size: 11)).foregroundColor(.white.opacity(0.42)); Circle().fill(accent.opacity(0.13)).frame(width: 88, height: 88).overlay(Image(systemName: "lock.open").font(.system(size: 25)).foregroundColor(accent)).onLongPressGesture(minimumDuration: 1.4, pressing: { pressing in if pressing { unlockStart = Date() } }, perform: { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { locked = false }; impact() }) }.foregroundColor(.white).contentShape(Rectangle()) }
    }

    private func albumArt(size: CGFloat, track: Track?) -> some View {
        Group {
            if size > 100 {
                VinylRecord(size: size, isPlaying: player.isPlaying)
            } else {
                ZStack {
                    if let image = track?.artwork { Image(uiImage: image).resizable().scaledToFill() }
                    else { LinearGradient(colors: [Color(red: 0.34, green: 0.14, blue: 0.1), Color(red: 0.08, green: 0.08, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: "waveform").font(.system(size: size * 0.25, weight: .light)).foregroundColor(accent) }
                }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(ink.opacity(0.14), lineWidth: 1))
            }
        }.frame(width: size, height: size).shadow(color: .black.opacity(size > 100 ? 0.48 : 0.3), radius: size > 100 ? 25 : 5, y: size > 100 ? 13 : 4).clipped()
    }
    private func playlistArt(_ playlist: MusicPlaylist, size: CGFloat) -> some View { Group { if let data = playlist.artworkData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() } else { LinearGradient(colors: [accent.opacity(0.8), Color.purple.opacity(0.65), .black], startPoint: .topLeading, endPoint: .bottomTrailing).overlay(Image(systemName: "waveform").foregroundColor(ink.opacity(0.8))) } }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 11)) }
    private var equalizer: some View { HStack(spacing: 3) { ForEach(0..<4) { i in Capsule().fill(accent.opacity(player.isPlaying ? 0.95 : 0.35)).frame(width: 3, height: player.isPlaying ? CGFloat([8, 15, 10, 18][i]) : 4).animation(.easeInOut(duration: Double(0.22 + Double(i) * 0.12)).repeatForever(autoreverses: true), value: player.isPlaying) } }.frame(height: 19, alignment: .center) }
    private func time(_ value: Double) -> String { guard value.isFinite else { return "0:00" }; return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
    private func icon(for tab: PlayerTab) -> String { switch tab { case .now: return "waveform"; case .tracks: return "music.note.list"; case .folders: return "folder"; case .albums: return "square.stack.3d.up" } }
    private func tabTitle(_ tab: PlayerTab) -> String { switch tab { case .now: return text("tab_now"); case .tracks: return text("tab_tracks"); case .folders: return text("tab_folders"); case .albums: return text("tab_albums") } }
    private func impact() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    private func saveSelectedArtwork() { guard let id = selectedPlaylistID, let data = selectedImage?.jpegData(compressionQuality: 0.85) else { return }; library.setArtwork(data, for: id); selectedImage = nil }
}

private struct VinylRecord: View {
    let size: CGFloat
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
            let secondsPerRotation = 5.6
            let angle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: secondsPerRotation) * 360 / secondsPerRotation
            record.rotationEffect(.degrees(angle))
        }.frame(width: size, height: size)
    }

    private var record: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(red: 0.28, green: 0.28, blue: 0.30), Color(red: 0.035, green: 0.035, blue: 0.04), Color(red: 0.16, green: 0.16, blue: 0.17), Color.black], center: .center, startRadius: size * 0.04, endRadius: size * 0.51))
            Circle().fill(AngularGradient(gradient: Gradient(stops: [
                .init(color: .white.opacity(0.18), location: 0), .init(color: .clear, location: 0.12),
                .init(color: .black.opacity(0.76), location: 0.26), .init(color: .white.opacity(0.12), location: 0.48),
                .init(color: .black.opacity(0.84), location: 0.68), .init(color: .white.opacity(0.14), location: 0.84),
                .init(color: .clear, location: 1)
            ]), center: .center))
            ForEach(0..<27, id: \.self) { index in
                let inset = size * (0.07 + CGFloat(index) * 0.012)
                Circle().stroke(LinearGradient(colors: [.white.opacity(index.isMultiple(of: 2) ? 0.17 : 0.06), .black.opacity(0.75), .white.opacity(0.09)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: index.isMultiple(of: 3) ? 1.15 : 0.65).padding(inset)
            }
            Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.04, blue: 0.05), Color(red: 0.77, green: 0.0, blue: 0.015), Color(red: 0.98, green: 0.025, blue: 0.035)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: size * 0.34, height: size * 0.34)
            Circle().stroke(.white.opacity(0.18), lineWidth: 1).frame(width: size * 0.19, height: size * 0.19)
            Circle().fill(Color.white).frame(width: size * 0.036, height: size * 0.036)
        }.frame(width: size, height: size).clipShape(Circle()).overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
    }
}
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
    let isLight: Bool
    let languageCode: String
    let accentColor: Color
    let onCreate: (String) -> Void
    var body: some View { let foreground = isLight ? Color(red: 0.08, green: 0.09, blue: 0.10) : Color.white; let background = isLight ? Color(red: 0.94, green: 0.94, blue: 0.92) : Color(red: 0.07, green: 0.07, blue: 0.08); return VStack(alignment: .leading, spacing: 16) { Text(playerText("new_mixtape", language: languageCode)).font(.system(size: 12, weight: .black, design: .monospaced)); TextField(playerText("album_name", language: languageCode), text: $name).padding(13).background(foreground.opacity(0.08), in: RoundedRectangle(cornerRadius: 11)); Button { onCreate(name); dismiss() } label: { Text(playerText("create_album", language: languageCode)).font(.system(size: 11, weight: .black, design: .monospaced)).frame(maxWidth: .infinity).padding(15).background(accentColor, in: RoundedRectangle(cornerRadius: 12)).foregroundColor(.black) }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }.foregroundColor(foreground).padding(22).background(background).preferredColorScheme(isLight ? .light : .dark) }
}

private struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController { let picker = UIImagePickerController(); picker.sourceType = .photoLibrary; picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate { let parent: ImagePicker; init(_ parent: ImagePicker) { self.parent = parent }; func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { parent.image = info[.originalImage] as? UIImage; parent.dismiss() }; func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() } }
}

private func playerText(_ key: String, language: String) -> String {
    let values: [String: (String, String, String)] = [
        "subtitle": ("ПОРТАТИВНЫЙ АУДИОПЛЕЕР", "ПОРТАТИВНИЙ АУДІОПЛЕЄР", "PORTABLE AUDIO PLAYER"),
        "signal": ("СИГНАЛ / 001", "СИГНАЛ / 001", "SIGNAL / 001"),
        "nothing_playing": ("НИЧЕГО НЕ ИГРАЕТ", "НІЧОГО НЕ ГРАЄ", "NOTHING PLAYING"),
        "add_tracks": ("ДОБАВЬТЕ МУЗЫКУ", "ДОДАЙТЕ МУЗИКУ", "ADD MUSIC TO BEGIN"),
        "choose_track": ("Выберите трек", "Виберіть трек", "Choose a track"),
        "library": ("МУЗЫКАЛЬНАЯ БИБЛИОТЕКА", "МУЗИЧНА БІБЛІОТЕКА", "MUSIC LIBRARY"),
        "music_files": ("ВАШИ МУЗЫКАЛЬНЫЕ ФАЙЛЫ", "ВАШІ МУЗИЧНІ ФАЙЛИ", "YOUR MUSIC FILES"),
        "choose_folder": ("Выбрать папку с музыкой", "Вибрати папку з музикою", "Choose music folder"),
        "choose_files": ("ИЛИ ВЫБРАТЬ АУДИОФАЙЛЫ", "АБО ВИБРАТИ АУДІОФАЙЛИ", "OR SELECT AUDIO FILES"),
        "documents_hint": ("Музыка, переданная с компьютера, появится в папке «Файлы» этого приложения.", "Музика, передана з комп’ютера, з’явиться в папці «Файли» цього застосунку.", "Music copied from a computer appears in this app’s Files folder."),
        "mixtapes": ("МОИ МИКСТЕЙПЫ", "МОЇ МІКСТЕЙПИ", "YOUR MIXTAPES"),
        "new": ("НОВЫЙ", "НОВИЙ", "NEW"),
        "no_albums": ("Пока нет альбомов", "Альбомів поки немає", "No albums yet"),
        "make_mixtape": ("Создайте сборник из своих треков", "Створіть збірку зі своїх треків", "Make a mixtape from your tracks"),
        "track_count": ("ТРЕКОВ: %d", "ТРЕКІВ: %d", "%d TRACKS"),
        "add": ("Добавить", "Додати", "Add"),
        "remove": ("Убрать", "Видалити", "Remove"),
        "library_title": ("БИБЛИОТЕКА", "БІБЛІОТЕКА", "LIBRARY"),
        "quiet_library": ("Здесь пока тихо", "Тут поки тихо", "Your library is quiet"),
        "import_music": ("ИМПОРТИРОВАТЬ МУЗЫКУ", "ІМПОРТУВАТИ МУЗИКУ", "IMPORT MUSIC"),
        "add_to": ("Добавить в", "Додати до", "Add to"),
        "remove_library": ("Удалить из библиотеки", "Видалити з бібліотеки", "Remove from library"),
        "now_playing": ("СЕЙЧАС ИГРАЕТ", "ЗАРАЗ ГРАЄ", "NOW PLAYING"),
        "player_locked": ("ПЛЕЕР ЗАБЛОКИРОВАН", "ПЛЕЄР ЗАБЛОКОВАНО", "PLAYER LOCKED"),
        "hold_unlock": ("Удерживайте, чтобы разблокировать", "Утримуйте, щоб розблокувати", "Touch and hold to unlock"),
        "track_position": ("Позиция в треке", "Позиція у треку", "Track position"),
        "theme": ("ТЕМА", "ТЕМА", "THEME"),
        "dark": ("Тёмная", "Темна", "Dark"),
        "light": ("Светлая", "Світла", "Light"),
        "accent": ("ЦВЕТ АКЦЕНТА", "КОЛІР АКЦЕНТУ", "ACCENT COLOR"),
        "language": ("ЯЗЫК", "МОВА", "LANGUAGE"),
        "settings": ("Настройки оформления", "Налаштування вигляду", "Appearance settings"),
        "color_0": ("Оранжевый", "Помаранчевий", "Orange"),
        "color_1": ("Лаймовый", "Лаймовий", "Lime"),
        "color_2": ("Синий", "Синій", "Blue"),
        "color_3": ("Фиолетовый", "Фіолетовий", "Violet"),
        "color_4": ("Белый", "Білий", "White"),
        "color_5": ("Чёрный", "Чорний", "Black"),
        "new_mixtape": ("НОВЫЙ МИКСТЕЙП", "НОВИЙ МІКСТЕЙП", "NEW MIXTAPE"),
        "album_name": ("Название альбома", "Назва альбому", "Album name"),
        "create_album": ("СОЗДАТЬ АЛЬБОМ", "СТВОРИТИ АЛЬБОМ", "CREATE ALBUM"),
        "error_title": ("ОШИБКА", "ПОМИЛКА", "ERROR"),
        "ok": ("ПОНЯТНО", "ЗРОЗУМІЛО", "OK")
    ]
    guard let value = values[key] else { return key }
    switch language { case "ru": return value.0; case "uk": return value.1; default: return value.2 }
}
