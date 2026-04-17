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

    // --- AUTO CHANGE SETTINGS ---
    @AppStorage("autoChangeEnabled") var autoChangeEnabled: Bool = false {
        didSet { setupAutoChangeTimer() }
    }
    
    @AppStorage("autoChangeHH") var autoChangeHH: Int = 1
    @AppStorage("autoChangeMM") var autoChangeMM: Int = 0
    @AppStorage("autoChangeSS") var autoChangeSS: Int = 0

    var autoChangeInterval: Double {
        let total = (autoChangeHH * 3600) + (autoChangeMM * 60) + autoChangeSS
        return total > 0 ? Double(total) : 60
    }
    
    private var autoChangeTimer: AnyCancellable?

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
        setupAutoChangeTimer()
        restoreWallpaperOnLaunch()
    }
    
    func setupAutoChangeTimer() {
        autoChangeTimer?.cancel()
        guard autoChangeEnabled else { return }
        
        autoChangeTimer = Timer.publish(every: autoChangeInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pickRandomWallpaper()
            }
    }

    func pickRandomWallpaper() {
        let source = currentWallpapers
        guard !source.isEmpty else { return }
        if let randomURL = source.randomElement() {
            updateWallpaper(to: randomURL)
        }
    }

    private func restoreWallpaperOnLaunch() {
        guard !lastUsedWallpaperPath.isEmpty else { return }
        let url = URL(fileURLWithPath: lastUsedWallpaperPath)
        let isVideo = ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
        
        if isVideo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                LiveWallManager.shared.playVideo(url: url, allScreens: self.changeAllScreens)
            }
        }
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

    func updateWallpaper(to url: URL, targetScreen: NSScreen? = nil) {
        guard Date().timeIntervalSince(lastUpdate) > 0.5 else { return }
        lastUpdate = Date()

        DispatchQueue.main.async {
            self.lastUsedWallpaperPath = url.path
            let isVideo = ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
            
            if isVideo {
                // Pass targetScreen through to the manager
                LiveWallManager.shared.playVideo(url: url, allScreens: self.changeAllScreens, targetScreen: targetScreen)
                self.setStaticThumbnail(from: url)
            } else {
                // If user selects a static photo, decide if we stop ALL videos or just for that screen
                if self.changeAllScreens {
                    LiveWallManager.shared.stopAll()
                }
                self.applySystemWallpaper(url: url, targetScreen: targetScreen)
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
                
                let uniqueID = UUID().uuidString
                let destinationURL = appDir.appendingPathComponent("lock_bg_\(uniqueID).jpg")
                
                let bitmapRep = NSBitmapImageRep(cgImage: imageRef)
                if let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) {
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

    private func applySystemWallpaper(url: URL, targetScreen: NSScreen? = nil) {
        let screens: [NSScreen]
        if self.changeAllScreens {
            screens = NSScreen.screens
        } else {
            screens = [targetScreen ?? NSScreen.main].compactMap { $0 }
        }
        
        for screen in screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
        
        // AppleScript fallback for "All Screens" to ensure system consistency
        if self.changeAllScreens {
            let path = url.path
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
