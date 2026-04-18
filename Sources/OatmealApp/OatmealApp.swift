import SwiftUI

public struct OatmealPackageApp: App {
    @State private var model = AppViewModel()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            OatmealRootView()
                .environment(model)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 800)

        Settings {
            OatmealSettingsView()
                .environment(model)
                .frame(width: 520, height: 560)
        }
    }
}
