import Foundation

enum CertificateChecker {
    // Читает ExpirationDate из embedded.mobileprovision.
    // Возвращает nil если файла нет (симулятор, Xcode-запуск без профиля).
    // Возвращает nil если сертификат уже истёк.
    // Иначе — количество дней с округлением вверх (6.3 → 7).
    static func daysUntilExpiry() -> Int? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }

        let start = Data("<?xml".utf8)
        let end = Data("</plist>".utf8)
        guard let startRange = data.range(of: start),
              let endRange = data.range(of: end) else { return nil }

        let xmlData = data[startRange.lowerBound ..< endRange.upperBound]
        guard let plist = try? PropertyListSerialization.propertyList(
                from: Data(xmlData), format: nil) as? [String: Any],
              let expDate = plist["ExpirationDate"] as? Date else { return nil }

        let seconds = expDate.timeIntervalSince(Date())
        guard seconds > 0 else { return nil }
        return Int(ceil(seconds / 86400))
    }
}
