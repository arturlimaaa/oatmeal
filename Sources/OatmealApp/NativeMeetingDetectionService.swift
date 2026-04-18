import AppKit
import Foundation

struct NativeMeetingRunningApplication: Equatable, Sendable {
    let bundleIdentifier: String?
    let localizedName: String?
}

@MainActor
protocol NativeMeetingApplicationWorkspace: AnyObject {
    var frontmostApplication: NativeMeetingRunningApplication? { get }
    func observeActivation(_ handler: @escaping @MainActor (NativeMeetingRunningApplication?) -> Void) -> AnyObject
    func removeObserver(_ token: AnyObject)
}

@MainActor
final class LiveNativeMeetingApplicationWorkspace: NativeMeetingApplicationWorkspace {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    var frontmostApplication: NativeMeetingRunningApplication? {
        guard let application = workspace.frontmostApplication else {
            return nil
        }

        return Self.map(application)
    }

    func observeActivation(_ handler: @escaping @MainActor (NativeMeetingRunningApplication?) -> Void) -> AnyObject {
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: workspace,
            queue: nil
        ) { notification in
            let application = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
                .map { Self.map($0) }
            Task { @MainActor in
                handler(application)
            }
        }
    }

    func removeObserver(_ token: AnyObject) {
        workspace.notificationCenter.removeObserver(token)
    }

    private nonisolated static func map(_ application: NSRunningApplication) -> NativeMeetingRunningApplication {
        NativeMeetingRunningApplication(
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName
        )
    }
}

struct SupportedNativeMeetingApp: Equatable, Sendable {
    let bundleIdentifier: String
    let displayName: String

    static let defaults: [SupportedNativeMeetingApp] = [
        SupportedNativeMeetingApp(bundleIdentifier: "us.zoom.xos", displayName: "Zoom"),
        SupportedNativeMeetingApp(bundleIdentifier: "com.microsoft.teams2", displayName: "Microsoft Teams"),
        SupportedNativeMeetingApp(bundleIdentifier: "com.microsoft.teams", displayName: "Microsoft Teams"),
        SupportedNativeMeetingApp(bundleIdentifier: "com.tinyspeck.slackmacgap", displayName: "Slack")
    ]
}

@MainActor
protocol NativeMeetingDetectionServicing {
    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void)
    func stop()
}

@MainActor
final class LiveNativeMeetingDetectionService: NativeMeetingDetectionServicing {
    private let workspace: NativeMeetingApplicationWorkspace
    private let supportedApps: [SupportedNativeMeetingApp]
    private let nowProvider: () -> Date

    private var activationObserver: AnyObject?
    private var onDetection: (@MainActor (PendingMeetingDetection) -> Void)?
    private var lastForegroundSupportedBundleIdentifier: String?
    private var activeSupportedApp: SupportedNativeMeetingApp?

    init(
        workspace: NativeMeetingApplicationWorkspace = LiveNativeMeetingApplicationWorkspace(),
        supportedApps: [SupportedNativeMeetingApp] = SupportedNativeMeetingApp.defaults,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.workspace = workspace
        self.supportedApps = supportedApps
        self.nowProvider = nowProvider
    }

    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {
        self.onDetection = onDetection

        guard activationObserver == nil else {
            handleActivation(of: workspace.frontmostApplication)
            return
        }

        activationObserver = workspace.observeActivation { [weak self] application in
            self?.handleActivation(of: application)
        }

        handleActivation(of: workspace.frontmostApplication)
    }

    func stop() {
        if let activationObserver {
            workspace.removeObserver(activationObserver)
        }
        activationObserver = nil
        onDetection = nil
        lastForegroundSupportedBundleIdentifier = nil
        activeSupportedApp = nil
    }

    private func handleActivation(of application: NativeMeetingRunningApplication?) {
        guard let application else {
            if let activeSupportedApp {
                emitEndSuggestion(for: activeSupportedApp)
            }
            lastForegroundSupportedBundleIdentifier = nil
            activeSupportedApp = nil
            return
        }

        guard let supportedApp = supportedApp(for: application) else {
            if let activeSupportedApp {
                emitEndSuggestion(for: activeSupportedApp)
            }
            lastForegroundSupportedBundleIdentifier = nil
            activeSupportedApp = nil
            return
        }

        if let activeSupportedApp,
           activeSupportedApp.bundleIdentifier != supportedApp.bundleIdentifier {
            emitEndSuggestion(for: activeSupportedApp)
        }

        guard supportedApp.bundleIdentifier != lastForegroundSupportedBundleIdentifier else {
            activeSupportedApp = supportedApp
            return
        }

        lastForegroundSupportedBundleIdentifier = supportedApp.bundleIdentifier
        activeSupportedApp = supportedApp
        onDetection?(
            PendingMeetingDetection(
                title: "Untitled Meeting",
                source: .nativeApp(supportedApp.displayName),
                phase: .start,
                detectedAt: nowProvider(),
                presentation: .prompt
            )
        )
    }

    private func emitEndSuggestion(for app: SupportedNativeMeetingApp) {
        onDetection?(
            PendingMeetingDetection(
                title: "Untitled Meeting",
                source: .nativeApp(app.displayName),
                phase: .endSuggestion,
                detectedAt: nowProvider(),
                presentation: .prompt,
                confidence: .low
            )
        )
    }

    private func supportedApp(for application: NativeMeetingRunningApplication) -> SupportedNativeMeetingApp? {
        guard let bundleIdentifier = application.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty else {
            return nil
        }

        if let exact = supportedApps.first(where: { $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }) {
            return exact
        }

        if let fallbackName = application.localizedName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fallbackName.isEmpty {
            return supportedApps.first(where: { $0.displayName.caseInsensitiveCompare(fallbackName) == .orderedSame })
        }

        return nil
    }
}
