import SwiftUI

@main
struct PremiumIPTVApp: App {
    var body: some Scene {
        WindowGroup {
            AppNavigator()
                .preferredColorScheme(.dark)
        }
    }
}
