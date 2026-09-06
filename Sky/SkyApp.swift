import SwiftUI

@main
struct SkyApp: App {
    var body: some Scene {
        WindowGroup {
            GalleryView()
                .preferredColorScheme(.light)
        }
    }
}
