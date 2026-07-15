import SwiftUI

@main
struct Sub2APIApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .task {
                    await session.hydrate()
                }
        }
    }
}
