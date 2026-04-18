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
}
