import Foundation
import Observation

enum Appearance: String, CaseIterable, Identifiable { case system, dark, light; var id: String { rawValue } }
@MainActor @Observable final class Preferences {
    private let defaults: UserDefaults
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    var biometrics: Bool { didSet { defaults.set(biometrics, forKey: "biometrics") } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "dark") ?? .dark
        biometrics = defaults.bool(forKey: "biometrics")
    }
    func completedOnboarding(for id: String) -> Bool { defaults.bool(forKey: "onboarding.\(id)") }
    func completeOnboarding(for id: String) { defaults.set(true, forKey: "onboarding.\(id)") }
}
