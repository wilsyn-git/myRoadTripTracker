import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Generates a short recap blurb on-device via Foundation Models.
/// Returns nil when the model is unavailable (caller falls back to RecapStats.templateNarrative).
enum RecapNarrativeGenerator {

    static func generate(from stats: RecapStats, tripName: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return nil }

            let instructions = """
            You write a short, warm, upbeat recap of a family road-trip license-plate \
            spotting game. Use ONLY the facts provided — never invent numbers or places. \
            Keep it to 2-3 sentences. No hashtags, no emoji.
            """
            let session = LanguageModelSession(instructions: instructions)
            let prompt = "Write the recap from these facts:\n\(stats.promptDescription(tripName: tripName))"
            do {
                let response = try await session.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch {
                #if DEBUG
                print("[RecapNarrativeGenerator] FoundationModels error: \(error)")
                #endif
                return nil
            }
        }
        #endif
        return nil
    }
}
