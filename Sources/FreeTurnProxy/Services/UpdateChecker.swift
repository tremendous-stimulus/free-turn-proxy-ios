import Foundation

enum UpdateChecker {
    // URL apps.json зависит от таргета (bundle id).
    private static var appsJSONURL: URL {
        let isTest = Bundle.main.bundleIdentifier == "com.freeturn.proxy.testing"
        let branch = isTest ? "testing" : "main"
        return URL(string: "https://raw.githubusercontent.com/tremendous-stimulus/free-turn-proxy-ios/\(branch)/apps.json")!
    }

    // Текущая версия приложения.
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    // Асинхронно получает последнюю версию из apps.json.
    // Возвращает версию строкой если она новее текущей, иначе nil.
    static func fetchLatestVersion() async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: appsJSONURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apps = json["apps"] as? [[String: Any]],
              let latest = apps.first?["version"] as? String else { return nil }
        return isNewer(latest, than: currentVersion) ? latest : nil
    }

    // Сравнение semver: возвращает true если a > b.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").compactMap { Int($0) }
        let bv = b.split(separator: ".").compactMap { Int($0) }
        let len = max(av.count, bv.count)
        for i in 0 ..< len {
            let ai = i < av.count ? av[i] : 0
            let bi = i < bv.count ? bv[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }
}
