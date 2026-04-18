import OatmealCore
import SwiftUI

@MainActor
struct SessionControllerCommandRouter {
    let model: AppViewModel
    let coordinator: SessionControllerSceneCoordinator

    @discardableResult
    func openMainWindow(
        openTranscript: Bool = false
    ) -> AppViewModel.LightweightSurfaceMainWindowRoute {
        coordinator.openMainWindow(with: model, openTranscript: openTranscript)
    }

    func reopenSessionController() {
        model.reopenSessionController()
        coordinator.reopenSessionController()
    }

    func syncSessionControllerWindow() {
        coordinator.syncSessionControllerWindow(with: model)
    }

    func syncDetectionPromptWindow() {
        coordinator.syncDetectionPromptWindow(with: model)
    }

    func presentSessionControllerOnLaunchIfNeeded() {
        coordinator.presentSessionControllerOnLaunchIfNeeded(with: model)
    }

    func startQuickNoteCapture() async {
        await model.startQuickNoteCapture()
        syncSessionControllerWindow()
    }

    func stopCapture() async {
        await model.stopSessionControllerCapture()
        syncSessionControllerWindow()
    }

    func ignorePendingMeetingDetection() {
        model.ignorePendingMeetingDetectionPrompt()
        syncDetectionPromptWindow()
    }

    func clearPendingMeetingDetection() {
        model.clearPendingMeetingDetection()
        syncDetectionPromptWindow()
    }

    func receiveMeetingDetection(_ detection: PendingMeetingDetection) {
        model.receiveMeetingDetection(detection)
        syncDetectionPromptWindow()
    }

    func selectPendingMeetingCandidate(_ eventID: CalendarEvent.ID) {
        model.selectPendingMeetingCandidate(eventID)
        syncDetectionPromptWindow()
    }

    func startPendingMeetingDetection() async {
        await model.startPendingMeetingDetectionCapture()
        syncDetectionPromptWindow()
        syncSessionControllerWindow()
    }
}
