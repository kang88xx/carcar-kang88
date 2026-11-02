import Flutter
import UIKit
import Vision
import WidgetKit
import ActivityKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let groupID = "group.com.kang88.carcar"
  private var findingTask: Task<Void, Never>?
  private let familyPush = PushNotifications()
  private var changingLauncherIcon = false
  private let launcherIcons = [
    "car_blue": "AppIconBlue", "car_black": "AppIconBlack",
    "car_white": "AppIconWhite", "car_gold": "AppIconGold",
    "car_mint": "AppIconMint", "car_purple": "AppIconPurple",
    "car_red": "AppIconRed", "car_gray": "AppIconGray"
  ]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    UNUserNotificationCenter.current().delegate = self
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "carcar/native", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "pushStatus": self.familyPush.status(result: result)
        case "registerPush": self.familyPush.register(requestPermission: args["requestPermission"] as? Bool ?? true, result: result)
        case "disablePush": self.familyPush.disable(result: result)
        case "launcherIconState": result(self.launcherIconState())
        case "setLauncherIcon": self.setLauncherIcon(args, result: result)
        case "recognizeText": self.recognizeText(args, result: result)
        case "updateWidgetSession", "clearWidgetSession":
          do {
            if call.method == "updateWidgetSession" { try WidgetSession.update(args) }
            else { try WidgetSession.clear() }
            if #available(iOS 14.0, *) { WidgetCenter.shared.reloadAllTimelines() }
            result(nil)
          } catch { result(FlutterError(code: "widget_session_failed", message: "위젯 보안 설정을 갱신하지 못했어요.", details: nil)) }
        case "updateSnapshot":
          var snapshot: [String: Any] = [:]
          for key in ["vehicleName", "floor", "zone", "spot", "updatedAt", "userId", "vehicleId"] {
            snapshot[key] = String((args[key] as? String ?? "").prefix(100))
          }
          snapshot["isDemo"] = args["isDemo"] as? Bool ?? false
          do { try WidgetSession.locked { try WidgetSnapshots.merge(snapshot) } }
          catch { result(FlutterError(code: "app_group_unavailable", message: "위젯 공유 설정을 확인해 주세요.", details: nil)); return }
          if #available(iOS 14.0, *) { WidgetCenter.shared.reloadAllTimelines() }
          result(nil)
        case "clearSnapshot":
          do { try WidgetSession.clear() }
          catch { result(FlutterError(code: "widget_clear_failed", message: "위젯 로그인을 지우지 못했어요. 다시 시도해 주세요.", details: nil)); return }
          UserDefaults(suiteName: self.groupID)?.removeObject(forKey: "parkingSnapshot")
          if #available(iOS 14.0, *) { WidgetCenter.shared.reloadAllTimelines() }
          self.stopFinding(result: result)
        case "startFinding": self.startFinding(args, result: result)
        case "stopFinding": self.stopFinding(result: result)
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    familyPush.registered(token: deviceToken)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    familyPush.registrationFailed()
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if familyPush.isFamily(notification.request.content) {
      guard familyPush.enabled else { completionHandler([]); return }
      if #available(iOS 14.0, *) { completionHandler([.banner, .list, .sound]) }
      else { completionHandler([.alert, .sound]) }
    } else {
      super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
    }
  }

  private func launcherIconState() -> [String: Any] {
    let app = UIApplication.shared
    let iconId = launcherIcons.first { $0.value == app.alternateIconName }?.key
    return ["supported": app.supportsAlternateIcons, "iconId": iconId as Any? ?? NSNull()]
  }

  private func setLauncherIcon(_ args: [String: Any], result: @escaping FlutterResult) {
    let app = UIApplication.shared
    guard app.supportsAlternateIcons else {
      result(FlutterError(code: "unsupported", message: "이 기기에서는 앱 아이콘을 바꿀 수 없어요.", details: nil)); return
    }
    guard args.keys.contains("iconId") else {
      result(FlutterError(code: "invalid_icon", message: "변경할 아이콘을 선택해 주세요.", details: nil)); return
    }
    let value = args["iconId"]
    var name: String?
    if let value, !(value is NSNull) {
      guard let iconId = value as? String, let asset = launcherIcons[iconId] else {
        result(FlutterError(code: "invalid_icon", message: "지원하는 아이콘을 선택해 주세요.", details: nil)); return
      }
      name = asset
    }
    guard !changingLauncherIcon, app.applicationState == .active else {
      result(FlutterError(code: "icon_change_busy", message: "앱으로 돌아온 뒤 다시 시도해 주세요.", details: nil)); return
    }
    if app.alternateIconName == name { result(launcherIconState()); return }
    changingLauncherIcon = true
    app.setAlternateIconName(name) { [weak self] error in
      DispatchQueue.main.async {
        guard let self else { return }
        self.changingLauncherIcon = false
        if error != nil {
          result(FlutterError(code: "icon_change_failed", message: "아이콘을 바꾸지 못했어요. 잠시 후 다시 시도해 주세요.", details: nil))
        } else {
          result(self.launcherIconState())
        }
      }
    }
  }

  private func recognizeText(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let path = args["path"] as? String, FileManager.default.fileExists(atPath: path) else {
      result(FlutterError(code: "image_missing", message: "사진을 다시 선택해 주세요.", details: nil)); return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = false
      do {
        let supported: [String]
        if #available(iOS 15.0, *) { supported = try request.supportedRecognitionLanguages() }
        else { supported = try VNRecognizeTextRequest.supportedRecognitionLanguages(for: .accurate, revision: request.revision) }
        request.recognitionLanguages = ["ko-KR", "en-US"].filter { supported.contains($0) }
        let handler = VNImageRequestHandler(url: URL(fileURLWithPath: path), options: [:])
        try handler.perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        DispatchQueue.main.async { result(text) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "ocr_failed", message: "글자를 읽지 못했어요. 직접 입력해 주세요.", details: nil))
        }
      }
    }
  }

  private func startFinding(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let minutes = args["minutes"] as? Int, [60, 120, 240, 480].contains(minutes) else {
      result(FlutterError(code: "invalid_duration", message: "1·2·4·8시간 중 선택해 주세요.", details: nil)); return
    }
    guard #available(iOS 17.0, *), ActivityAuthorizationInfo().areActivitiesEnabled else {
      result(false); return
    }
    findingTask?.cancel()
    findingTask = Task { @MainActor in
      for activity in Activity<ParkingAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
      if Task.isCancelled { result(false); return }
      let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
      let state = ParkingAttributes.ContentState(
        floor: String((args["floor"] as? String ?? "").prefix(20)),
        zone: String((args["zone"] as? String ?? "").prefix(20)),
        spot: String((args["spot"] as? String ?? "").prefix(20)), expiresAt: end)
      do {
        let activity = try Activity.request(
          attributes: ParkingAttributes(vehicleName: String((args["vehicleName"] as? String ?? "우리 차").prefix(40))),
          content: ActivityContent(state: state, staleDate: end), pushType: nil)
        result(true)
        do { try await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000) }
        catch { return }
        await activity.end(nil, dismissalPolicy: .immediate)
      } catch {
        result(FlutterError(code: "live_activity_failed", message: "차량 찾기 표시를 시작하지 못했어요.", details: nil))
      }
    }
  }

  private func stopFinding(result: @escaping FlutterResult) {
    findingTask?.cancel()
    findingTask = nil
    if #available(iOS 16.2, *) {
      Task { @MainActor in
        for activity in Activity<ParkingAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        result(nil)
      }
    } else { result(nil) }
  }
}
