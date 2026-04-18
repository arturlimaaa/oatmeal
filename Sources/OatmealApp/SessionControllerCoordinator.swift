import SwiftUI

@MainActor
struct SessionControllerSceneCoordinator {
    let openWindow: (String) -> Void
    let dismissWindow: (String) -> Void

    func syncSessionControllerWindow(with model: AppViewModel) {
        if model.sessionControllerState != nil, !model.isSessionControllerDismissedForCurrentState {
            openWindow(OatmealSceneID.sessionController)
        } else {
            dismissWindow(OatmealSceneID.sessionController)
        }
    }

    func presentSessionControllerOnLaunchIfNeeded(with model: AppViewModel) {
        guard model.shouldAutoPresentSessionControllerOnLaunch else {
            return
        }

        openWindow(OatmealSceneID.sessionController)
    }

    @discardableResult
    func openMainWindow(
        with model: AppViewModel,
        openTranscript: Bool = false
    ) -> AppViewModel.LightweightSurfaceMainWindowRoute {
        let route = model.routeMainWindowFromLightweightSurface(openTranscript: openTranscript)
        openWindow(OatmealSceneID.main)
        return route
    }

    func reopenSessionController() {
        openWindow(OatmealSceneID.sessionController)
    }
}
