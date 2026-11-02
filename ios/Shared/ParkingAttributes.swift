import ActivityKit
import AppIntents
import Foundation

@available(iOS 16.1, *)
struct ParkingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let floor: String
        let zone: String
        let spot: String
        let expiresAt: Date
    }
    let vehicleName: String
}

// Shared by Runner and the widget extension: LiveActivityIntent executes in the app process.
@available(iOS 17.0, *)
struct StopParkingActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "차량 찾기 표시 종료"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "표시 ID") var activityID: String

    init() { activityID = "" }
    init(activityID: String) { self.activityID = activityID }

    func perform() async throws -> some IntentResult {
        // An old button must never dismiss a newer activity or change a parking record.
        if let activity = Activity<ParkingAttributes>.activities.first(where: { $0.id == activityID }) {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
        return .result()
    }
}
