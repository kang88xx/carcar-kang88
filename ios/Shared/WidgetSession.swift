import Foundation
import Security
import Darwin

// Shared by Runner and the extension. Credentials never enter App Group preferences.
enum WidgetSession {
    static let group = "group.com.kang88.carcar"
    static func locked<T>(_ body: () throws -> T) throws -> T {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw Failure.storage }
        let fd = open(dir.appendingPathComponent("widget.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Failure.storage }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw Failure.storage }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
    enum Failure: Error { case storage, invalid, server }
    static func query() throws -> [String: Any] {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "WidgetKeychainGroup") as? String, !group.contains("$(") else { throw Failure.storage }
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.kang88.carcar.widget", kSecAttrAccount as String: "session", kSecAttrAccessGroup as String: group]
    }
    static func read() throws -> [String: Any]? {
        var q = try query(); q[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure.storage }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    static func stateURL() throws -> URL {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw Failure.storage }
        return dir.appendingPathComponent("widget-draft.json")
    }
    static func state() throws -> [String: Any] {
        let url = try stateURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
    }
    static func write(_ state: [String: Any]) throws { try JSONSerialization.data(withJSONObject: state).write(to: stateURL(), options: .atomic) }
    static func clear() throws {
        try locked {
            let status = SecItemDelete(try query() as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.storage }
            try write([:])
        }
    }
    static func update(_ args: [String: Any]) throws {
        try locked {
            guard let raw = args["url"] as? String, let url = URLComponents(string: raw), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, ["", "/"].contains(url.path),
                  let user = args["userId"] as? String, UUID(uuidString: user) != nil,
                  let vehicle = args["vehicleId"] as? String, UUID(uuidString: vehicle) != nil,
                  let expiry = args["expiresAt"] as? NSNumber, expiry.doubleValue > Date().timeIntervalSince1970,
                  let token = args["accessToken"] as? String, token.split(separator: ".").count == 3,
                  let key = args["publishableKey"] as? String, publicKey(key),
                  let claims = jwtClaims(token), claims["role"] as? String == "authenticated", claims["sub"] as? String == user,
                  ((claims["exp"] as? NSNumber)?.doubleValue ?? 0) >= expiry.doubleValue else { throw Failure.invalid }
            for field in ["floors", "zones"] {
                guard let values = args[field] as? [String], (1...100).contains(values.count), values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 20 }) else { throw Failure.invalid }
            }
            let old = try read()
            let same = ["userId", "vehicleId", "url"].allSatisfy { old?[$0] as? String == args[$0] as? String }
            var clean: [String: Any] = [:]
            for field in ["url", "publishableKey", "accessToken", "expiresAt", "userId", "vehicleId", "floors", "zones"] { clean[field] = args[field] }
            clean["generation"] = same ? old?["generation"] : UUID().uuidString
            let data = try JSONSerialization.data(withJSONObject: clean)
            let q = try query()
            var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = q; item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(item as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw Failure.storage }
            if !same { try write([:]) }
        }
    }
    static func publicKey(_ key: String) -> Bool {
        key.hasPrefix("sb_publishable_") || (jwtClaims(key)?["role"] as? String == "anon")
    }
    static func jwtClaims(_ token: String) -> [String: Any]? {
        let pieces = token.split(separator: ".")
        guard pieces.count == 3 else { return nil }
        var text = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let bytes = Data(base64Encoded: text), let claims = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return nil }
        return claims
    }
    // Call while holding the process-shared lock.
    static func display() throws -> [String: Any] {
        var value = try state()
        let session = try read()
        let demo = UserDefaults(suiteName: group)?.dictionary(forKey: "parkingSnapshot")?["isDemo"] as? Bool ?? false
        let enabled = !demo && ((session?["expiresAt"] as? NSNumber)?.doubleValue ?? 0) > Date().timeIntervalSince1970
        value["enabled"] = enabled
        value["busy"] = (value["busyUntil"] as? Double ?? 0) > Date().timeIntervalSince1970
        if enabled {
            for field in ["floor", "zone"] {
                let options = session?[field + "s"] as? [String] ?? []
                if !options.contains(value[field] as? String ?? "") { value[field] = options.first; value.removeValue(forKey: "requestId") }
            }
        } else { value["status"] = demo ? "체험은 앱에서 기록해 주세요" : "앱을 열어 로그인 갱신" }
        return value
    }
    /// Direct tap on a floor/zone chip; the value must be one of the owner's configured options.
    static func select(_ field: String, _ selected: String) throws {
        guard field == "floor" || field == "zone" else { throw Failure.invalid }
        try locked {
            var value = try display()
            guard value["enabled"] as? Bool == true, value["busy"] as? Bool != true,
                  let options = try read()?[field + "s"] as? [String], options.contains(selected) else { return }
            value[field] = selected
            value["requestId"] = UUID().uuidString
            value["status"] = "등록을 누르면 서버에 저장돼요"
            try write(value)
        }
    }
    /// Options to render as chips; empty without a live widget session. Call while holding the lock.
    static func options(_ field: String) -> [String] {
        (try? read()?[field + "s"] as? [String]) ?? []
    }
    static func cycle(_ field: String) throws {
        try locked {
            var value = try display()
            guard value["enabled"] as? Bool == true, value["busy"] as? Bool != true,
                  let options = try read()?[field + "s"] as? [String], !options.isEmpty else { return }
            let index = options.firstIndex(of: value[field] as? String ?? "") ?? 0
            value[field] = options[(index + 1) % options.count]
            value["requestId"] = UUID().uuidString
            value["status"] = "등록을 누르면 서버에 저장돼요"
            try write(value)
        }
    }
}

// All callers hold WidgetSession.locked; older app reads cannot overwrite widget writes.
enum WidgetSnapshots {
    static func timestamp(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: text) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: text)
    }
    static func merge(_ incoming: [String: Any]) throws {
        if let auth = try WidgetSession.read() {
            guard incoming["isDemo"] as? Bool != true,
                  ["userId", "vehicleId"].allSatisfy({ incoming[$0] as? String == auth[$0] as? String }) else { return }
        }
        guard let defaults = UserDefaults(suiteName: WidgetSession.group) else { throw WidgetSession.Failure.storage }
        let old = defaults.dictionary(forKey: "parkingSnapshot") ?? [:]
        let same = ["userId", "vehicleId"].allSatisfy { (incoming[$0] as? String)?.isEmpty == false && incoming[$0] as? String == old[$0] as? String }
        if same, let previous = timestamp(old["updatedAt"]), previous > (timestamp(incoming["updatedAt"]) ?? .distantPast) { return }
        defaults.set(incoming, forKey: "parkingSnapshot")
    }
}
