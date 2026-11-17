import MacMinionKit
import SwiftUI

/// A question waiting for you: may the AI provider see saved values for this (S-076)?
struct ValuesRequest: Identifiable {
    let id = UUID()
    let provider: AIProvider
    /// What it's for: "Ask about your game folder".
    let purpose: String
    /// What would be sent, in plain words.
    let items: [String]
    let answer: (Bool) -> Void
}

extension AppModel {
    /// Whether saved values may go to the current AI provider. Off in Settings means never; otherwise you're
    /// asked once per session, showing what would be sent. `nil` with a reason when it may not.
    func allowSendingValues(purpose: String, items: [String]) async -> String? {
        let provider = prefs.aiProvider
        guard prefs.allowsValues(provider) else {
            return String(localized: "\(aiSource) isn't allowed to see saved values. Turn on Allow Saved Values in Settings > AI.")
        }
        if valuesApproved.contains(provider) { return nil }
        let allowed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            valuesRequest = ValuesRequest(provider: provider, purpose: purpose, items: items) { continuation.resume(returning: $0) }
        }
        if allowed { valuesApproved.insert(provider) }
        return allowed ? nil : String(localized: "Nothing was sent.")
    }

    /// Answers the waiting question (the sheet's buttons, and the self-test).
    func answerValuesRequest(_ allowed: Bool) {
        guard let request = valuesRequest else { return }
        valuesRequest = nil
        request.answer(allowed)
    }
}

/// Asks before saved values go to an AI provider for the first time in a session.
struct ValuesPermissionSheet: View {
    @Environment(AppModel.self) private var model
    let request: ValuesRequest

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Label("Send Saved Values to \(model.aiSource)?", systemImage: "hand.raised")
                .font(.title2.bold())
            Text("\(request.purpose) sends \(model.aiSource) some of what your SavedVariables files hold:")
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(request.items, id: \.self) { Label($0, systemImage: "doc.text").foregroundStyle(.secondary) }
            }
            Text(request.provider == .apple || request.provider == .ollama
                 ? String(localized: "It stays on this Mac. You're asked once until MacMinion quits; turn this off for good in Settings > AI.")
                 : String(localized: "It leaves this Mac for \(model.aiSource). You're asked once until MacMinion quits; turn this off for good in Settings > AI."))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Don't Send", role: .cancel) { model.answerValuesRequest(false) }.keyboardShortcut(.cancelAction)
                Button("Allow Until Quit") { model.answerValuesRequest(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xxl)
        .frame(width: 480)
        .fitsContent()
        .noInitialFocus()
        .interactiveDismissDisabled()
    }
}
