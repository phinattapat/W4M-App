import AppKit
import AVFoundation
import AVKit

final class LiveWallManager {
    static let shared = LiveWallManager()
    private init() {}

    private var wallpaperWindows: [NSScreen: (window: NSWindow, player: AVPlayer)] = [:]

    func playVideo(url: URL, allScreens: Bool) {
        stopAll()
        let screens = allScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }

        for screen in screens {
            let player = makeLoopingPlayer(url: url)
            let window = makeWallpaperWindow(for: screen, player: player)
            wallpaperWindows[screen] = (window, player)
            player.play()
        }
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
        window.setFrame(screen.frame, display: false)
        window.orderFront(nil)

        return window
    }
}
