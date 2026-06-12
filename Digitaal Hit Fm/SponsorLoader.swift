import SwiftUI
import UIKit
import Combine

struct SponsorEntry: Codable, Identifiable, Equatable {
    let name: String
    let imageURL: String
    let localLogo: String?
    var id: String { name }
}

struct SponsorsConfig: Codable {
    let sponsors: [SponsorEntry]
}

class SponsorLoader: ObservableObject {
    static let shared = SponsorLoader()

    @Published var sponsors: [SponsorEntry] = []
    @Published var images: [String: UIImage] = [:]

    private let url = URL(string: "https://digitaal911.com/app/sponsor/sponsors.json")!

    func load() {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let config = try? JSONDecoder().decode(SponsorsConfig.self, from: data) else { return }
            DispatchQueue.main.async { self.sponsors = config.sponsors }
            self.downloadImages(for: config.sponsors)
        }.resume()
    }

    private func downloadImages(for sponsors: [SponsorEntry]) {
        for sponsor in sponsors {
            guard let url = URL(string: sponsor.imageURL) else { continue }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async { self?.images[sponsor.id] = image }
            }.resume()
        }
    }
}

struct SponsorCard: View {
    let sponsor: SponsorEntry
    let image: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if let local = sponsor.localLogo, let fallback = UIImage(named: local) {
                    Image(uiImage: fallback).resizable().scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.systemGray5))
                        .overlay(Text(sponsor.name).font(.caption).multilineTextAlignment(.center).padding(6))
                }
            }
            .frame(width: 100, height: 100)
            .cornerRadius(10)

            Text(sponsor.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.07), radius: 5, x: 0, y: 2)
    }
}
