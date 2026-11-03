import Flutter
import UIKit
import UserNotifications

/// Only explicit Flutter opt-in calls register. Tokens are returned in memory;
/// no token or account credential is written to UserDefaults or the app group.
final class PushNotifications {
  private let enabledKey = "carcar.familyPush.enabled"
  private var generation = 0
  private var pending: FlutterResult?
  private var timeout: DispatchWorkItem?

  var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
  private var configured: Bool {
    ["development", "production"].contains(Bundle.main.object(forInfoDictionaryKey: "CarcarAPNsEnvironment") as? String ?? "")
  }
  private var environment: String {
    #if targetEnvironment(simulator)
    return "sandbox"
    #else
    return Bundle.main.object(forInfoDictionaryKey: "CarcarAPNsEnvironment") as? String == "development" ? "sandbox" : "production"
    #endif
  }

  func status(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        result([
          "supported": true, "configured": self.configured,
          "permission": self.permissionName(settings.authorizationStatus),
          "granted": self.granted(settings.authorizationStatus),
          "enabled": self.enabled, "provider": "apns", "environment": self.environment
        ])
      }
    }
  }

  func register(requestPermission: Bool, result: @escaping FlutterResult) {
    guard configured else {
      result(FlutterError(code: "push_unconfigured", message: "가족 알림 연결을 확인해 주세요.", details: nil)); return
    }
    guard pending == nil else {
      result(FlutterError(code: "push_busy", message: "알림 등록을 확인하고 있어요.", details: nil)); return
    }
    generation += 1
    let attempt = generation
    pending = result
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.generation == attempt, self.pending != nil else { return }
      self.generation += 1
      self.finish(error: "push_timeout", message: "알림 서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.")
    }
    timeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: work)
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      DispatchQueue.main.async {
        guard self.generation == attempt, self.pending != nil else { return }
        if self.granted(settings.authorizationStatus) {
          UIApplication.shared.registerForRemoteNotifications()
        } else if settings.authorizationStatus == .notDetermined && requestPermission {
          center.requestAuthorization(options: [.alert, .sound]) { allowed, error in
            DispatchQueue.main.async {
              guard self.generation == attempt, self.pending != nil else { return }
              if allowed && error == nil { UIApplication.shared.registerForRemoteNotifications() }
              else { self.finish(error: "push_permission_required", message: "설정에서 차자리의 알림을 허용해 주세요.") }
            }
          }
        } else {
          self.finish(error: "push_permission_required", message: "설정에서 차자리의 알림을 허용해 주세요.")
        }
      }
    }
  }

  func registered(token: Data) {
    guard pending != nil else {
      if !enabled { UIApplication.shared.unregisterForRemoteNotifications() }
      return
    }
    guard !token.isEmpty else {
      finish(error: "push_registration_failed", message: "알림 등록을 완료하지 못했어요."); return
    }
    UserDefaults.standard.set(true, forKey: enabledKey)
    let result = pending
    pending = nil
    timeout?.cancel(); timeout = nil
    result?([
      "provider": "apns", "environment": environment,
      "token": token.map { String(format: "%02x", $0) }.joined()
    ])
  }

  func registrationFailed() {
    finish(error: "push_registration_failed", message: "알림 등록을 완료하지 못했어요. 연결 상태를 확인해 주세요.")
  }

  func disable(result: @escaping FlutterResult) {
    generation += 1
    UserDefaults.standard.set(false, forKey: enabledKey)
    finish(error: "push_cancelled", message: "알림 등록을 취소했어요.")
    UIApplication.shared.unregisterForRemoteNotifications()
    let center = UNUserNotificationCenter.current()
    let group = DispatchGroup()
    group.enter()
    center.getDeliveredNotifications { notifications in
      center.removeDeliveredNotifications(withIdentifiers: notifications.filter {
        self.isFamily($0.request.content)
      }.map { $0.request.identifier })
      group.leave()
    }
    group.enter()
    center.getPendingNotificationRequests { requests in
      center.removePendingNotificationRequests(withIdentifiers: requests.filter {
        self.isFamily($0.content)
      }.map { $0.identifier })
      group.leave()
    }
    group.notify(queue: .main) { result(nil) }
  }

  func isFamily(_ content: UNNotificationContent) -> Bool {
    content.categoryIdentifier == "carcar_family" || content.userInfo["kind"] as? String == "parking_updated"
  }

  private func granted(_ status: UNAuthorizationStatus) -> Bool {
    if status == .authorized || status == .provisional { return true }
    if #available(iOS 14.0, *), status == .ephemeral { return true }
    return false
  }

  private func permissionName(_ status: UNAuthorizationStatus) -> String {
    if #available(iOS 14.0, *), status == .ephemeral { return "ephemeral" }
    switch status {
    case .authorized: return "authorized"
    case .provisional: return "provisional"
    case .denied: return "denied"
    case .notDetermined: return "notDetermined"
    default: return "denied"
    }
  }

  private func finish(error: String, message: String) {
    let result = pending
    pending = nil
    timeout?.cancel(); timeout = nil
    result?(FlutterError(code: error, message: message, details: nil))
  }
}
