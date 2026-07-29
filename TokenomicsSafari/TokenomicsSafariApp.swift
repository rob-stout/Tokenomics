import SwiftUI

@main
struct TokenomicsSafariApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
        .defaultSize(width: 440, height: 380)
    }
}
