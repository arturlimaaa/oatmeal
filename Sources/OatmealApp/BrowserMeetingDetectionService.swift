import AppKit
import ApplicationServices
import CoreAudio
import Foundation

enum BrowserScriptingFamily: Sendable {
    case safari
    case chromium
}

struct SupportedMeetingBrowser: Equatable, Sendable {
    let bundleIdentifier: String
    let displayName: String
    let scriptingApplicationName: String?
    let scriptingFamily: BrowserScriptingFamily?

    static let defaults: [SupportedMeetingBrowser] = [
        SupportedMeetingBrowser(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            scriptingApplicationName: "Safari",
            scriptingFamily: .safari
        ),
        SupportedMeetingBrowser(
            bundleIdentifier: "com.google.Chrome",
            displayName: "Google Chrome",
            scriptingApplicationName: "Google Chrome",
            scriptingFamily: .chromium
        ),
        SupportedMeetingBrowser(
            bundleIdentifier: "com.google.Chrome.canary",
            displayName: "Google Chrome Canary",
            scriptingApplicationName: "Google Chrome Canary",
            scriptingFamily: .chromium
        ),
        SupportedMeetingBrowser(
            bundleIdentifier: "company.thebrowser.Browser",
            displayName: "Arc",
            scriptingApplicationName: "Arc",
            scriptingFamily: .chromium
        ),
        SupportedMeetingBrowser(
            bundleIdentifier: "org.mozilla.firefox",
            displayName: "Firefox",
            scriptingApplicationName: nil,
            scriptingFamily: nil
        ),
        SupportedMeetingBrowser(
            bundleIdentifier: "com.microsoft.edgemac",
            displayName: "Microsoft Edge",
            scriptingApplicationName: "Microsoft Edge",
            scriptingFamily: .chromium
        ),
        SupportedMeetingBrowser(
            bundleIdentifier: "com.brave.Browser",
            displayName: "Brave",
            scriptingApplicationName: "Brave Browser",
            scriptingFamily: .chromium
        ),
        SupportedMeetingBrowser(
            bundleIdentifier: "com.operasoftware.Opera",
            displayName: "Opera",
            scriptingApplicationName: "Opera",
            scriptingFamily: .chromium
        )
    ]
}

struct BrowserMeetingActivitySnapshot: Equatable, Sendable {
    let isMicrophoneActive: Bool
    let isSystemAudioActive: Bool
    let capturedAt: Date

    var presentation: PendingMeetingDetection.Presentation? {
        if isMicrophoneActive {
            return .prompt
        }

        if isSystemAudioActive {
            return .passiveSuggestion
        }

        return nil
    }
}

struct BrowserMeetingContextSnapshot: Equatable, Sendable {
    let capturedAt: Date
    let activePageURL: String?
    let activePageTitle: String?
    let focusedWindowTitle: String?
    let meetingSurfaceName: String?

    var isLikelyMeetingPage: Bool {
        meetingSurfaceName != nil
    }

    var preferredMeetingTitle: String {
        if let activePageTitle,
           let cleanedTitle = Self.cleanedMeetingTitle(from: activePageTitle),
           !cleanedTitle.isEmpty {
            return cleanedTitle
        }

        if let focusedWindowTitle,
           let cleanedTitle = Self.cleanedMeetingTitle(from: focusedWindowTitle),
           !cleanedTitle.isEmpty {
            return cleanedTitle
        }

        return "Untitled Meeting"
    }

    var signature: String {
        [
            activePageURL?.lowercased() ?? "no-url",
            activePageTitle?.lowercased() ?? "no-title",
            focusedWindowTitle?.lowercased() ?? "no-window",
            meetingSurfaceName?.lowercased() ?? "no-surface"
        ].joined(separator: "|")
    }

