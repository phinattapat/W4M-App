import SwiftUI
import Combine
import ServiceManagement

@main
struct W4MApp: App {
    @StateObject private var vm = WallpaperVM()

    var body: some Scene {
        MenuBarExtra("W4M", systemImage: "photo.on.rectangle.angled") {
            MainMenuView(vm: vm)
                .background(Color.clear) // Keep this
        }
        .menuBarExtraStyle(.window)
    }
}
