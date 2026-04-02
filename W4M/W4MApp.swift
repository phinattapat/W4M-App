import SwiftUI
import Combine
import ServiceManagement

@main
struct W4MApp: App {
    // This creates your ViewModel once and keeps it alive
    @StateObject private var vm = WallpaperVM()

    var body: some Scene {
        MenuBarExtra("W4M", systemImage: "photo.on.rectangle.angled") {
            MainMenuView(vm: vm)
        }
        .menuBarExtraStyle(.window)
    }
}
