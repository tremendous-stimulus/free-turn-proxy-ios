import Foundation
import UserNotifications

// Точную дату протухания provisioning-профиля узнать нельзя: SideStore Refresh
// перевыпускает профиль в системном хранилище устройства, не трогая
// embedded.mobileprovision в нашем бандле, а само системное хранилище
// (/var/MobileDevice/ProvisioningProfiles) недоступно из песочницы приложения
// (проверено на устройстве — contentsOfDirectory падает с permission denied).
// Поэтому вместо (неизбежно лживого) обратного отсчёта — периодическое
// напоминание: баннер в приложении раз в 3 суток + пуш, если приложение вообще
// не открывали 2 суток.
enum RefreshReminder {
    static let bannerInterval: TimeInterval = 3 * 86400
    static let missedOpenPushInterval: TimeInterval = 2 * 86400
    private static let missedOpenPushID = "sidestore-refresh-reminder"

    // Чистая логика показа баннера — тестируется без UserDefaults/Date().
    // anchorAt — момент первого запуска ИЛИ последнего явного закрытия
    // крестиком (не «когда баннер последний раз пересчитывался на форграунде» —
    // иначе баннер гас бы сам при любом сворачивании/разворачивании, даже без
    // тапа по крестику). nil — анкера ещё нет, баннер молчит.
    static func shouldShowBanner(anchorAt: Date?, now: Date) -> Bool {
        guard let anchorAt else { return false }
        return now.timeIntervalSince(anchorAt) >= bannerInterval
    }

    // Вызывается при каждом возврате приложения в форграунд.
    @discardableResult
    static func onForeground(now: Date = Date()) -> Bool {
        let defaults = UserDefaults.standard
        var anchorAt = defaults.object(forKey: DefaultsKeys.refreshBannerAnchorAt) as? Date
        if anchorAt == nil {
            // Первый запуск после установки — заводим анкер, баннер пока молчит.
            anchorAt = now
            defaults.set(now, forKey: DefaultsKeys.refreshBannerAnchorAt)
        }
        rescheduleMissedOpenPush(now: now)
        return shouldShowBanner(anchorAt: anchorAt, now: now)
    }

    // Явное закрытие баннера крестиком — единственное место (кроме первого
    // запуска), где анкер сдвигается вперёд. Следующий показ — через
    // bannerInterval от этого момента.
    static func dismissBanner(now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: DefaultsKeys.refreshBannerAnchorAt)
    }

    // Пуш «вы давно не открывали приложение» — планируется заново при каждом
    // открытии на +2 суток вперёд. Если пользователь 2 суток не откроет
    // приложение, никто его не отменит и не переставит — он долетит.
    private static func rescheduleMissedOpenPush(now: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [missedOpenPushID])
        let content = UNMutableNotificationContent()
        content.title = "Не забудьте про SideStore"
        content.body = "Вы давно не открывали Free Turn — если профиль не обновился сам, приложение скоро перестанет работать. Откройте SideStore → My Apps → Refresh All."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: missedOpenPushInterval, repeats: false)
        let req = UNNotificationRequest(identifier: missedOpenPushID, content: content, trigger: trigger)
        center.add(req)
    }
}
