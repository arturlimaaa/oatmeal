import OatmealUI
import SwiftUI

@main
struct OatmealMacApp: App {
    private let packageApp = OatmealPackageApp()

    var body: some Scene {
        packageApp.body
    }
}
