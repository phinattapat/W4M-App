import AppKit
import AVFoundation
import AVKit

/// Manages live (video) wallpaper windows on macOS desktop spaces.
/// Places a borderless, non-interactive AVPlayerLayer window behind all icons
/// on every requested screen.
final class LiveWallManager {

    // MARK: - Singleton
    static let shared = LiveWallManager()
    private init() {}

    // MARK: - Private state
    /// One entry per screen: the transparent window + its player.
    private var wallpaperWindows: [NSScreen: (window: NSWindow, player: AVPlayer)] = [:]

    // MARK: - Public API

    /// Start (or replace) a looping video wallpaper.
    /// - Parameters:
    ///   - url: A local file URL pointing to an .mp4 / .mov / .m4v file.
    ///   - allScreens: `true` → put the video on every connected screen.
    ///                 `false` → only the main screen.
    func playVideo(url: URL, allScreens: Bool) {
        stopAll()   // Tear down any previous session first

        let screens = allScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }

        for screen in screens {
            let player = makeLoopingPlayer(url: url)
            let window = makeWallpaperWindow(for: screen, player: player)
            wallpaperWindows[screen] = (window, player)
            player.play()
        }
    }

    /// Tear down all live wallpaper windows and stop all players.
    func stopAll() {
        for (_, pair) in wallpaperWindows {
            pair.player.pause()
            pair.window.orderOut(nil)
            pair.window.close()
        }
        wallpaperWindows.removeAll()
    }

    // MARK: - Private helpers

    /// Creates an `AVPlayer` that loops the given URL indefinitely and is muted.
    private func makeLoopingPlayer(url: URL) -> AVPlayer {
        let item   = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none   // We handle looping via notification

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

    /// Creates a borderless window that sits below desktop icons but above the
    /// default macOS desktop layer, sized to fill the given screen.
    private func makeWallpaperWindow(for screen: NSScreen, player: AVPlayer) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask:   .borderless,
            backing:     .buffered,
            defer:       false,
            screen:      screen
        )

        // Level: just below the desktop icons (kCGDesktopIconWindowLevel - 1)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents  = true   // Clicks pass through to the desktop
        window.collectionBehavior  = [
            .canJoinAllSpaces,          // Visible on every Space
            .stationary,                // Doesn't move with Mission Control
            .ignoresCycle               // Not reachable via Cmd-Tab
        ]
        window.isReleasedWhenClosed = false
        window.hasShadow            = false

        // Embed AVPlayerLayer inside the window's content view
        let playerLayer        = AVPlayerLayer(player: player)
        playerLayer.frame      = CGRect(origin: .zero, size: screen.frame.size)
        playerLayer.videoGravity = .resizeAspectFill

        let hostView           = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        hostView.wantsLayer    = true
        hostView.layer?.addSublayer(playerLayer)

        window.contentView = hostView
        window.setFrame(screen.frame, display: false)
        window.orderFront(nil)

        return window
    }
}
