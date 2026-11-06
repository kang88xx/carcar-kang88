import XCTest
import Darwin

/// Simulator QA only. Never starts, activates, or changes the app under test.
final class IconAlertWatcherTests: XCTestCase {
    func testAcknowledgeOnlyChagokIconChanges() {
        continueAfterFailure = false
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let carcar = XCUIApplication(bundleIdentifier: "com.kang88.carcar")
        let notices: [(message: String, button: String)] = [
            ("You have changed the icon for “차자리”.", "OK"),
            ("You have changed the icon for \"차자리\".", "OK"),
            ("‘차자리’ 아이콘을 변경했습니다.", "확인")
        ]
        var dismissed = 0
        let deadline = Date().addingTimeInterval(600)
        print("[CARCAR_ICON_WATCHER] ready")
        fflush(stdout)
        while Date() < deadline && dismissed < 2 {
            for application in [springboard, carcar] {
                guard application.state == .runningForeground || application.state == .runningBackground else { continue }
                for alert in application.alerts.allElementsBoundByIndex {
                    guard alert.exists else { continue }
                    let labels = alert.staticTexts.allElementsBoundByIndex.map {
                        $0.label.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                    }
                    guard let notice = notices.first(where: { labels.contains($0.message) }) else { continue }
                    let ok = alert.buttons[notice.button]
                    guard ok.exists && ok.isHittable else { continue }
                    let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    before.name = "chagok-icon-alert-\(dismissed + 1)-before-OK"
                    before.lifetime = .keepAlways
                    add(before)
                    print("[CARCAR_ICON_WATCHER] matched-icon-alert-\(dismissed + 1)")
                    fflush(stdout)
                    ok.tap()
                    dismissed += 1
                    print("[CARCAR_ICON_WATCHER] acknowledged-icon-alert-\(dismissed)")
                    fflush(stdout)
                    break
                }
                if dismissed >= 2 { break }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        print("[CARCAR_ICON_WATCHER] finished-count=\(dismissed)")
        fflush(stdout)
        XCTAssertEqual(dismissed, 2, "Expected initial B2 and confirmed-save B3 icon notices")
    }
}
