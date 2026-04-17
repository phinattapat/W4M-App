import SwiftUI
import Combine
import AVKit

struct MainMenuView: View {
    @ObservedObject var vm: WallpaperVM
    @State private var activeURL: URL? = nil
    @State private var isTransitioning = false
    @State private var showSettings = false
    
    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // --- HEADER ---
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("W4M").font(.system(size: 16, weight: .black, design: .monospaced))
                            Text(vm.folderPathString.isEmpty ? "NO SOURCE" : "\(vm.currentWallpapers.count) FILES")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 80, alignment: .leading)
                        
                        Spacer()
                        
                        Picker("", selection: $vm.activeTab) {
                            Text("Photos").tag("Photos")
                            Text("Videos").tag("Videos")
                        }
                        .pickerStyle(.segmented)
                        .tint(.blue)
                        .frame(width: 140)
                        .labelsHidden()
                        
                        Spacer()
                        
                        // RIGHT SECTION: Cleaned up controls
                        HStack(spacing: 12) {
                            Button(action: vm.selectFolder) {
                                Image(systemName: "folder.fill.badge.plus").font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showSettings.toggle()
                                }
                            }) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(showSettings ? .blue : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(width: 80, alignment: .trailing)
                    }
                    .padding()
                }
                .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))

                Divider()

                // --- GRID SECTION ---
                ZStack {
                    if vm.folderPathString.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "display.2").font(.system(size: 40)).foregroundColor(.gray.opacity(0.2))
                            Button("SELECT SOURCE FOLDER", action: vm.selectFolder).buttonStyle(.bordered).controlSize(.large)
                        }
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVGrid(columns: columns, spacing: 15) {
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
                                            Image(systemName: "heart.fill")
                                                .font(.system(size: 10, weight: .black))
                                                .foregroundColor(isPinned ? Color(nsColor: NSColor(calibratedRed: 0.82, green: 0.16, blue: 0.35, alpha: 1.0)) : .white.opacity(0.4))
                                                .padding(6)
                                                .background(Circle().fill(.ultraThinMaterial))
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
                    }
                    
                    if showSettings {
                        SettingsOverlay(vm: vm, isPresented: $showSettings)
                            .zIndex(10)
                            .transition(.opacity)
                    }
                }
                .frame(width: 440, height: 520)

                Divider()
                
                // --- BOTTOM BAR ---
                HStack(alignment: .center, spacing: 15) {
                    Button("QUIT") { NSApplication.shared.terminate(nil) }.font(.system(size: 10, weight: .bold)).buttonStyle(.plain).opacity(0.4)
                    
                    HStack(spacing: 4) {
                        Toggle("", isOn: $vm.launchAtLogin).toggleStyle(.checkbox).labelsHidden().controlSize(.small)
                        Text("LAUNCH AT LOGIN").font(.system(size: 8, weight: .bold)).opacity(vm.launchAtLogin ? 0.8 : 0.3)
                    }
                    
                    Spacer()
                    
                    Text("MODE: \(vm.changeAllScreens ? "ALL SCREENS" : "CURRENT SCREEN")")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            Color.black.opacity(isTransitioning ? 0.4 : 0).ignoresSafeArea()
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

// --- ITEM COMPONENT ---
private struct WallpaperItem: View {
    let url: URL
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            StaticThumbnailView(url: url)
                .frame(width: 130, height: 85)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isActive ? Color.blue : Color.white.opacity(0.12), lineWidth: isActive ? 3 : 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .scaleEffect(isActive ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

// --- THUMBNAIL GENERATOR ---
struct StaticThumbnailView: View {
    let url: URL
    @State private var thumbnail: NSImage? = nil

    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black.opacity(0.1)
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: 130, height: 85)
        .clipped()
        .onAppear { generateThumbnail() }
    }

    private func generateThumbnail() {
        let isVideo = ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
        if !isVideo {
            DispatchQueue.global(qos: .userInitiated).async {
                if let image = NSImage(contentsOf: url) {
                    DispatchQueue.main.async { self.thumbnail = image }
                }
            }
            return
        }
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 1, preferredTimescale: 60)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let imageRef = try generator.copyCGImage(at: time, actualTime: nil)
                let nsImage = NSImage(cgImage: imageRef, size: NSSize(width: 130, height: 85))
                DispatchQueue.main.async { self.thumbnail = nsImage }
            } catch { print("Thumbnail failed: \(error)") }
        }
    }
}

// --- SETTINGS OVERLAY ---
struct SettingsOverlay: View {
    @ObservedObject var vm: WallpaperVM
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeIn(duration: 0.2)) { isPresented = false }
                }

            VStack(alignment: .leading, spacing: 20) {
                Text("SETTINGS").font(.system(size: 12, weight: .black))
                
                VStack(alignment: .leading, spacing: 16) {
                    // Display Mode (Moved from header)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DISPLAY MODE").font(.system(size: 10, weight: .bold)).opacity(0.6)
                        Picker("", selection: $vm.changeAllScreens) {
                            Text("Single Screen").tag(false)
                            Text("All Screens").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: vm.changeAllScreens) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "changeAllScreens")
                            if newValue && !vm.lastUsedWallpaperPath.isEmpty {
                                vm.updateWallpaper(to: URL(fileURLWithPath: vm.lastUsedWallpaperPath))
                            }
                        }
                    }

                    Divider()

                    Toggle("AUTO-CHANGE WALLPAPER", isOn: $vm.autoChangeEnabled)
                        .toggleStyle(.switch)
                        .font(.system(size: 11, weight: .bold))
                    
                    if vm.autoChangeEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CHANGE EVERY:").font(.system(size: 10, weight: .bold)).opacity(0.6)
                            HStack(spacing: 10) {
                                timePicker(value: $vm.autoChangeHH, range: 0...23, label: "hr")
                                timePicker(value: $vm.autoChangeMM, range: 0...59, label: "min")
                                timePicker(value: $vm.autoChangeSS, range: 0...59, label: "sec")
                            }
                            .onChange(of: vm.autoChangeHH) { _, _ in vm.setupAutoChangeTimer() }
                            .onChange(of: vm.autoChangeMM) { _, _ in vm.setupAutoChangeTimer() }
                            .onChange(of: vm.autoChangeSS) { _, _ in vm.setupAutoChangeTimer() }
                        }
                    }
                }
                
                Spacer()
                
                Button("APPLY & CLOSE") {
                    withAnimation(.easeIn(duration: 0.2)) { isPresented = false }
                }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            }
            .padding(25)
            .background(VisualEffectView(material: .menu, blendingMode: .withinWindow))
            .cornerRadius(15).padding(20).shadow(radius: 20)
        }
    }
    
    @ViewBuilder
    func timePicker(value: Binding<Int>, range: ClosedRange<Int>, label: String) -> some View {
        HStack(spacing: 4) {
            Picker("", selection: value) {
                ForEach(range, id: \.self) { i in
                    // Using a String format to ensure at least one or two digits show
                    Text("\(i)").tag(i)
                }
            }
            // Force the picker style to 'menu' so it shows the number instead of dots
            .pickerStyle(.menu)
            // Set a fixed or minimum width so it doesn't collapse
            .frame(width: 55)
            .labelsHidden()
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .opacity(0.7)
        }
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
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
