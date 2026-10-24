import Foundation

/// The models Hikki offers, written down here rather than fetched (the owner's call): a short recommended list, the
/// rest under "Other models", and "Auto", which picks a balanced one from the providers that have a key. Each Anthropic
/// model says how it thinks (`AIThinkingStyle`): every one listed here takes adaptive thinking only.
public enum AIModelCatalog {
    public static let opus = AIModel(
        id: "claude-opus-5-5", provider: .anthropic, family: "Opus", version: "5.5", thinking: .adaptive(effort: .medium))
    public static let sonnet = AIModel(
        id: "claude-sonnet-5-5", provider: .anthropic, family: "Sonnet", version: "5.5", thinking: .adaptive(effort: .medium))
    public static let haiku = AIModel(
        id: "claude-haiku-5-5", provider: .anthropic, family: "Haiku", version: "5.5", thinking: .adaptive(effort: .medium))
    public static let gptSol = AIModel(id: "gpt-6.1-sol", provider: .openAI, family: "GPT-6.1", version: "Sol")
    public static let gptAstra = AIModel(id: "gpt-6-astra", provider: .openAI, family: "GPT-6", version: "Astra")

    public static let recommended: [AIModel] = [opus, sonnet, gptSol]
    public static let others: [AIModel] = [haiku, gptAstra]
    public static let all: [AIModel] = recommended + others

    public static func model(id: String) -> AIModel? {
        all.first { $0.id == id }
    }

    /// "Auto": balances speed, effort and cost — Sonnet when there is an Anthropic key, else GPT-6.1 Sol.
    public static func auto(available: Set<AIProvider>) -> AIModel? {
        if available.contains(.anthropic) { return sonnet }
        if available.contains(.openAI) { return gptSol }
        return nil
    }

    /// The model to use for a choice ("auto" or an id): the chosen one when its provider has a key, else Auto's.
    public static func resolve(_ choice: String?, available: Set<AIProvider>) -> AIModel? {
        if let choice, choice != autoID, let model = model(id: choice), available.contains(model.provider) {
            return model
        }
        return auto(available: available)
    }

    public static let autoID = "auto"
}
