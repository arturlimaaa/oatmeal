import AppKit
import SwiftUI

public struct OatmealPackageApp: App {
    @State private var model = AppViewModel()
    @NSApplicationDelegateAdaptor(OatmealApplicationDelegate.self) private var applicationDelegate
    @AppStorage(OnboardingCompletion.defaultsKey) private var isOnboardingComplete = false

    public init() {}

    public var body: some Scene {
        let _ = applicationDelegate.bind(model: model)

        Window("Oatmeal", id: OatmealSceneID.main) {
            OatmealRootView()
                .environment(model)
                .frame(minWidth: 1120, minHeight: 720)
                .preferredColorScheme(.light)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 800)

        Window("Session Controller", id: OatmealSceneID.sessionController) {
            SessionControllerWindowRootView()
                .environment(model)
                .preferredColorScheme(.light)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowLevel(.floating)
        .defaultSize(width: 376, height: 248)
        .defaultLaunchBehavior(.suppressed)

        Window("Start Oatmeal", id: OatmealSceneID.meetingDetectionPrompt) {
            MeetingDetectionPromptWindowRootView()
                .environment(model)
                .preferredColorScheme(.light)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowLevel(.floating)
        .defaultSize(width: 340, height: 184)
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra(isInserted: $isOnboardingComplete) {
            OatmealMenuBarContent()
                .environment(model)
                .preferredColorScheme(.light)
        } label: {
            Image("Oatmeal_menubar", bundle: .module)
        }
        .menuBarExtraStyle(.window)

        Settings {
            OatmealSettingsView()
                .environment(model)
                .frame(width: 520, height: 560)
                .preferredColorScheme(.light)
        }
    }
}
