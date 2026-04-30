import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum TerminalUI {
    enum Stream {
        case stdout
        case stderr

        var file: FileHandle {
            switch self {
            case .stdout:
                return .standardOutput
            case .stderr:
                return .standardError
            }
        }

        var fileDescriptor: Int32 {
            switch self {
            case .stdout:
                return STDOUT_FILENO
            case .stderr:
                return STDERR_FILENO
            }
        }
    }

    enum Color: String {
        case green = "32"
        case red = "31"
        case yellow = "33"
        case cyan = "36"
        case dim = "2"
        case bold = "1"
    }

    static func isInteractive(_ stream: Stream) -> Bool {
        #if canImport(Darwin) || canImport(Glibc)
        isatty(stream.fileDescriptor) == 1
        #else
        false
        #endif
    }

    static func supportsANSI(_ stream: Stream) -> Bool {
        ProcessInfo.processInfo.environment["NO_COLOR"] == nil && isInteractive(stream)
    }

    static func styled(_ text: String, color: Color, stream: Stream = .stdout) -> String {
        guard supportsANSI(stream) else {
            return text
        }
        return "\u{001B}[\(color.rawValue)m\(text)\u{001B}[0m"
    }

    static func status(_ text: String, passed: Bool, stream: Stream = .stdout) -> String {
        styled(text, color: passed ? .green : .red, stream: stream)
    }

    static func write(_ text: String, stream: Stream = .stderr) {
        if let data = text.data(using: .utf8) {
            stream.file.write(data)
        }
    }

    static func writeLine(_ text: String, stream: Stream = .stderr) {
        write("\(text)\n", stream: stream)
    }

    static func progressLine(current: Int, total: Int, label: String, width: Int = 40, stream: Stream = .stderr) -> String {
        let clampedTotal = max(total, 1)
        let clampedCurrent = min(max(current, 0), clampedTotal)
        let ratio = Double(clampedCurrent) / Double(clampedTotal)
        let filled = Int((ratio * Double(width)).rounded(.down))
        let empty = max(width - filled, 0)
        let bar = String(repeating: "#", count: filled) + String(repeating: "-", count: empty)
        let percent = String(format: "%3.0f%%", ratio * 100)
        let highlightedPercent = styled(percent, color: .cyan, stream: stream)
        return "[\(bar)] \(highlightedPercent) \(clampedCurrent)/\(clampedTotal) \(label)"
    }

    static func table(title: String, rows: [(String, String)]) -> String {
        let metricWidth = max("Metric".count, rows.map { $0.0.count }.max() ?? 0)
        let valueWidth = max("Value".count, rows.map { $0.1.count }.max() ?? 0)
        let border = "+-\(String(repeating: "-", count: metricWidth))-+-\(String(repeating: "-", count: valueWidth))-+"
        var lines: [String] = []
        if title.isEmpty == false {
            lines.append(title)
        }
        lines.append(border)
        lines.append("| \(pad("Metric", to: metricWidth)) | \(pad("Value", to: valueWidth, alignRight: true)) |")
        lines.append(border)
        for row in rows {
            lines.append("| \(pad(row.0, to: metricWidth)) | \(pad(row.1, to: valueWidth, alignRight: true)) |")
        }
        lines.append(border)
        return lines.joined(separator: "\n")
    }

    private static func pad(_ text: String, to width: Int, alignRight: Bool = false) -> String {
        guard text.count < width else {
            return text
        }

        let padding = String(repeating: " ", count: width - text.count)
        return alignRight ? padding + text : text + padding
    }
}
