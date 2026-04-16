import Foundation
import os

/// Thin wrapper around os.Logger with pre-bound subsystem and a category per
/// subsystem. Viewable with:
///   log stream --predicate 'subsystem == "com.KaiSong06.better-mac"'
enum Log {
    static let subsystem = "com.KaiSong06.better-mac"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let island = Logger(subsystem: subsystem, category: "island")
    static let media = Logger(subsystem: subsystem, category: "media")
    static let spotify = Logger(subsystem: subsystem, category: "spotify")
    static let volume = Logger(subsystem: subsystem, category: "volume")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let perm = Logger(subsystem: subsystem, category: "permissions")
}