    private static func cleanedMeetingTitle(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let suffixes = [
            " - Google Meet",
            " | Google Meet",
            " - Microsoft Teams",
            " | Microsoft Teams",
            " - Zoom",
            " | Zoom",
            " - WhatsApp",
            " | WhatsApp",
            " - Safari",
            " - Google Chrome",
            " - Microsoft Edge",
            " - Arc"
        ]

        for suffix in suffixes where trimmed.hasSuffix(suffix) {
            let cleaned = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }

        return trimmed == "Google Meet" ? nil : trimmed
    }
}

enum BrowserAutomationAvailability: String, Equatable, Sendable {
    case unknown
    case available
    case denied
}

struct BrowserDetectionCapabilityState: Equatable, Sendable {
    let accessibilityTrusted: Bool
    let automationAvailability: BrowserAutomationAvailability

    var detailText: String {
        switch (accessibilityTrusted, automationAvailability) {
        case (true, .available):
            "Browser meeting detection has full context access for the best Start Oatmeal prompts."
        case (true, .denied):
            "Accessibility is enabled, but browser automation access was denied. Oatmeal can still fall back to lighter heuristics."
        case (true, .unknown):
            "Accessibility is enabled. Browser automation will improve Google Meet and web-call detection the first time Oatmeal can inspect the active tab."
        case (false, .available):
            "Browser automation is available, but Accessibility is off. Oatmeal can inspect active tabs, but window-title fallbacks are limited."
        case (false, .denied):
            "Browser meeting detection is limited because Accessibility and browser automation are not fully available."
        case (false, .unknown):
            "For Jamie-like browser detection, enable Accessibility and allow Oatmeal to inspect active browser tabs when macOS asks."
        }
    }
}

@MainActor
protocol BrowserMeetingActivityMonitoring: AnyObject {
    func start(onUpdate: @escaping @MainActor (BrowserMeetingActivitySnapshot) -> Void)
    func stop()
}

@MainActor
final class LiveBrowserMeetingActivityMonitor: BrowserMeetingActivityMonitoring, @unchecked Sendable {
    private let nowProvider: () -> Date
    private let pollingIntervalNanoseconds: UInt64

    private var pollingTask: Task<Void, Never>?
    private var lastSnapshot: BrowserMeetingActivitySnapshot?

    init(
        nowProvider: @escaping () -> Date = Date.init,
        pollingInterval: TimeInterval = 1.5
    ) {
        self.nowProvider = nowProvider
        self.pollingIntervalNanoseconds = UInt64(max(pollingInterval, 0.25) * 1_000_000_000)
    }

    func start(onUpdate: @escaping @MainActor (BrowserMeetingActivitySnapshot) -> Void) {
        let initialSnapshot = currentSnapshot()
        lastSnapshot = initialSnapshot
        Task { @MainActor in
            onUpdate(initialSnapshot)
        }

        guard pollingTask == nil else {
            return
        }

        pollingTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
                guard !Task.isCancelled else { return }

                let snapshot = currentSnapshot()
                guard snapshot != lastSnapshot else {
                    continue
                }

                lastSnapshot = snapshot
                await MainActor.run {
                    onUpdate(snapshot)
                }
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        lastSnapshot = nil
    }

    private func currentSnapshot() -> BrowserMeetingActivitySnapshot {
        BrowserMeetingActivitySnapshot(
            isMicrophoneActive: defaultDeviceIsRunning(selector: kAudioHardwarePropertyDefaultInputDevice),
            isSystemAudioActive: defaultDeviceIsRunning(selector: kAudioHardwarePropertyDefaultOutputDevice),
            capturedAt: nowProvider()
        )
    }

    private func defaultDeviceIsRunning(selector: AudioObjectPropertySelector) -> Bool {
        guard let deviceID = defaultDeviceID(selector: selector) else {
            return false
        }

        return deviceIsRunningSomewhere(deviceID)
    }

    private func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
    }

    private func deviceIsRunningSomewhere(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &isRunning
        )
        guard status == noErr else {
            return false
        }
        return isRunning != 0
    }
}

@MainActor
protocol BrowserMeetingContextInspecting: AnyObject {
    var capabilityState: BrowserDetectionCapabilityState { get }
    func inspect(
        application: NativeMeetingRunningApplication,
        browser: SupportedMeetingBrowser,
        capturedAt: Date
    ) -> BrowserMeetingContextSnapshot
}

