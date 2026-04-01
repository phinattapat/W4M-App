import SwiftUI
import Combine
@main
struct W4MApp: App {
    @StateObject private var vm = WallpaperVM()

    var body: some Scene {
        MenuBarExtra("W4M", systemImage: "photo.on.rectangle.angled") {
            MainMenuView(vm: vm)
        }
        .menuBarExtraStyle(.window)
    }
}
