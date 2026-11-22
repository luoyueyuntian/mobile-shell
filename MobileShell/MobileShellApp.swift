import SwiftUI

@main
struct MobileShellApp: App {
    @State private var store = MobileShellStore.live()

    var body: some Scene {
        WindowGroup {
            ShellRootView(store: store)
        }
    }
}
