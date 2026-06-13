import SwiftUI
import AVKit
import WebKit
import SafariServices

// MARK: - Web View Wrapper

struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    let onDismiss: () -> Void
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            AppLogger.shared.log(event: "WebView.loaded", details: webView.url?.absoluteString ?? "unknown")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            AppLogger.shared.log(event: "WebView.error", details: error.localizedDescription)
        }
    }
}

struct iPadMainView: View {
    @StateObject private var radioPlayer = RadioPlayer.shared
    @ObservedObject private var configLoader = ConfigLoader.shared
    @ObservedObject private var sponsorLoader = SponsorLoader.shared
    @State private var selectedStreamName = ""
    @State private var rightTab = 0
    @State private var showInfo = false

    private var currentStream: StreamEntry? {
        configLoader.stream(named: selectedStreamName)
    }

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    // ── LEFT PANEL: Player ──────────────────────────────
                    playerPanel
                        .frame(width: geo.size.width * 0.42)

                    Divider()

                    // ── RIGHT PANEL: Sponsors / Nieuws ─────────────────
                    rightPanel
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    stationMenu
                }
                ToolbarItem(placement: .principal) {
                    Text(selectedStreamName)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        RoutePickerViewiPad()
                            .frame(width: 36, height: 36)
                        Button { showInfo = true } label: {
                            Image(systemName: "info.circle")
                        }
                    }
                }
            }
            .onAppear {
                configLoader.load()
                sponsorLoader.load()
            }
            .onChange(of: configLoader.streams) { _, streams in
                guard let first = streams.first, selectedStreamName.isEmpty else { return }
                selectedStreamName = first.name
                radioPlayer.currentStreamName = first.name
                radioPlayer.setStream(streamURL: first.streamURL, metadataURL: first.metadataURL)
            }
            .sheet(isPresented: $showInfo) {
                iPadInfoView()
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Player Panel

    private var playerPanel: some View {
        VStack(spacing: 28) {
            // Logo
            AsyncImage(url: URL(string: currentStream?.logoURL ?? "")) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFit()
                default:
                    Image(currentStream?.localLogo ?? "digitaal_hit_fm_zwart")
                        .resizable().scaledToFit()
                }
            }
            .id(selectedStreamName)
            .frame(height: 200)
            .padding(.top, 24)

            // Subtitle
            Text(currentStream?.subtitle ?? " ")
                .font(.custom("Snell Roundhand", size: 26))
                .bold()
                .foregroundColor(.red)

            // Now Playing
            VStack(spacing: 6) {
                let isLoading = radioPlayer.artist == "Loading artist..." || radioPlayer.title == "Loading title..."
                let hasData = !radioPlayer.artist.isEmpty || !radioPlayer.title.isEmpty

                if radioPlayer.isBuffering {
                    Text("Loading Stream...")
                        .font(.title3).bold().foregroundColor(.gray)
                    Text(" ").font(.title3)
                } else if !isLoading && hasData {
                    Text(radioPlayer.artist)
                        .font(.title3).bold().foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    Text(radioPlayer.title)
                        .font(.title3).bold()
                        .multilineTextAlignment(.center)
                } else {
                    Text(selectedStreamName)
                        .font(.title3).bold()
                    Text(isLoading ? "Loading..." : " ").font(.title3)
                }
            }
            .frame(minHeight: 70)
            .padding(.horizontal)

            // Play / Pause
            Button {
                radioPlayer.togglePlayback()
            } label: {
                Image(systemName: radioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .resizable()
                    .frame(width: 90, height: 90)
                    .foregroundColor(radioPlayer.isPlaying ? .red : .primary)
            }

            // Volume
            VStack(spacing: 4) {
                Text("Volume")
                    .font(.caption).foregroundColor(.secondary)
                Slider(value: Binding(
                    get: { radioPlayer.volume },
                    set: { radioPlayer.volume = $0 }
                ), in: 0...1)
                Text("\(Int(radioPlayer.volume * 100))%")
                    .font(.caption2).foregroundColor(.red)
            }
            .padding(.horizontal, 32)
            .accentColor(.black)

            Spacer()

            // Footer
            VStack(spacing: 4) {
                let year = String(Calendar.current.component(.year, from: Date()))
                Text("© \(year) Digitaal Hit FM")
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 16) {
                    Link("digitaalhitfm.online", destination: URL(string: "https://digitaalhitfm.online")!)
                    Link("digitaal911.com", destination: URL(string: "https://digitaal911.com")!)
                }
                .font(.caption).foregroundColor(.red)
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            Picker("", selection: $rightTab) {
                Text("Sponsors").tag(0)
                Text("Mooi Berghem").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(16)

            if rightTab == 0 {
                sponsorsGrid
            } else {
                NewsPanel()
            }
        }
    }

    private var sponsorsGrid: some View {
        ScrollView {
            if sponsorLoader.sponsors.isEmpty {
                ProgressView("Sponsors laden...")
                    .padding(.top, 60)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 16
                ) {
                    ForEach(sponsorLoader.sponsors) { sponsor in
                        SponsorCard(sponsor: sponsor, image: sponsorLoader.images[sponsor.id])
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Station Menu

    private var stationMenu: some View {
        Menu {
            ForEach(configLoader.streams) { stream in
                Button {
                    selectedStreamName = stream.name
                    radioPlayer.currentStreamName = stream.name
                    radioPlayer.artist = "Loading artist..."
                    radioPlayer.title = "Loading title..."
                    radioPlayer.setStream(streamURL: stream.streamURL, metadataURL: stream.metadataURL)
                } label: {
                    Text(stream.name)
                }
            }
        } label: {
            HStack {
                Image(systemName: "music.note.list")
                Text("Station").fontWeight(.medium)
            }
            .foregroundColor(.primary)
        }
    }
}

// MARK: - News Panel (embedded)

private struct NewsPanel: View {
    @StateObject private var loader = NewsLoader()
    @State private var showSafari = false
    @State private var selectedURL: URL?

    var body: some View {
        Group {
            if loader.isLoading {
                ProgressView("Nieuws laden...").padding(.top, 60)
            } else if let msg = loader.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.red)
                    Text(msg).multilineTextAlignment(.center).padding()
                    Button("Opnieuw") { loader.load() }
                }
                .padding(.top, 40)
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title).font(.headline).foregroundColor(.primary)
                            if !entry.summary.isEmpty {
                                Text(entry.summary).font(.caption).foregroundColor(.secondary).lineLimit(2)
                            }
                            Text(entry.published).font(.caption2).foregroundColor(.red)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear { loader.load() }
        .sheet(isPresented: $showSafari) {
            if let url = selectedURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = .systemRed
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Info Sheet

private struct iPadInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var radioPlayer = RadioPlayer.shared

    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–" }
    private var buildNumber: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–" }

    var body: some View {
        NavigationView {
            List {
                Section("Applicatie") {
                    iPadInfoRow(label: "Naam", value: "Digitaal Hit FM iPad")
                    iPadInfoRow(label: "Versie", value: appVersion)
                    iPadInfoRow(label: "Build", value: buildNumber)
                }
                Section("Stream") {
                    iPadInfoRow(label: "Station", value: radioPlayer.currentStreamName.isEmpty ? "–" : radioPlayer.currentStreamName)
                    iPadInfoRow(label: "Status", value: radioPlayer.isBuffering ? "Buffering..." : (radioPlayer.isPlaying ? "Speelt af" : "Gepauzeerd"))
                    HStack {
                        Text("Buffer").foregroundColor(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(format: "%.1fs", radioPlayer.bufferSeconds)).monospacedDigit()
                            ProgressView(value: min(radioPlayer.bufferSeconds, 30), total: 30)
                                .progressViewStyle(.linear).accentColor(.red).frame(width: 140)
                        }
                    }
                }
                Section("Ontwikkelaar") {
                    iPadInfoRow(label: "Naam", value: "John van Schaijk")
                    Link(destination: URL(string: "https://vanschaijk.eu")!) {
                        Label("vanschaijk.eu", systemImage: "globe")
                    }
                }
                Section("Links") {
                    Link(destination: URL(string: "https://digitaalhitfm.online")!) { Label("digitaalhitfm.online", systemImage: "globe") }
                    Link(destination: URL(string: "https://digitaal911.com")!) { Label("digitaal911.com", systemImage: "globe") }
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Sluiten") { dismiss() } }
            }
        }
    }
}

private struct iPadInfoRow: View {
    let label: String; let value: String
    var body: some View {
        HStack { Text(label).foregroundColor(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }
    }
}

// MARK: - AirPlay picker

struct RoutePickerViewiPad: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.activeTintColor = .red
        v.tintColor = .black
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
