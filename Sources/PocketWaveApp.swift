import SwiftUI

@main
struct PocketWaveApp: App {
    @StateObject private var library = MusicLibrary()
    @StateObject private var player = AudioPlayerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
        }
    }
}
