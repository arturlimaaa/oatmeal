import AVFoundation
import CoreGraphics
import Foundation
import OatmealCore
import UserNotifications

@MainActor
protocol CaptureAccessServing {
    func currentPermissions(calendarStatus: PermissionStatus) async -> CapturePermissions
    func requestPermissions(requiresSystemAudio: Bool, calendarStatus: PermissionStatus) async -> CapturePermissions
}

@MainActor
final class LiveCaptureAccessService: CaptureAccessServing {
    private let defaults: UserDefaults
    private let notificationsSupported: Bool
    private let systemAudioPromptedKey = "capture.systemAudioPrompted"

    init(
        defaults: UserDefaults = .standard,
        notificationsSupported: Bool? = nil
    ) {
        self.defaults = defaults
        self.notificationsSupported = notificationsSupported ?? Self.canUseUserNotificationCenter()
    }

    func currentPermissions(calendarStatus: PermissionStatus) async -> CapturePermissions {
        CapturePermissions(
            microphone: microphonePermissionStatus(),
            systemAudio: systemAudioPermissionStatus(),
            notifications: await notificationPermissionStatus(),
            calendar: calendarStatus
        )
    }

    func requestPermissions(requiresSystemAudio: Bool, calendarStatus: PermissionStatus) async -> CapturePermissions {
        if microphonePermissionStatus() == .notDetermined {
            _ = await requestMicrophoneAccess()
        }

        if requiresSystemAudio, systemAudioPermissionStatus() != .granted {
            defaults.set(true, forKey: systemAudioPromptedKey)
            _ = CGRequestScreenCaptureAccess()
        }

        let notificationStatus = await notificationPermissionStatus()
        if notificationStatus == .notDetermined, let notificationCenter = notificationCenter() {
            _ = try? await notificationCenter.requestAuthorization(options: [.badge, .sound, .alert])
        }

        return await currentPermissions(calendarStatus: calendarStatus)
    }

    private func microphonePermissionStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .granted
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func systemAudioPermissionStatus() -> PermissionStatus {
        if CGPreflightScreenCaptureAccess() {
            return .granted
        }

        return defaults.bool(forKey: systemAudioPromptedKey) ? .denied : .notDetermined
    }

    private func notificationPermissionStatus() async -> PermissionStatus {
        guard let notificationCenter = notificationCenter() else {
            return .restricted
        }

        let settings = await notificationCenter.notificationSettings()
        return switch settings.authorizationStatus {
        case .notDetermined:
            .notDetermined
        case .authorized, .provisional, .ephemeral:
            .granted
        case .denied:
            .denied
        @unknown default:
            .restricted
        }
    }

    private func notificationCenter() -> UNUserNotificationCenter? {
        guard notificationsSupported else {
            return nil
        }

        return .current()
    }

    private static func canUseUserNotificationCenter(
        bundleURL: URL = Bundle.main.bundleURL,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        let hasAppBundle = bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
        let hasBundleIdentifier = !(bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasAppBundle && hasBundleIdentifier
    }
}
