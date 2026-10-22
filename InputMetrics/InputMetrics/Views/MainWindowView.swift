import SwiftUI

struct MainWindowView: View {
    var body: some View {
        ScrollView {
            KeyboardStatsView()
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

#Preview {
    MainWindowView()
}
