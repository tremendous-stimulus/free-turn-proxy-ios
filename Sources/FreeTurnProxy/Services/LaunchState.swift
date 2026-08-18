import Foundation

// Разовые факты про установку, которые считаются на старте и дальше живут в
// UserDefaults. Пересчитывать их по текущему состоянию нельзя: наличие
// профилей меняется в обе стороны, и вопрос «пришёл ли пользователь с
// предыдущей версии» после первого запуска ответа уже не меняет.
enum LaunchState {
    // nil — ещё ни разу не считали (свежая установка или апдейт с версии, где
    // этого флага не было). true — на первом запуске профили уже были, то есть
    // пользователь обновился; false — пришёл с нуля либо уже закрыл подсказку
    // про новый режим.
    static func isUpgradedUser(defaults: UserDefaults = .standard) -> Bool? {
        defaults.object(forKey: DefaultsKeys.isUpgradedUser) as? Bool
    }

    static func setUpgradedUser(_ value: Bool, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: DefaultsKeys.isUpgradedUser)
    }

    // Вызывается один раз за запуск приложения. Уже посчитанное значение не
    // трогает — в том числе false, выставленный крестиком на подсказке.
    @discardableResult
    static func resolveUpgradedUser(hasConfigs: Bool, defaults: UserDefaults = .standard) -> Bool {
        if let known = isUpgradedUser(defaults: defaults) { return known }
        setUpgradedUser(hasConfigs, defaults: defaults)
        return hasConfigs
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    // Версия предыдущего запуска — nil на первом. Нужна для миграций и
    // «что нового» в будущих версиях, поэтому пишется всегда, даже если
    // сейчас её никто не читает.
    static func lastRunVersion(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: DefaultsKeys.lastRunVersion)
    }

    // Возвращает версию ПРЕДЫДУЩЕГО запуска и запоминает текущую.
    @discardableResult
    static func recordRun(version: String = currentVersion, defaults: UserDefaults = .standard) -> String? {
        let previous = lastRunVersion(defaults: defaults)
        defaults.set(version, forKey: DefaultsKeys.lastRunVersion)
        return previous
    }
}
