import ActivityKit
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
