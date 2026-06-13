import SwiftUI
import Foundation
import Combine
import SafariServices

// MARK: - Model

struct NewsEntry: Identifiable {
    let id: String
    let title: String
    let summary: String
    let link: URL?
    let published: String
}

// MARK: - Loader

@MainActor
class NewsLoader: ObservableObject {
    @Published var entries: [NewsEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let feedURL = URL(string: "https://www.mooiberghem.nl/index.php?format=feed&type=atom")!

    func load() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                var request = URLRequest(url: feedURL)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, _) = try await URLSession.shared.data(for: request)
                entries = AtomFeedParser(data: data).parse()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Atom parser

private class AtomFeedParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var entries: [NewsEntry] = []

    private var inEntry = false
    private var currentElement = ""
    private var currentID = ""
    private var currentTitle = ""
    private var currentSummary = ""
    private var currentLink = ""
    private var currentPublished = ""

    init(data: Data) { self.data = data }

    func parse() -> [NewsEntry] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String]) {
        currentElement = elementName
        if elementName == "entry" {
            inEntry = true
            currentID = ""; currentTitle = ""; currentSummary = ""
            currentLink = ""; currentPublished = ""
        }
        if elementName == "link", inEntry, let href = attributeDict["href"] {
            currentLink = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inEntry else { return }
        switch currentElement {
        case "title":     currentTitle     += string
        case "summary":   currentSummary   += string
        case "content":   currentSummary   += string
        case "published": currentPublished += string
        case "updated":   if currentPublished.isEmpty { currentPublished += string }
        case "id":        currentID        += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "entry" {
            entries.append(NewsEntry(
                id: currentID.isEmpty ? currentLink : currentID,
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines).strippingHTML(),
                summary: currentSummary.trimmingCharacters(in: .whitespacesAndNewlines).strippingHTML(),
                link: URL(string: currentLink),
                published: formatAtomDate(currentPublished.trimmingCharacters(in: .whitespacesAndNewlines))
            ))
            inEntry = false
        }
        currentElement = ""
    }
}

private func formatAtomDate(_ raw: String) -> String {
    let iso = ISO8601DateFormatter()
    for options: ISO8601DateFormatter.Options in [
        [.withInternetDateTime, .withFractionalSeconds],
        [.withInternetDateTime]
    ] {
        iso.formatOptions = options
        if let date = iso.date(from: raw) {
            let df = DateFormatter()
            df.locale = Locale(identifier: "nl_NL")
            df.dateStyle = .medium
            df.timeStyle = .none
            return df.string(from: date)
        }
    }
    return raw
}

private extension String {
    func strippingHTML() -> String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - View

struct NewsView: View {
    @StateObject private var loader = NewsLoader()
    @Environment(\.dismiss) private var dismiss
    @State private var showSafari = false
    @State private var selectedURL: URL?

    var body: some View {
        NavigationView {
            Group {
                if loader.isLoading {
                    ProgressView("Nieuws laden...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let msg = loader.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle).foregroundColor(.red)
                        Text(msg).multilineTextAlignment(.center).padding()
                        Button("Opnieuw proberen") { loader.load() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if loader.entries.isEmpty {
                    Text("Geen nieuws gevonden")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(loader.entries) { entry in
                        Button {
                            guard let url = entry.link else { return }
                            selectedURL = url
                            showSafari = true
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.title)
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .multilineTextAlignment(.leading)
                                if !entry.summary.isEmpty {
                                    Text(entry.summary)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }
                                Text(entry.published)
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Nieuws")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Sluiten") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { loader.load() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear { loader.load() }
            .sheet(isPresented: $showSafari) {
                if let url = selectedURL {
                    NewsSafariView(url: url)
                        .ignoresSafeArea()
                }
            }
        }
    }
}

private struct NewsSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = .systemRed
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
