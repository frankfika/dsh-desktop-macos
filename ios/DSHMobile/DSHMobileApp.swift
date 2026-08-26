import SwiftUI

@main
struct DSHMobileApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .onOpenURL { model.acceptPairingURL($0) }
        }
    }
}

