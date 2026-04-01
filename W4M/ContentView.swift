import SwiftUI
import AppKit
import Combine

// --- THE BRAIN (Logic) ---
class WallpaperVM: ObservableObject {
    @AppStorage("wallpaperFolderPath") var folderPathString: String = ""
    @AppStorage("lastUsedWallpaper") var lastUsedWallpaperPath: String = ""
    
    @Published var changeAllScreens: Bool {
        didSet { UserDefaults.standard.set(changeAllScreens, forKey: "changeAllScreens") }
    }
    
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
            self.folderPathString = url.path
            fetchWallpapers()
        }
    }

    func fetchWallpapers() {
        let url = URL(fileURLWithPath: folderPathString)
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            let files = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            self.wallpaperURLs = files?.filter {
                ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased())
            }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) ?? []
        }
    }

    func updateWallpaper(to url: URL) {
            // 🔥 THE FIX: Push this save action to the Main Thread so SwiftUI doesn't crash
            DispatchQueue.main.async {
                self.lastUsedWallpaperPath = url.path
            }
            
            let workspace = NSWorkspace.shared
            
            if changeAllScreens {
                for screen in NSScreen.screens {
                    try? workspace.setDesktopImageURL(url, for: screen, options: [:])
                }
            } else {
                if let mainScreen = NSScreen.main {
                    try? workspace.setDesktopImageURL(url, for: mainScreen, options: [:])
                }
            }
        }

    // THE MAGIC: Watches for space changes and re-applies the wallpaper
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
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in
                if !self.folderPathString.isEmpty { self.fetchWallpapers() }
            }
        }
    }
}

// --- THE UI ---
struct MainMenuView: View {
    @ObservedObject var vm: WallpaperVM
    @State private var activeURL: URL? = nil
    @State private var isTransitioning = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("W4M").font(.system(size: 16, weight: .black, design: .monospaced))
                            Text(vm.folderPathString.isEmpty ? "NO SOURCE" : "\(vm.wallpaperURLs.count) IMAGES")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        
                        Picker("", selection: $vm.changeAllScreens) {
                            Text("Current").tag(false)
                            Text("All Screens").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                        .labelsHidden()
                        
                        Button(action: vm.selectFolder) {
                            Image(systemName: "folder.fill.badge.plus")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                    }
                    .padding()
                }
                .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))

                Divider()

                if vm.folderPathString.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "display.2")
                            .font(.system(size: 40))
                            .foregroundColor(.gray.opacity(0.2))
                        
                        Button("SELECT SOURCE FOLDER", action: vm.selectFolder)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
                    .frame(width: 440, height: 400)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: [
                            GridItem(.fixed(130), spacing: 12),
                            GridItem(.fixed(130), spacing: 12),
                            GridItem(.fixed(130), spacing: 12)
                        ], spacing: 15) {
                            ForEach(vm.wallpaperURLs, id: \.self) { url in
                                WallpaperItem(url: url, isActive: activeURL == url) {
                                    triggerChange(url: url)
                                }
                            }
                        }
                        .padding()
                    }
                    .frame(width: 440, height: 520)
                }

                Divider()
                
                HStack {
                    Button("QUIT") { NSApplication.shared.terminate(nil) }
                        .font(.system(size: 10, weight: .bold))
                        .buttonStyle(.plain)
                        .opacity(0.4)
                    Spacer()
                    if vm.changeAllScreens {
                        Text("MODE: BROADCAST")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.blue)
                            .opacity(0.8)
                    }
                }
                .padding(12)
            }

            Color.black
                .opacity(isTransitioning ? 0.4 : 0)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: isTransitioning)
        }
    }

    func triggerChange(url: URL) {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.6)) {
            activeURL = url
            isTransitioning = true
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) {
            vm.updateWallpaper(to: url)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.easeOut(duration: 0.3)) {
                    activeURL = nil
                    isTransitioning = false
                }
            }
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
