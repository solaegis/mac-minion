import Foundation
import FoundationModels

/// On-device Apple Intelligence via the Foundation Models framework. No API key and no network:
/// prompts stay on this Mac. Not an `LLMProvider` — that protocol is HTTP-shaped.
public enum AppleIntelligence: Sendable {
    public static let displayName = "Apple Intelligence"

    /// Why the system model cannot run, or that it can.
    public enum Status: Equatable, Sendable {
        case available
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
    }

    /// Tests set this; production leaves it `nil` and reads the system model.
    nonisolated(unsafe) public static var statusOverride: Status?

    public static var status: Status {
        if let statusOverride { return statusOverride }
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(.deviceNotEligible): return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady): return .modelNotReady
        case .unavailable: return .modelNotReady
        @unknown default: return .modelNotReady
        }
    }

    public static var isAvailable: Bool { status == .available }

    /// Human-readable status for Settings, or `nil` when ready.
    public static var statusMessage: String {
        switch status {
        case .available: String(localized: "Available", bundle: .kit)
        case .deviceNotEligible:
            String(localized: "This Mac doesn't support Apple Intelligence.", bundle: .kit)
        case .appleIntelligenceNotEnabled:
            String(localized: "Turn on Apple Intelligence in System Settings.", bundle: .kit)
        case .modelNotReady:
            String(localized: "Apple Intelligence isn't ready yet. Try again in a moment.", bundle: .kit)
        }
    }

    /// Why a request can't be sent, or `nil` when it can.
    public static var unavailableReason: String? {
        status == .available ? nil : statusMessage
    }

    /// Streams one answer. `onText` gets the whole answer so far after every snapshot.
    public static func stream(system: String, prompt: String,
                              onText: @Sendable (String) async -> Void) async throws -> String {
        if let why = unavailableReason { throw AIError.notConfigured(why) }
        let session = LanguageModelSession(instructions: system)
        var text = ""
        do {
            let response = session.streamResponse(to: prompt)
            for try await snapshot in response {
                text = snapshot.content
                await onText(text)
            }
        } catch {
            throw mapError(error)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.empty }
        return trimmed
    }

    static func mapError(_ error: Error) -> Error {
        if error is AIError || error is CancellationError { return error }
        // Map GenerationError only. LanguageModelError is not in every macOS 26 SDK the
        // release runner uses; GenerationError covers the same refusal / rate-limit cases.
        if let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .refusal:
                return AIError.refused(e.failureReason)
            case .guardrailViolation:
                return AIError.refused(nil)
            case .rateLimited:
                return AIError.rateLimited(displayName)
            case .exceededContextWindowSize:
                return AIError.http(0, String(localized: "The prompt is too long for Apple Intelligence.", bundle: .kit))
            case .assetsUnavailable:
                return AIError.notConfigured(String(localized: "Apple Intelligence isn't ready yet. Try again in a moment.", bundle: .kit))
            default:
                return AIError.http(0, e.localizedDescription)
            }
        }
        return AIError.http(0, error.localizedDescription)
    }
}
