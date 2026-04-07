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
                // --- HEADER ---
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        // LEFT SECTION: Branding
                        VStack(alignment: .leading, spacing: 2) {
                            Text("W4M").font(.system(size: 16, weight: .black, design: .monospaced))
                            Text(vm.folderPathString.isEmpty ? "NO SOURCE" : "\(vm.currentWallpapers.count) FILES")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 80, alignment: .leading)
                        
                        Spacer()
                        
                        // CENTER SECTION: Tabs (Blue Selection)
                        Picker("", selection: $vm.activeTab) {
                            Text("Photos").tag("Photos")
                            Text("Videos").tag("Videos")
                        }
                        .pickerStyle(.segmented)
                        .tint(.blue) // Makes the selection blue
                        .frame(width: 140)
                        .labelsHidden()
                        
                        Spacer()
                        
                        // RIGHT SECTION: Controls
                        HStack(spacing: 8) {
                            if vm.activeTab == "Photos" {
                                Picker("", selection: $vm.changeAllScreens) {
                                    Text("Single").tag(false)
                                    Text("All").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .tint(.blue) // Makes the selection blue
                                .frame(width: 100)
                                .labelsHidden()
                                .transition(.opacity)
                                .onChange(of: vm.changeAllScreens) { oldValue, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "changeAllScreens")
                                    if newValue && !vm.lastUsedWallpaperPath.isEmpty {
                                        let url = URL(fileURLWithPath: vm.lastUsedWallpaperPath)
                                        vm.updateWallpaper(to: url)
                                    }
                                }
                            } else {
                                // Keeps layout stable when "Single/All" is hidden
                                Spacer().frame(width: 100)
                            }
                            
                            Button(action: vm.selectFolder) {
                                Image(systemName: "folder.fill.badge.plus")
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(width: 130, alignment: .trailing)
                    }
                    .padding()
                }
                .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))

                Divider()

                // --- GRID SECTION ---
                if vm.folderPathString.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "display.2")
                            .font(.system(size: 40))
                            .foregroundColor(.gray.opacity(0.2))
                        
                        Button("SELECT SOURCE FOLDER", action: vm.selectFolder)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
                    .frame(width: 440, height: 520)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 15) {
                            ForEach(vm.currentWallpapers, id: \.self) { url in
                                ZStack(alignment: .topTrailing) {
                                    WallpaperItem(url: url, isActive: activeURL == url) {
                                        triggerChange(url: url)
                                    }
                                    
                                    Button(action: {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                            vm.toggleFavorite(url: url)
                                        }
                                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                                    }) {
                                        let isPinned = vm.favoritePaths.contains(url.path)
                                        Image(systemName: isPinned ? "heart.fill" : "heart")
                                            .font(.system(size: 10, weight: .black))
                                            .foregroundColor(isPinned ? Color(nsColor: NSColor(calibratedRed: 0.82, green: 0.16, blue: 0.35, alpha: 1.0)) : .white.opacity(0.8))
                                            .padding(6)
                                            .background(
                                                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                                                    .cornerRadius(8)
                                            )
                                            .shadow(radius: 2)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                }
                            }
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                    }
                    .frame(width: 440, height: 520)
                }

                Divider()
                
                // --- BOTTOM BAR ---
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
                    
                    Text("MODE: \(vm.changeAllScreens ? "ALL SCREENS" : "CURRENT SCREEN")")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.blue)
                        .opacity(0.8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            // Darkening overlay
            Color.black
                .opacity(isTransitioning ? 0.4 : 0)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: isTransitioning)
        }
        // Force Single Mode for Videos
        .onChange(of: vm.activeTab) { oldValue, newValue in
            if newValue == "Videos" {
                vm.changeAllScreens = false
            }
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

// --- HELPER ---
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
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
