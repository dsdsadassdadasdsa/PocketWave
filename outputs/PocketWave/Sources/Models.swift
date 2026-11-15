import Foundation
import UIKit

struct Track: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var artist: String
    var album: String
    var url: URL
    var duration: Double = 0
    var artworkData: Data? = nil

    var artwork: UIImage? { artworkData.flatMap(UIImage.init(data:)) }
    var displayTitle: String { title.isEmpty ? url.deletingPathExtension().lastPathComponent : title }
}

struct MusicPlaylist: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var trackIDs: [UUID] = []
    var artworkData: Data? = nil
}

enum RepeatMode: Int, CaseIterable {
    case off, all, one
    var label: String { ["REPEAT OFF", "REPEAT ALL", "REPEAT ONE"][rawValue] }
}
