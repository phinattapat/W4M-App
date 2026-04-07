import SwiftUI
import AppKit
import Combine
import ServiceManagement
import AVKit

// --- THE BRAIN (Logic) ---
class WallpaperVM: ObservableObject {
    @AppStorage("favoritePaths") var favoritePathsData: Data = Data()
    
    // --- NEW: TAB & CATEGORY LOGIC ---
    @Published var activeTab: String = "Photos"
    @Published var photoURLs: [URL] = []
    @Published var videoURLs: [URL] = []

    // Helper to get/set favorites as a Set
    var favoritePaths: Set<String> {
        get { (try? JSONDecoder().decode(Set<String>.self, from: favoritePathsData)) ?? [] }
        set { if let data = try? JSONEncoder().encode(newValue) { favoritePathsData = data } }
    }

    // --- UPDATED: Returns the sorted list based on the ACTIVE TAB ---
    var currentWallpapers: [URL] {
        let currentSource = (activeTab == "Photos" ? photoURLs : videoURLs)
        return currentSource.sorted { url1, url2 in
            let fav1 = favoritePaths.contains(url1.path)
            let fav2 = favoritePaths.contains(url2.path)
            
            if fav1 != fav2 {
                return fav1 // Favorites float to the top
            }
            return url1.lastPathComponent < url2.lastPathComponent
        }
    }

    func toggleFavorite(url: URL) {
        var current = favoritePaths
        if current.contains(url.path) {
            current.remove(url.path)
        } else {
            current.insert(url.path)
        }
        favoritePaths = current
        objectWillChange.send()
    }

    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            DispatchQueue.main.async {
                do {
                    if self.launchAtLogin { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch { print("Failed to update login item: \(error)") }
            }
        }
    }

    @AppStorage("wallpaperFolderPath") var folderPathString: String = ""
    @AppStorage("lastUsedWallpaper") var lastUsedWallpaperPath: String = ""
    @Published var changeAllScreens: Bool
    
    private var spaceObserver: NSObjectProtocol?

    init() {
        self.changeAllScreens = UserDefaults.standard.bool(forKey: "changeAllScreens")
        if !folderPathString.isEmpty { fetchWallpapers() }
        startMonitoring()
        setupSpaceObserver()
    }

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"

        if panel.runModal() == .OK, let url = panel.url {
            self.folderPathString = url.path
            fetchWallpapers()
        }
    }

    // --- UPDATED: Scans for both Photos and Videos separately ---
    func fetchWallpapers() {
        guard !folderPathString.isEmpty else { return }
        let url = URL(fileURLWithPath: folderPathString)
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Use "?? []" to provide an empty array if the directory read fails
            let files = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? [] // This unwraps the optional safely
            
            let photos = files.filter {
                ["jpg", "jpeg", "png", "heic", "webp"].contains($0.pathExtension.lowercased())
            }
            
            let videos = files.filter {
                ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased())
            }

            DispatchQueue.main.async {
                self.photoURLs = photos
                self.videoURLs = videos
            }
        }
    }

    private var lastUpdate: Date = .distantPast

    // --- UPDATED: Handles switching between Static and Live Wallpapers ---
    func updateWallpaper(to url: URL) {
        guard Date().timeIntervalSince(lastUpdate) > 0.5 else { return }
        lastUpdate = Date()

        DispatchQueue.main.async {
            self.lastUsedWallpaperPath = url.path
            let isVideo = ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
            
            if isVideo {
                // Use the LiveWallManager engine for video files
                LiveWallManager.shared.playVideo(url: url, allScreens: self.changeAllScreens)
            } else {
                // Stop any running video and set static image via macOS system
                LiveWallManager.shared.stopAll()
                
                let screens = self.changeAllScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
                for screen in screens {
                    do {
                        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                    } catch {
                        print("ACTUAL ERROR: \(error)")
                    }
                }
            }
        }
    }

    private func setupSpaceObserver() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.changeAllScreens, !self.lastUsedWallpaperPath.isEmpty else { return }
            let url = URL(fileURLWithPath: self.lastUsedWallpaperPath)
            self.updateWallpaper(to: url)
        }
    }
    
    func startMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.fetchWallpapers()
        }
    }
}

// --- COMPONENTS ---
struct WallpaperItem: View {
    let url: URL
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                let isVideo = ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
                
                if isVideo {
                    // --- VIDEO PREVIEW ---
                    VideoPreviewView(url: url)
                        .frame(width: 130, height: 85)
                        .cornerRadius(10)
                        .clipped()
                        .blur(radius: isActive ? 8 : 0)
                } else {
                    // --- STATIC IMAGE ---
                    AsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Color.black.opacity(0.2) }
                    .frame(width: 130, height: 85)
                    .cornerRadius(10)
                    .clipped()
                    .blur(radius: isActive ? 8 : 0)
                }
                
                if isActive {
                    RoundedRectangle(cornerRadius: 10).stroke(Color.white, lineWidth: 3).shadow(radius: 10)
                    Image(systemName: "sparkles").foregroundColor(.white).font(.title2)
                }
            }
            .scaleEffect(isActive ? 1.25 : 1.0)
            .rotationEffect(.degrees(isActive ? 4 : 0))
            .shadow(color: .black.opacity(isActive ? 0.5 : 0.2), radius: isActive ? 20 : 4)
        }
        .buttonStyle(.plain)
    }
}
struct VideoPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        let player = AVPlayer(url: url)
        player.isMuted = true // Keep the UI quiet
        
        // Loop the preview
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
            player.seek(to: .zero)
            player.play()
        }
        
        view.player = player
        view.controlsStyle = .none // Hide play/pause buttons
        view.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
