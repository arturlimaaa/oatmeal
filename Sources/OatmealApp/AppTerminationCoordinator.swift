import AppKit

struct AppTerminationPrompt: Equatable, Sendable {
    let title: String
    let message: String
    let continueButtonTitle: String
    let stopAndQuitButtonTitle: String
    let quitButtonTitle: String
}

enum AppTerminationChoice: Equatable, Sendable {
    case keepRecording
    case stopAndQuit
    case quitAnyway
}

enum AppTerminationPolicy {
    static func prompt(for state: SessionControllerState?) -> AppTerminationPrompt? {
        guard let state, state.canStopCapture else {
            return nil
        }

        return AppTerminationPrompt(
            title: "Quit While Recording?",
            message: """
            Oatmeal is still recording “\(state.title)” locally. Quitting now will interrupt the live capture. \
            Oatmeal should retain any saved local artifacts and recovered session state for relaunch, but the safest \
            path is to stop capture first so Oatmeal can queue background processing before the app exits.
            """,
            continueButtonTitle: "Keep Recording",
            stopAndQuitButtonTitle: "Stop and Quit",
            quitButtonTitle: "Quit Anyway"
        )
    }

    static func choice(for response: NSApplication.ModalResponse) -> AppTerminationChoice {
        switch response {
        case .alertFirstButtonReturn:
            .keepRecording
        case .alertSecondButtonReturn:
            .stopAndQuit
        default:
            .quitAnyway
        }
    }
}

@MainActor
final class OatmealApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppViewModel?
    private var terminationTask: Task<Void, Never>?

    func bind(model: AppViewModel) {
        self.model = model
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let prompt = AppTerminationPolicy.prompt(for: model?.sessionControllerState) else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        alert.alertStyle = .warning
        alert.addButton(withTitle: prompt.continueButtonTitle)
        alert.addButton(withTitle: prompt.stopAndQuitButtonTitle)
        alert.addButton(withTitle: prompt.quitButtonTitle)

        switch AppTerminationPolicy.choice(for: alert.runModal()) {
        case .quitAnyway:
            return .terminateNow
        case .keepRecording:
            return .terminateCancel
        case .stopAndQuit:
            guard let model else {
                return .terminateNow
            }

            terminationTask?.cancel()
            terminationTask = Task { [weak self] in
                let didStopSafely = await model.stopSessionControllerCaptureForTermination()
                sender.reply(toApplicationShouldTerminate: didStopSafely)
                self?.terminationTask = nil
            }
            return .terminateLater
        }
    }
}
