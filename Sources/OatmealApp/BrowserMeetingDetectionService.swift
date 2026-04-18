import CoreAudio
import Foundation

struct SupportedMeetingBrowser: Equatable, Sendable {
    let bundleIdentifier: String
    let displayName: String

    static let defaults: [SupportedMeetingBrowser] = [
        SupportedMeetingBrowser(bundleIdentifier: "com.apple.Safari", displayName: "Safari"),
        SupportedMeetingBrowser(bundleIdentifier: "com.google.Chrome", displayName: "Google Chrome"),
        SupportedMeetingBrowser(bundleIdentifier: "com.google.Chrome.canary", displayName: "Google Chrome Canary"),
        SupportedMeetingBrowser(bundleIdentifier: "company.thebrowser.Browser", displayName: "Arc"),
        SupportedMeetingBrowser(bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox"),
        SupportedMeetingBrowser(bundleIdentifier: "com.microsoft.edgemac", displayName: "Microsoft Edge"),
        SupportedMeetingBrowser(bundleIdentifier: "com.brave.Browser", displayName: "Brave"),
        SupportedMeetingBrowser(bundleIdentifier: "com.operasoftware.Opera", displayName: "Opera")
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
protocol BrowserMeetingDetectionServicing {
    func start(onDetection: @escaping @MainActor (PendingMeetingDetection) -> Void)
    func stop()
}

@MainActor
final class LiveBrowserMeetingDetectionService: BrowserMeetingDetectionServicing {
    private let workspace: NativeMeetingApplicationWorkspace
    private let activityMonitor: BrowserMeetingActivityMonitoring
    private let supportedBrowsers: [SupportedMeetingBrowser]
    private let nowProvider: () -> Date

    private var activationObserver: AnyObject?
    private var onDetection: (@MainActor (PendingMeetingDetection) -> Void)?
    private var frontmostBrowser: SupportedMeetingBrowser?
    private var latestActivitySnapshot: BrowserMeetingActivitySnapshot?
    private var lastDetectionSignature: String?
    private var browserSessionWasMeetingLike = false
    private var lastEndSuggestionSignature: String?

    init(
        workspace: NativeMeetingApplicationWorkspace = LiveNativeMeetingApplicationWorkspace(),
        activityMonitor: BrowserMeetingActivityMonitoring = LiveBrowserMeetingActivityMonitor(),
        supportedBrowsers: [SupportedMeetingBrowser] = SupportedMeetingBrowser.defaults,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.workspace = workspace
        self.activityMonitor = activityMonitor
        self.supportedBrowsers = supportedBrowsers
        self.nowProvider = nowProvider
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

        handleActivation(of: workspace.frontmostApplication)
    }

    func stop() {
        if let activationObserver {
            workspace.removeObserver(activationObserver)
        }
        activationObserver = nil
        activityMonitor.stop()
        onDetection = nil
        frontmostBrowser = nil
        latestActivitySnapshot = nil
        lastDetectionSignature = nil
        browserSessionWasMeetingLike = false
        lastEndSuggestionSignature = nil
    }

    private func handleActivation(of application: NativeMeetingRunningApplication?) {
        let previousBrowser = frontmostBrowser
        frontmostBrowser = application.flatMap(supportedBrowser(for:))
        if previousBrowser != frontmostBrowser,
           let previousBrowser,
           browserSessionWasMeetingLike {
            emitEndSuggestion(for: previousBrowser, at: nowProvider())
            browserSessionWasMeetingLike = false
        }

        if frontmostBrowser == nil {
            lastDetectionSignature = nil
        }
        evaluateDetection()
    }

    private func handleActivityUpdate(_ snapshot: BrowserMeetingActivitySnapshot) {
        latestActivitySnapshot = snapshot
        if snapshot.presentation == nil {
            if let browser = frontmostBrowser, browserSessionWasMeetingLike {
                emitEndSuggestion(for: browser, at: snapshot.capturedAt)
                browserSessionWasMeetingLike = false
            }
            lastDetectionSignature = nil
        }
        evaluateDetection()
    }

    private func evaluateDetection() {
        guard let browser = frontmostBrowser,
              let snapshot = latestActivitySnapshot,
              let presentation = snapshot.presentation else {
            return
        }

        browserSessionWasMeetingLike = true
        lastEndSuggestionSignature = nil
        let signature = "\(browser.bundleIdentifier)|\(presentation.rawValue)"
        guard signature != lastDetectionSignature else {
            return
        }

        lastDetectionSignature = signature
        onDetection?(
            PendingMeetingDetection(
                title: "Untitled Meeting",
                source: .browser(browser.displayName),
                phase: .start,
                detectedAt: snapshot.capturedAt,
                presentation: presentation
            )
        )
    }

    private func emitEndSuggestion(for browser: SupportedMeetingBrowser, at detectedAt: Date) {
        let signature = "\(browser.bundleIdentifier)|end"
        guard signature != lastEndSuggestionSignature else {
            return
        }

        lastEndSuggestionSignature = signature
        onDetection?(
            PendingMeetingDetection(
                title: "Untitled Meeting",
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
}
