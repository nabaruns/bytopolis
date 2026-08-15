import SwiftUI

@main
struct DiskSizeApp: App {
    var body: some Scene {
        WindowGroup("DiskSize") {
            ContentView()
                .frame(minWidth: 860, minHeight: 440)
        }
        .windowResizability(.contentMinSize)
    }
}