@MainActor
final class LiveBrowserMeetingContextInspector: BrowserMeetingContextInspecting {
    private var automationAvailability: BrowserAutomationAvailability = .unknown

    var capabilityState: BrowserDetectionCapabilityState {
        BrowserDetectionCapabilityState(
            accessibilityTrusted: AXIsProcessTrusted(),
            automationAvailability: automationAvailability
        )
    }

    func inspect(
        application: NativeMeetingRunningApplication,
        browser: SupportedMeetingBrowser,
        capturedAt: Date
    ) -> BrowserMeetingContextSnapshot {
        let focusedWindowTitle = focusedWindowTitle(for: application)
        let automationResult = activeTabContext(for: browser)
        let activePageURL = automationResult?.url
        let activePageTitle = automationResult?.title ?? focusedWindowTitle
        let meetingSurfaceName = Self.matchingMeetingSurfaceName(
            url: activePageURL,
            title: activePageTitle ?? focusedWindowTitle
        )

        return BrowserMeetingContextSnapshot(
            capturedAt: capturedAt,
            activePageURL: activePageURL,
            activePageTitle: activePageTitle,
            focusedWindowTitle: focusedWindowTitle,
            meetingSurfaceName: meetingSurfaceName
        )
    }

    private func focusedWindowTitle(for application: NativeMeetingRunningApplication) -> String? {
        guard AXIsProcessTrusted(),
              let processIdentifier = application.processIdentifier else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        var focusedWindowValue: CFTypeRef?
        let focusedWindowError = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )
        guard focusedWindowError == .success,
              let focusedWindow = focusedWindowValue else {
            return nil
        }

        let windowElement = unsafeDowncast(focusedWindow, to: AXUIElement.self)
        var titleValue: CFTypeRef?
        let titleError = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleValue)
        guard titleError == .success else {
            return nil
        }

        return titleValue as? String
    }

    private func activeTabContext(for browser: SupportedMeetingBrowser) -> (url: String?, title: String?)? {
        guard let scriptingApplicationName = browser.scriptingApplicationName,
              let scriptingFamily = browser.scriptingFamily else {
            return nil
        }

        let source: String
        switch scriptingFamily {
        case .safari:
            source = """
            tell application "\(scriptingApplicationName)"
                if (count of windows) is 0 then return {"", ""}
                set currentURL to URL of current tab of front window
                set currentTitle to name of front document
                return {currentURL, currentTitle}
            end tell
            """
        case .chromium:
            source = """
            tell application "\(scriptingApplicationName)"
                if (count of windows) is 0 then return {"", ""}
                set currentTab to active tab of front window
                return {URL of currentTab, title of currentTab}
            end tell
            """
        }

        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return nil
        }

        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo,
           let errorNumber = errorInfo[NSAppleScript.errorNumber] as? Int {
            if errorNumber == -1743 {
                automationAvailability = .denied
            }
            return nil
        }

        automationAvailability = .available
        guard descriptor.numberOfItems >= 2 else {
            return nil
        }

        let url = blankToNil(descriptor.atIndex(1)?.stringValue)
        let title = blankToNil(descriptor.atIndex(2)?.stringValue)
        return (url: url, title: title)
    }

    private static func matchingMeetingSurfaceName(url: String?, title: String?) -> String? {
        let normalizedURL = url?.lowercased() ?? ""
        let normalizedTitle = title?.lowercased() ?? ""

        if normalizedURL.contains("meet.google.com/")
            || normalizedTitle.contains("google meet") {
            return "Google Meet"
        }

        if normalizedURL.contains("teams.microsoft.com")
            || normalizedTitle.contains("microsoft teams") {
            return "Teams Web"
        }

        if normalizedURL.contains("zoom.us/wc")
            || normalizedURL.contains("app.zoom.us/wc")
            || normalizedTitle.contains("zoom meeting") {
            return "Zoom Web"
        }

        if normalizedURL.contains("web.whatsapp.com"),
           normalizedTitle.contains("call") || normalizedTitle.contains("video") || normalizedTitle.contains("voice") {
            return "WhatsApp Web"
        }

        return nil
    }

    private func blankToNil(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
protocol BrowserMeetingDetectionServicing {
    var capabilityState: BrowserDetectionCapabilityState { get }
    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void)
    func stop()
}

