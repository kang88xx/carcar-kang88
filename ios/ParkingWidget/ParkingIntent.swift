import AppIntents
import Foundation
import WidgetKit

struct ParkingActionIntent: AppIntent {
    static var title: LocalizedStringResource = "주차 위치 기록"
    static var openAppWhenRun: Bool = false
    @Parameter(title: "동작") var action: String
    init() { action = "save" }
    init(_ action: String) { self.action = action }
    func perform() async throws -> some IntentResult {
        defer { WidgetCenter.shared.reloadAllTimelines() }
        if ["floor", "zone"].contains(action) { try WidgetSession.cycle(action) }
        else if action == "save" { try await save() }
        return .result()
    }
    private func save() async throws {
        let captured: ([String: Any], [String: Any])? = try WidgetSession.locked {
            var draft = try WidgetSession.display()
            guard draft["enabled"] as? Bool == true, draft["busy"] as? Bool != true,
                  let session = try WidgetSession.read() else { return nil }
            if draft["requestId"] == nil { draft["requestId"] = UUID().uuidString.lowercased() }
            draft["operation"] = UUID().uuidString
            draft["busyUntil"] = Date().addingTimeInterval(20).timeIntervalSince1970
            draft["status"] = "서버에 저장 중…"
            try WidgetSession.write(draft)
            return (session, draft)
        }
        guard let (session, initial) = captured else { return }
        WidgetCenter.shared.reloadAllTimelines()
        var record: [String: Any]?
        var message = "저장하지 못했어요 · 다시 시도"
        do {
            guard let root = session["url"] as? String, let url = URL(string: root.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/rest/v1/rpc/create_parking_record_and_set_latest") else { throw WidgetSession.Failure.invalid }
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(session["publishableKey"] as? String, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(session["accessToken"] as? String ?? "")", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["p_vehicle_id": session["vehicleId"]!, "p_floor": initial["floor"]!, "p_zone": initial["zone"]!, "p_spot": "", "p_note": "", "p_idempotency_key": initial["requestId"]!])
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 12
            let network = URLSession(configuration: config, delegate: NoWidgetRedirect(), delegateQueue: nil)
            defer { network.invalidateAndCancel() }
            let (data, response) = try await network.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw WidgetSession.Failure.server }
            if [401, 403].contains(response.statusCode) { message = "앱을 열어 로그인·차량 권한 확인" }
            guard (200...299).contains(response.statusCode), data.count <= 65536,
                  let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = value["id"] as? String, UUID(uuidString: id) != nil,
                  let created = value["created_at"] as? String, validDate(created),
                  let spot = value["spot"] as? String, spot.count <= 20,
                  value["vehicle_id"] as? String == (session["vehicleId"] as? String)?.lowercased(),
                  value["created_by"] as? String == (session["userId"] as? String)?.lowercased(),
                  value["idempotency_key"] as? String == (initial["requestId"] as? String)?.lowercased(),
                  value["floor"] as? String == initial["floor"] as? String,
                  value["zone"] as? String == initial["zone"] as? String else { throw WidgetSession.Failure.server }
            record = value
        } catch { /* Fail closed. Never persist or log network error bodies or credentials. */ }
        try WidgetSession.locked {
            guard try WidgetSession.read()?["generation"] as? String == session["generation"] as? String,
                  try WidgetSession.state()["operation"] as? String == initial["operation"] as? String else { return }
            var draft = initial; draft.removeValue(forKey: "busyUntil")
            if let record = record {
                guard let defaults = UserDefaults(suiteName: WidgetSession.group) else { throw WidgetSession.Failure.storage }
                var snapshot = defaults.dictionary(forKey: "parkingSnapshot") ?? [:]
                for field in ["floor", "zone", "spot"] { snapshot[field] = record[field] }
                snapshot["updatedAt"] = record["created_at"]; snapshot["isDemo"] = false
                snapshot["userId"] = session["userId"]; snapshot["vehicleId"] = session["vehicleId"]
                try WidgetSnapshots.merge(snapshot)
                draft["status"] = "저장했어요"; draft.removeValue(forKey: "requestId")
            } else { draft["status"] = message }
            try WidgetSession.write(draft)
        }
    }
    private func validDate(_ value: String) -> Bool {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if parser.date(from: value) != nil { return true }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: value) != nil
    }
}

private final class NoWidgetRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
