import SwiftUI

struct ContentView: View {
    @State private var viewModel = RootViewModel()

    var body: some View {
        NavigationStack {
            RootStatusView(
                state: viewModel.state,
                requestAccess: viewModel.requestAccess
            )
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.cancelWork()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaAssetsDidChange)) { _ in
            viewModel.refreshAfterLibraryChange()
        }
    }
}

#Preview {
    ContentView()
}
