import Foundation

final class AppLogger {
    static let shared = AppLogger()

    private init() {}

    func log(event: String, details: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[AppLogger] [\(timestamp)] event=\(event) details=\(details)")
    }
}

