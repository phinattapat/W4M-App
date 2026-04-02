import SwiftUI
import AppKit
import Combine
import ServiceManagement

// --- THE BRAIN (Logic) ---
class WallpaperVM: ObservableObject {
    @AppStorage("favoritePaths") var favoritePathsData: Data = Data() // Stores Set<String> as Data
        
        // Helper to get/set favorites as a Set
        var favoritePaths: Set<String> {
            get {
                (try? JSONDecoder().decode(Set<String>.self, from: favoritePathsData)) ?? []
            }
            set {
                if let data = try? JSONEncoder().encode(newValue) {
                    favoritePathsData = data
                }
            }
        }

        // --- THE FIX: This provides the sorted list for your View ---
        var sortedWallpapers: [URL] {
            wallpaperURLs.sorted { url1, url2 in
                let fav1 = favoritePaths.contains(url1.path)
                let fav2 = favoritePaths.contains(url2.path)
                
                if fav1 != fav2 {
                    return fav1 // Favorites float to the top
                }
                return url1.lastPathComponent < url2.lastPathComponent // Then alphabetical
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
            objectWillChange.send() // Ensure UI updates
        }
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            // Safe system update on the main thread
            DispatchQueue.main.async {
                do {
                    if self.launchAtLogin {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Failed to update login item: \(error)")
                }
            }
        }
    }

    // Your existing variables
    @AppStorage("wallpaperFolderPath") var folderPathString: String = ""
    @AppStorage("lastUsedWallpaper") var lastUsedWallpaperPath: String = ""
    
    // 💡 THE FIX: Stripped of side-effects. Just a plain variable now.
    @Published var changeAllScreens: Bool
    
    @Published var wallpaperURLs: [URL] = []
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
            let didStart = url.startAccessingSecurityScopedResource()
            
            self.folderPathString = url.path
            fetchWallpapers()
            
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
    }

    func fetchWallpapers() {
        guard !folderPathString.isEmpty else { return }
        let url = URL(fileURLWithPath: folderPathString)
        
        let didStart = url.startAccessingSecurityScopedResource()
        
        DispatchQueue.global(qos: .userInitiated).async {
            let files = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            
            let foundURLs = files?.filter {
                let ext = $0.pathExtension.lowercased()
                return ["jpg", "jpeg", "png", "heic", "webp"].contains(ext)
            } ?? []

            DispatchQueue.main.async {
                if self.wallpaperURLs != foundURLs {
                    self.wallpaperURLs = foundURLs
                }
                
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
    }
    private var lastUpdate: Date = .distantPast

    func updateWallpaper(to url: URL) {
        // 1. Prevent "Spamming" (The BSBlockSentinel fix)
        // If less than 0.5s has passed, ignore the click.
        guard Date().timeIntervalSince(lastUpdate) > 0.5 else { return }
        lastUpdate = Date()

        // 2. All Wallpaper calls MUST be on Main Thread (The Scene fix)
        DispatchQueue.main.async {
            self.lastUsedWallpaperPath = url.path
            
            let screens = self.changeAllScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
            
            for screen in screens {
                do {
                    // macOS 14+ prefers this on the main thread
                    try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                } catch {
                    // ONLY this print matters. If this doesn't trigger, you're fine.
                    print("ACTUAL ERROR: \(error)")
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
            for screen in NSScreen.screens {
                try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            }
        }
    }
    
    func startMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
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
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.black.opacity(0.2) }
                .frame(width: 130, height: 85).cornerRadius(10).clipped()
                .blur(radius: isActive ? 8 : 0)
                
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

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { }
}
