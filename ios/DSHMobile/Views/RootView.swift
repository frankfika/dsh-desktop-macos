import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.connection == nil {
                PairingView()
            } else {
                DashboardView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.connection == nil)
        .alert("DSH Mobile", isPresented: Binding(
            get: { model.message != nil },
            set: { if !$0 { model.message = nil } }
        )) {
            Button("好") { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
    }
}

