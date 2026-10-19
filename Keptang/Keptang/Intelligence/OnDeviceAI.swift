import FoundationModels

/// Apple Intelligence's on-device language model (Foundation Models framework).
enum OnDeviceAI {
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    static var statusText: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Apple Intelligence reads your receipts on this device."
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This device can't run Apple Intelligence, so receipts are read with built-in text rules."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in Settings for smarter receipt reading. Text rules are used until then."
            case .modelNotReady:
                return "Apple Intelligence is still getting ready. Text rules are used for now."
            @unknown default:
                return "Apple Intelligence isn't available right now. Text rules are used instead."
            }
        }
    }
}
