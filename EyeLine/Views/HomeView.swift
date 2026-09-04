import SwiftUI

/// App entry point. For the MVP, "home" is the script library: pick or
/// create a script, then swipe-to-record straight from a row.
struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScriptLibraryView()
        }
    }
}
