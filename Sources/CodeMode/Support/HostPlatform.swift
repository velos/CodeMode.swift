import Foundation

enum HostPlatform: String, Sendable {
    case iOS
    case macOS
    case watchOS
    case visionOS

    static let current: HostPlatform = {
        #if os(iOS)
        return .iOS
        #elseif os(macOS)
        return .macOS
        #elseif os(watchOS)
        return .watchOS
        #elseif os(visionOS)
        return .visionOS
        #else
        #error("Unsupported platform")
        #endif
    }()
}
