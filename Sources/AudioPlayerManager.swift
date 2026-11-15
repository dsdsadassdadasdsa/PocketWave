import Foundation
import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isShuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var playbackError: String?
    private var audioPlayer: AVAudioPlayer?
    private var queue: [Track] = []
    private var timer: Timer?

    override init() { super.init(); configureAudio(); configureRemoteCommands() }
    private func configureAudio() {
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: []); try AVAudioSession.sharedInstance().setActive(true) } catch { }
    }
    func play(_ track: Track, from tracks: [Track]) {
        queue = tracks
        currentTrack = track
        playbackError = nil
        do {
            let p = try AVAudioPlayer(contentsOf: track.url)
            p.delegate = self; p.prepareToPlay(); audioPlayer = p; duration = p.duration; currentTime = 0
            p.play(); isPlaying = true; startTimer(); updateNowPlaying(); haptic(.medium)
        } catch { isPlaying = false; playbackError = error.localizedDescription }
    }
    func togglePlayPause() { guard let audioPlayer else { return }; if audioPlayer.isPlaying { audioPlayer.pause(); isPlaying = false } else { audioPlayer.play(); isPlaying = true }; updateNowPlaying(); haptic(.light) }
    func seek(to value: Double) { audioPlayer?.currentTime = value; currentTime = value; updateNowPlaying(); haptic(.selection) }
    func next() { advance(direction: 1) }
    func previous() { if currentTime > 3 { seek(to: 0) } else { advance(direction: -1) } }
    func toggleShuffle() { isShuffle.toggle(); haptic(.light) }
    func cycleRepeat() { repeatMode = RepeatMode(rawValue: (repeatMode.rawValue + 1) % 3) ?? .off; haptic(.light) }
    private func advance(direction: Int) {
        guard !queue.isEmpty else { return }
        if direction == 1 && repeatMode == .one { seek(to: 0); audioPlayer?.play(); isPlaying = true; return }
        let index = currentTrack.flatMap { t in queue.firstIndex(where: { $0.id == t.id }) } ?? 0
        let nextIndex = isShuffle && direction == 1 ? Int.random(in: queue.indices) : (index + direction + queue.count) % queue.count
        guard direction == 1 || index > 0 || repeatMode == .all else { return }
        play(queue[nextIndex], from: queue)
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if repeatMode == .one { seek(to: 0); player.play(); isPlaying = true } else if repeatMode == .all || queue.firstIndex(where: { $0.id == currentTrack?.id }) != queue.count - 1 { next() } else { isPlaying = false; currentTime = duration; updateNowPlaying() }
    }
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in guard let self, let p = self.audioPlayer else { return }; self.currentTime = p.currentTime; self.duration = p.duration }
        }
    }
    private func updateNowPlaying() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: track.displayTitle, MPMediaItemPropertyArtist: track.artist, MPMediaItemPropertyAlbumTitle: track.album, MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
        if let image = track.artwork { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.isPlaying == false { self?.togglePlayPause() } }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.isPlaying == true { self?.togglePlayPause() } }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: e.positionTime) }; return .success
        }
    }
    private enum Feedback { case light, medium, selection }
    private func haptic(_ kind: Feedback) { switch kind { case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred(); case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred(); case .selection: UISelectionFeedbackGenerator().selectionChanged() } }
}