@MainActor
final class LiveBrowserMeetingDetectionService: BrowserMeetingDetectionServicing {
    private let workspace: NativeMeetingApplicationWorkspace
    private let activityMonitor: BrowserMeetingActivityMonitoring
    private let contextInspector: BrowserMeetingContextInspecting
    private let supportedBrowsers: [SupportedMeetingBrowser]
    private let nowProvider: () -> Date
    private let pollingIntervalNanoseconds: UInt64

    private var activationObserver: AnyObject?
    private var onDetection: (@MainActor (PendingMeetingDetection) -> Void)?
    private var frontmostBrowser: SupportedMeetingBrowser?
    private var frontmostApplication: NativeMeetingRunningApplication?
    private var latestActivitySnapshot: BrowserMeetingActivitySnapshot?
    private var latestContextSnapshot: BrowserMeetingContextSnapshot?
    private var lastDetectionSignature: String?
    private var browserSessionWasMeetingLike = false
    private var lastEndSuggestionSignature: String?
    private var pollingTask: Task<Void, Never>?

    var capabilityState: BrowserDetectionCapabilityState {
        contextInspector.capabilityState
    }

    init(
        workspace: NativeMeetingApplicationWorkspace = LiveNativeMeetingApplicationWorkspace(),
        activityMonitor: BrowserMeetingActivityMonitoring = LiveBrowserMeetingActivityMonitor(),
        contextInspector: BrowserMeetingContextInspecting = LiveBrowserMeetingContextInspector(),
        supportedBrowsers: [SupportedMeetingBrowser] = SupportedMeetingBrowser.defaults,
        nowProvider: @escaping () -> Date = Date.init,
        pollingInterval: TimeInterval = 1.5
    ) {
        self.workspace = workspace
        self.activityMonitor = activityMonitor
        self.contextInspector = contextInspector
        self.supportedBrowsers = supportedBrowsers
        self.nowProvider = nowProvider
        self.pollingIntervalNanoseconds = UInt64(max(pollingInterval, 0.25) * 1_000_000_000)
    }

    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void) {
        self.onDetection = onDetection

        if activationObserver == nil {
            activationObserver = workspace.observeActivation { [weak self] application in
                self?.handleActivation(of: application)
            }
        }

        activityMonitor.start { [weak self] snapshot in
            self?.handleActivityUpdate(snapshot)
        }

        startPollingContext()
        handleActivation(of: workspace.frontmostApplication)
    }

    func stop() {
        if let activationObserver {
            workspace.removeObserver(activationObserver)
        }
        activationObserver = nil
        pollingTask?.cancel()
        pollingTask = nil
        activityMonitor.stop()
        onDetection = nil
        frontmostBrowser = nil
        frontmostApplication = nil
        latestActivitySnapshot = nil
        latestContextSnapshot = nil
        lastDetectionSignature = nil
        browserSessionWasMeetingLike = false
        lastEndSuggestionSignature = nil
    }

    private func handleActivation(of application: NativeMeetingRunningApplication?) {
        let previousBrowser = frontmostBrowser
        frontmostApplication = application
        frontmostBrowser = application.flatMap(supportedBrowser(for:))

        if previousBrowser != frontmostBrowser,
           let previousBrowser,
           browserSessionWasMeetingLike {
            emitEndSuggestion(
                for: previousBrowser,
                title: latestContextSnapshot?.preferredMeetingTitle ?? "Untitled Meeting",
                at: nowProvider()
            )
            browserSessionWasMeetingLike = false
        }

        if frontmostBrowser == nil {
            latestContextSnapshot = nil
            lastDetectionSignature = nil
        }

        refreshContextAndEvaluate(detectedAt: nowProvider())
    }

    private func handleActivityUpdate(_ snapshot: BrowserMeetingActivitySnapshot) {
        latestActivitySnapshot = snapshot
        refreshContextAndEvaluate(detectedAt: snapshot.capturedAt)
    }

    private func startPollingContext() {
        guard pollingTask == nil else {
            return
        }

        pollingTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.handleActivation(of: self.workspace.frontmostApplication)
                }
            }
        }
    }

    private func refreshContextAndEvaluate(detectedAt: Date) {
        if let application = frontmostApplication, let browser = frontmostBrowser {
            latestContextSnapshot = contextInspector.inspect(
                application: application,
                browser: browser,
                capturedAt: detectedAt
            )
        } else {
            latestContextSnapshot = nil
        }

        evaluateDetection(detectedAt: detectedAt)
    }

    private func evaluateDetection(detectedAt: Date) {
        guard let browser = frontmostBrowser else {
            return
        }

        let context = latestContextSnapshot
        let activitySnapshot = latestActivitySnapshot
        let detection: PendingMeetingDetection?

        if context?.isLikelyMeetingPage == true {
            detection = PendingMeetingDetection(
                title: context?.preferredMeetingTitle ?? "Untitled Meeting",
                source: .browser(browser.displayName),
                phase: .start,
                detectedAt: detectedAt,
                presentation: .prompt,
                confidence: .high
            )
        } else if activitySnapshot?.isMicrophoneActive == true {
            detection = PendingMeetingDetection(
                title: context?.preferredMeetingTitle ?? "Untitled Meeting",
                source: .browser(browser.displayName),
                phase: .start,
                detectedAt: detectedAt,
                presentation: .prompt,
                confidence: .high
            )
        } else if activitySnapshot?.isSystemAudioActive == true {
            detection = PendingMeetingDetection(
                title: context?.preferredMeetingTitle ?? "Untitled Meeting",
                source: .browser(browser.displayName),
                phase: .start,
                detectedAt: detectedAt,
                presentation: .passiveSuggestion,
                confidence: .low
            )
        } else {
            if browserSessionWasMeetingLike {
                emitEndSuggestion(
                    for: browser,
                    title: context?.preferredMeetingTitle ?? "Untitled Meeting",
                    at: detectedAt
                )
                browserSessionWasMeetingLike = false
            }
            lastDetectionSignature = nil
            return
        }

        guard let detection else {
            return
        }

        browserSessionWasMeetingLike = true
        lastEndSuggestionSignature = nil
        let signature = [
            browser.bundleIdentifier,
            detection.presentation.rawValue,
            detection.confidence.rawValue,
            context?.signature ?? "no-context"
        ].joined(separator: "|")

        guard signature != lastDetectionSignature else {
            return
        }

        lastDetectionSignature = signature
        onDetection?(detection)
    }

    private func emitEndSuggestion(for browser: SupportedMeetingBrowser, title: String, at detectedAt: Date) {
        let signature = "\(browser.bundleIdentifier)|\(title.lowercased())|end"
        guard signature != lastEndSuggestionSignature else {
            return
        }

        lastEndSuggestionSignature = signature
        onDetection?(
            PendingMeetingDetection(
                title: title,
                source: .browser(browser.displayName),
                phase: .endSuggestion,
                detectedAt: detectedAt,
                presentation: .prompt,
                confidence: .low
            )
        )
    }

    private func supportedBrowser(for application: NativeMeetingRunningApplication) -> SupportedMeetingBrowser? {
        guard let bundleIdentifier = application.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty else {
            return nil
        }

        if let exact = supportedBrowsers.first(where: { $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }) {
            return exact
        }

        if let fallbackName = application.localizedName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fallbackName.isEmpty {
            return supportedBrowsers.first(where: { $0.displayName.caseInsensitiveCompare(fallbackName) == .orderedSame })
        }

        return nil
    }
    private func blankToNil(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
