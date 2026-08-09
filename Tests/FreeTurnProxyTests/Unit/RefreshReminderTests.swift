import XCTest
@testable import FreeTurnProxy

final class RefreshReminderTests: XCTestCase {

    func test_noAnchor_doesNotShow() {
        XCTAssertFalse(RefreshReminder.shouldShowBanner(anchorAt: nil, now: Date()))
    }

    func test_lessThanIntervalSinceAnchor_doesNotShow() {
        let now = Date()
        let anchor = now.addingTimeInterval(-RefreshReminder.bannerInterval * 0.5)
        XCTAssertFalse(RefreshReminder.shouldShowBanner(anchorAt: anchor, now: now))
    }

    func test_exactlyIntervalSinceAnchor_shows() {
        let now = Date()
        let anchor = now.addingTimeInterval(-RefreshReminder.bannerInterval)
        XCTAssertTrue(RefreshReminder.shouldShowBanner(anchorAt: anchor, now: now))
    }

    func test_moreThanIntervalSinceAnchor_shows() {
        let now = Date()
        let anchor = now.addingTimeInterval(-RefreshReminder.bannerInterval * 3)
        XCTAssertTrue(RefreshReminder.shouldShowBanner(anchorAt: anchor, now: now))
    }

    // Крестик не просто прячет баннер на экране — он отодвигает якорь, так что
    // повторный форграунд в тот же день не должен снова считать баннер «пора
    // показывать».
    func test_dismissBanner_movesAnchorToNow() {
        let defaults = UserDefaults.standard
        let key = DefaultsKeys.refreshBannerAnchorAt
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        let dismissedAt = Date()
        RefreshReminder.dismissBanner(now: dismissedAt)

        let stored = defaults.object(forKey: key) as? Date
        XCTAssertEqual(stored, dismissedAt)
        XCTAssertFalse(RefreshReminder.shouldShowBanner(anchorAt: stored, now: dismissedAt.addingTimeInterval(3600)))
    }
}
