import XCTest

/// Keyboard Send must deliver the message and leave the field focused.
/// The composer circle is gone; this is the Snap Return key labeled Send.
final class ChatSendUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testKeyboardSendKeepsFocusAndDeliversMessage() throws {
        let app = launchHarness()
        tap(app.buttons["uitest.open.me"])
        XCTAssertTrue(app.descendants(matching: .any)["chat.title"].waitForExistence(timeout: 8))

        let composer = app.textFields["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 6), "Composer field missing")
        tap(composer)
        XCTAssertTrue(
            app.keyboards.element.waitForExistence(timeout: 4) || isKeyboardFocused(composer),
            "Composer never took keyboard focus"
        )

        let ping = "keyboard-send-ping-\(Int(Date().timeIntervalSince1970))"
        composer.typeText(ping)
        tapKeyboardSend(in: app, composer: composer)

        let bubble = app.staticTexts[ping]
        XCTAssertTrue(bubble.waitForExistence(timeout: 6), "Send did not deliver \(ping)")
        XCTAssertTrue(
            app.keyboards.element.exists || isKeyboardFocused(composer),
            "Keyboard Send resigned the field — keyboard collapsed"
        )
    }

    @MainActor
    private func launchHarness() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["gridUITestHarness"]
        app.launch()
        XCTAssertTrue(
            app.buttons["uitest.open.me"].waitForExistence(timeout: 12),
            "Harness Open Me never appeared"
        )
        return app
    }

    @MainActor
    private func tapKeyboardSend(in app: XCUIApplication, composer: XCUIElement) {
        let keys = [
            app.keyboards.buttons["send"],
            app.keyboards.buttons["Send"],
            app.buttons["send"],
            app.buttons["Send"]
        ]
        if let send = keys.first(where: { $0.waitForExistence(timeout: 2) }) {
            tap(send)
            return
        }
        composer.typeText("\n")
    }

    @MainActor
    private func isKeyboardFocused(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) == true
    }

    @MainActor
    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 6), "Missing \(element)")
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }
}
