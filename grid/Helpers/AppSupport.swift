import Foundation

enum AppSupport {
    static let email = "bdebourbon@me.com"
    static let legalLastUpdated = "August 29, 2026"

    static var mailtoURL: URL {
        URL(string: "mailto:\(email)")!
    }

    static func reportMailtoURL(
        reportedDisplayName: String,
        reportedDeviceID: String,
        reason: Report.ReportReason,
        details: String?
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        let queryItems = [
            URLQueryItem(name: "subject", value: "Grid user report: \(reason.displayName)"),
            URLQueryItem(
                name: "body",
                value: """
                A user report was submitted in Grid.

                Reported: \(reportedDisplayName)
                Device ID: \(reportedDeviceID)
                Reason: \(reason.displayName)

                Details:
                \(details?.isEmpty == false ? details! : "(none)")
                """
            )
        ]
        components.queryItems = queryItems
        return components.url
    }
}
