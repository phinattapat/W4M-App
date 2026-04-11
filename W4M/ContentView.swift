import SwiftUI
import AppKit
import Combine
import ServiceManagement
import AVKit

class WallpaperVM: ObservableObject {
    @AppStorage("favoritePaths") var favoritePathsData: Data = Data()
    @Published var activeTab: String = "Photos"
    @Published var photoURLs: [URL] = []
    @Published var videoURLs: [URL] = []

    var favoritePaths: Set<String> {
        get { (try? JSONDecoder().decode(Set<String>.self, from: favoritePathsData)) ?? [] }
        set { if let data = try? JSONEncoder().encode(newValue) { favoritePathsData = data } }
    }

    var currentWallpapers: [URL] {
        let currentSource = (activeTab == "Photos" ? photoURLs : videoURLs)
        return currentSource.sorted { url1, url2 in
            let fav1 = favoritePaths.contains(url1.path)
            let fav2 = favoritePaths.contains(url2.path)
            if fav1 != fav2 { return fav1 }
            return url1.lastPathComponent < url2.lastPathComponent
        }
    }

    func toggleFavorite(url: URL) {
        var current = favoritePaths
        if current.contains(url.path) { current.remove(url.path) }
        else { current.insert(url.path) }
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

    func fetchWallpapers() {
        guard !folderPathString.isEmpty else { return }
        let url = URL(fileURLWithPath: folderPathString)
        DispatchQueue.global(qos: .userInitiated).async {
            let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            let photos = files.filter { ["jpg", "jpeg", "png", "heic", "webp"].contains($0.pathExtension.lowercased()) }
            let videos = files.filter { ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }
            DispatchQueue.main.async {
                self.photoURLs = photos
                self.videoURLs = videos
            }
        }
    }

    private var lastUpdate: Date = .distantPast

    func updateWallpaper(to url: URL) {
        guard Date().timeIntervalSince(lastUpdate) > 0.5 else { return }
        lastUpdate = Date()

        DispatchQueue.main.async {
            self.lastUsedWallpaperPath = url.path
            let isVideo = ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
            
            if isVideo {
                LiveWallManager.shared.playVideo(url: url, allScreens: self.changeAllScreens)
                self.setStaticThumbnail(from: url)
            } else {
                LiveWallManager.shared.stopAll()
                self.applySystemWallpaper(url: url)
            }
        }
    }

    private func setStaticThumbnail(from url: URL) {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let timestamp = CMTime(seconds: 0, preferredTimescale: 60)
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let imageRef = try generator.copyCGImage(at: timestamp, actualTime: nil)
                
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let appDir = appSupport.appendingPathComponent("W4M", isDirectory: true)
                try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
                
                // Using a unique ID ensures macOS doesn't ignore the change due to caching
                let uniqueID = UUID().uuidString
                let destinationURL = appDir.appendingPathComponent("lock_bg_\(uniqueID).jpg")
                
                let bitmapRep = NSBitmapImageRep(cgImage: imageRef)
                if let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) {
                    // Cleanup old thumbs first
                    let existingFiles = (try? FileManager.default.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil)) ?? []
                    for file in existingFiles { try? FileManager.default.removeItem(at: file) }
                    
                    try jpegData.write(to: destinationURL)
                    
                    DispatchQueue.main.async {
                        self.applySystemWallpaper(url: destinationURL)
                    }
                }
            } catch {
                print("Thumbnail failed: \(error)")
            }
        }
    }

    private func applySystemWallpaper(url: URL) {
        let path = url.path
        
        // --- THE AGGRESSIVE FIX ---
        // This AppleScript manually iterates through every desktop "Space" and monitor
        // to force the picture to update. This usually bypasses the "lazy" UI update.
        let scriptSource = """
        tell application "System Events"
            set desktopCount to count of desktops
            repeat with i from 1 to desktopCount
                set picture of desktop i to "\(path)"
            end repeat
        end tell
        """
        
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }

        // Secondary backup using standard API for the login screen logic
        let screens = self.changeAllScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        for screen in screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    private func setupSpaceObserver() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, !self.lastUsedWallpaperPath.isEmpty else { return }
            let url = URL(fileURLWithPath: self.lastUsedWallpaperPath)
            
            let isVideo = ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
            if !isVideo {
                self.applySystemWallpaper(url: url)
            } else {
                // For videos, find the latest thumbnail in App Support and re-apply
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let appDir = appSupport.appendingPathComponent("W4M")
                if let latestThumb = try? FileManager.default.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil).first {
                    self.applySystemWallpaper(url: latestThumb)
                }
            }
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
