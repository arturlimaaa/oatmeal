import AppKit
import SwiftUI

public struct OatmealPackageApp: App {
    @State private var model = AppViewModel()
    @NSApplicationDelegateAdaptor(OatmealApplicationDelegate.self) private var applicationDelegate

    public init() {}

    public var body: some Scene {
        let _ = applicationDelegate.bind(model: model)

        Window("Oatmeal", id: OatmealSceneID.main) {
            OatmealRootView()
                .environment(model)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 800)

        Window("Session Controller", id: OatmealSceneID.sessionController) {
            SessionControllerWindowRootView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowLevel(.floating)
        .defaultSize(width: 376, height: 248)

        Window("Start Oatmeal", id: OatmealSceneID.meetingDetectionPrompt) {
            MeetingDetectionPromptWindowRootView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowLevel(.floating)
        .defaultSize(width: 340, height: 184)

        MenuBarExtra {
            OatmealMenuBarContent()
                .environment(model)
        } label: {
            Label("Oatmeal", systemImage: model.menuBarSymbolName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            OatmealSettingsView()
                .environment(model)
                .frame(width: 520, height: 560)
        }
    }
}
