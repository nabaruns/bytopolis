import SwiftUI

@main
struct DiskSizeApp: App {
    var body: some Scene {
        WindowGroup("DiskSize") {
            ContentView()
                .frame(minWidth: 640, minHeight: 420)
        }
        .windowResizability(.contentMinSize)
    }
}
