import AppKit
import AVFoundation
import AVKit

final class LiveWallManager {
    static let shared = LiveWallManager()
    private init() {}

    // We use the deviceDescription to uniquely identify screens even if NSScreen objects change
    private var wallpaperWindows: [String: (window: NSWindow, player: AVPlayer)] = [:]

    func playVideo(url: URL, allScreens: Bool, targetScreen: NSScreen? = nil) {
        if allScreens {
            stopAll()
            for screen in NSScreen.screens {
                createOrUpdateWindow(url: url, for: screen)
            }
        } else {
            // If a specific screen is provided, use it; otherwise, default to main
            let screen = targetScreen ?? NSScreen.main ?? NSScreen.screens.first!
            createOrUpdateWindow(url: url, for: screen)
        }
    }
    
    private func createOrUpdateWindow(url: URL, for screen: NSScreen) {
        let screenID = "\(screen.deviceDescription)"
        
        // Stop existing player for THIS screen only
        if let existing = wallpaperWindows[screenID] {
            existing.player.pause()
            existing.window.close()
        }

        let player = makeLoopingPlayer(url: url)
        let window = makeWallpaperWindow(for: screen, player: player)
        wallpaperWindows[screenID] = (window, player)
        player.play()
    }

    func stopAll() {
        for (_, pair) in wallpaperWindows {
            pair.player.pause()
            pair.window.orderOut(nil)
            pair.window.close()
        }
        wallpaperWindows.removeAll()
    }

    private func makeLoopingPlayer(url: URL) -> AVPlayer {
        let item   = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        return player
    }

    private func makeWallpaperWindow(for screen: NSScreen, player: AVPlayer) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask:   .borderless,
            backing:     .buffered,
            defer:       false,
            screen:      screen
        )

        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents  = true
        window.collectionBehavior  = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hasShadow = false

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = CGRect(origin: .zero, size: screen.frame.size)
        playerLayer.videoGravity = .resizeAspectFill

        let hostView = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        hostView.wantsLayer = true
        hostView.layer?.addSublayer(playerLayer)

        window.contentView = hostView
        // Important: Use frame of the specific screen
        window.setFrame(screen.frame, display: true)
        window.orderFront(nil)

        return window
    }
}
