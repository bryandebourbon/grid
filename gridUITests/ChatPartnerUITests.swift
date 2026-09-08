import XCTest

/// Taps and swipes the signed-in grid. This is the same-chat bug:
/// two different faces must open two different threads.
final class ChatPartnerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTappingTwoPeopleOpensTwoDifferentChats() throws {
        let app = launchLiveGrid()
        let people = occupiedCells(app)
        XCTAssertGreaterThanOrEqual(people.count, 2, "Need two faces on the grid")

        tap(people[0])
        let first = waitForOpenChat(app)
        tap(element(app, "chat.close"))
        XCTAssertTrue(people[1].waitForExistence(timeout: 6))

        tap(people[1])
        let second = waitForOpenChat(app)
        XCTAssertNotEqual(
            first.partnerID,
            second.partnerID,
            "Same chat opened for two cells (\(first.title) / \(second.title))"
        )
        XCTAssertNotEqual(first.title, second.title, "Two people showed the same header")
    }

    @MainActor
    func testPeopleTabSwipe() throws {
        let app = launchLiveGrid()
        XCTAssertTrue(app.buttons["people.tab.all"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["people.tab.favorites"].exists)

        let grid = app.scrollViews.firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 4))
        grid.swipeLeft()
        grid.swipeRight()
    }

    @MainActor
    func testCloseChatReturnsToGrid() throws {
        let app = launchLiveGrid()
        let people = occupiedCells(app)
        XCTAssertFalse(people.isEmpty)

        tap(people[0])
        XCTAssertTrue(element(app, "chat.close").waitForExistence(timeout: 8))
        tap(element(app, "chat.close"))
        XCTAssertTrue(occupiedCells(app).first?.waitForExistence(timeout: 6) == true)
        XCTAssertFalse(element(app, "chat.close").exists)
    }

    @MainActor
    private func launchLiveGrid() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            occupiedCellQuery(app).firstMatch.waitForExistence(timeout: 20),
            "Live grid never appeared. Sign in on this phone first."
        )
        return app
    }

    @MainActor
    private func occupiedCellQuery(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND NOT identifier CONTAINS %@", "grid.cell.", "empty")
        )
    }

    @MainActor
    private func occupiedCells(_ app: XCUIApplication) -> [XCUIElement] {
        occupiedCellQuery(app).allElementsBoundByIndex
    }

    @MainActor
    private func waitForOpenChat(_ app: XCUIApplication) -> (title: String, partnerID: String) {
        let title = element(app, "chat.title")
        XCTAssertTrue(title.waitForExistence(timeout: 8), "Chat did not open after a cell tap")
        return (title.label, (title.value as? String) ?? title.label)
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
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
