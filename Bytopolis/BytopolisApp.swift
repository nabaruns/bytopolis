import SwiftUI

@main
struct BytopolisApp: App {
    var body: some Scene {
        WindowGroup("Bytopolis") {
            ContentView()
                .frame(minWidth: 860, minHeight: 440)
        }
        .windowResizability(.contentMinSize)
    }
}
