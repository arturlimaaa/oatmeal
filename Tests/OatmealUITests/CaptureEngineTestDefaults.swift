import Foundation
@testable import OatmealUI

extension MeetingCaptureEngineServing {
    func availableMicrophones() -> [CaptureInputDevice] {
        []
    }

    func activeMicrophoneID(for noteID: UUID) -> String? {
        nil
    }

    func switchMicrophone(to id: String, for noteID: UUID) async throws {}
}
