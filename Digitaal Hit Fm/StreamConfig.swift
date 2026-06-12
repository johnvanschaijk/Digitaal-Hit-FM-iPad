import Foundation
import Combine

struct StreamEntry: Codable, Identifiable, Equatable {
    let name: String
    let streamURL: String
    let metadataURL: String
    let logoURL: String
    let localLogo: String?
    let subtitle: String

    var id: String { name }
}

struct AppConfig: Codable {
    let streams: [StreamEntry]
}

class ConfigLoader: ObservableObject {
    static let shared = ConfigLoader()

    @Published var streams: [StreamEntry] = []
    @Published var isLoading = true

    private let configURL = URL(string: "https://digitaal911.com/app/config.json")!

    func load() {
        isLoading = true
        var request = URLRequest(url: configURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                self?.isLoading = false
                guard let data = data,
                      let config = try? JSONDecoder().decode(AppConfig.self, from: data) else { return }
                self?.streams = config.streams
            }
        }.resume()
    }

    func stream(named name: String) -> StreamEntry? {
        streams.first { $0.name == name }
    }
}
