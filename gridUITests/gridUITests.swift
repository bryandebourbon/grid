//
//  gridUITests.swift
//  gridUITests
//
//  Created by Bryan de Bourbon on 5/24/25.
//

import XCTest

final class gridUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testLaunchShowsSignInOrContent() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // On a fresh install with no stored credentials the app resolves to the
        // welcome / Sign in with Apple screen. Allow time for the async
        // credential-state check to complete.
        let welcome = app.staticTexts["Welcome to Grid"]
        let appeared = welcome.waitForExistence(timeout: 15)

        // If credentials happen to exist the app proceeds past sign-in; either
        // way the app must not have crashed and should be running.
        XCTAssertTrue(appeared || app.state == .runningForeground)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
