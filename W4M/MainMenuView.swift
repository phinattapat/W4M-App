import SwiftUI
import Combine

// --- THE UI ---
struct MainMenuView: View {
    @ObservedObject var vm: WallpaperVM
    @State private var activeURL: URL? = nil
    @State private var isTransitioning = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // HEADER
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
                        .tint(.blue)
                        .accentColor(.blue)
                        // 💡 THE FIX: macOS 14+ requires (oldValue, newValue)
                        .onChange(of: vm.changeAllScreens) { oldValue, newValue in
                            
                            // Save the new setting to disk
                            UserDefaults.standard.set(newValue, forKey: "changeAllScreens")
                            
                            // Apply the wallpaper if needed
                            if newValue && !vm.lastUsedWallpaperPath.isEmpty {
                                let url = URL(fileURLWithPath: vm.lastUsedWallpaperPath)
                                vm.updateWallpaper(to: url)
                            }
                        }
                        
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

                // GRID
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
                
                // BOTTOM BAR
                HStack(alignment: .center, spacing: 15) {
                    Button("QUIT") { NSApplication.shared.terminate(nil) }
                        .font(.system(size: 10, weight: .bold))
                        .buttonStyle(.plain)
                        .opacity(0.4)
                    
                    HStack(spacing: 4) {
                        Toggle("", isOn: $vm.launchAtLogin)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .controlSize(.small)
                        
                        Text("LAUNCH AT LOGIN")
                            .font(.system(size: 8, weight: .bold))
                            .opacity(vm.launchAtLogin ? 0.8 : 0.3)
                    }
                    
                    Spacer()
                    
                    if vm.changeAllScreens {
                        Text("MODE: ALL SCREENS")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.blue)
                            .opacity(0.8)
                    }
                    else {
                        Text("MODE: CURRENT SCREENS")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.blue)
                            .opacity(0.8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            Color.black
                .opacity(isTransitioning ? 0.4 : 0)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: isTransitioning)
        }
    }

    func triggerChange(url: URL) {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

        DispatchQueue.main.async {
            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.6)) {
                self.activeURL = url
                self.isTransitioning = true
            }
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) {
            vm.updateWallpaper(to: url)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.easeOut(duration: 0.3)) {
                    self.activeURL = nil
                    self.isTransitioning = false
                }
            }
        }
    }
}
