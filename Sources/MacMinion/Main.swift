import Foundation

/// Starts the CLI when there is a command after the app's name, else the app.
@main
enum Main {
    static func main() {
        if let code = AgentCLI.runIfRequested() { exit(code) }
        // Before SwiftUI loads menus and windows, so Bundle localization sees it.
        LanguageController.applySaved()
        MacMinionApp.main()
    }
}
