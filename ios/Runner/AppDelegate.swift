import Flutter
import UIKit
import Vision
import WidgetKit
import ActivityKit
import UserNotifications
import AuthenticationServices
import CryptoKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let groupID = "group.com.kang88.carcar"
  private var findingTask: Task<Void, Never>?
  private let familyPush = PushNotifications()
  private var changingLauncherIcon = false
  private var appleSignInRequest: AppleSignInRequest?
  // Keep legacy names readable so an upgrade can restore or replace an old icon.
  private let launcherIcons = [
    "car_blue": "AppIconBlue", "car_black": "AppIconBlack",
    "car_white": "AppIconWhite", "car_gold": "AppIconGold",
    "car_mint": "AppIconMint", "car_purple": "AppIconPurple",
    "car_red": "AppIconRed", "car_gray": "AppIconGray",
    "floor_f1": "AppIconFloorF1", "floor_f2": "AppIconFloorF2",
    "floor_f3": "AppIconFloorF3", "floor_f4": "AppIconFloorF4",
    "floor_f5": "AppIconFloorF5",
    "floor_b1": "AppIconFloorB1", "floor_b2": "AppIconFloorB2",
    "floor_b3": "AppIconFloorB3", "floor_b4": "AppIconFloorB4",
    "floor_b5": "AppIconFloorB5", "floor_b6": "AppIconFloorB6"
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
        case "signInWithApple": self.signInWithApple(result: result)
        case "pushStatus": self.familyPush.status(result: result)
        case "registerPush": self.familyPush.register(requestPermission: args["requestPermission"] as? Bool ?? true, result: result)
        case "disablePush": self.familyPush.disable(result: result)
        case "shareText": self.shareText(args, result: result)
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

  private func shareText(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let text = args["text"] as? String,
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          text.utf16.count <= 4096 else {
      result(FlutterError(code: "invalid_share_text", message: "공유할 내용을 확인해 주세요.", details: nil)); return
    }
    guard UIApplication.shared.applicationState == .active,
          let presenter = window?.rootViewController,
          presenter.presentedViewController == nil,
          presenter.viewIfLoaded?.window != nil else { result(false); return }
    let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
    if let popover = sheet.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
      popover.permittedArrowDirections = []
    }
    // Presentation success does not mean the user sent an invitation.
    presenter.present(sheet, animated: true) { result(true) }
  }

  private func signInWithApple(result: @escaping FlutterResult) {
    guard appleSignInRequest == nil else {
      result(FlutterError(code: "apple_sign_in_busy", message: "진행 중인 Apple 로그인을 먼저 완료해 주세요.", details: nil)); return
    }
    guard UIApplication.shared.applicationState == .active,
          let anchor = window, !anchor.isHidden,
          anchor.rootViewController?.viewIfLoaded?.window != nil else {
      result(FlutterError(code: "apple_sign_in_unavailable", message: "앱으로 돌아온 뒤 Apple 로그인을 다시 시도해 주세요.", details: nil)); return
    }
    let request = AppleSignInRequest(anchor: anchor) { [weak self] value in
      self?.appleSignInRequest = nil
      result(value)
    }
    appleSignInRequest = request
    request.start()
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
      guard let iconId = value as? String, iconId.hasPrefix("floor_"), let asset = launcherIcons[iconId] else {
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

/// Holds one system authentication request and its secrets only until completion.
private final class AppleSignInRequest: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
  private let anchor: UIWindow
  private var completion: FlutterResult?
  private var controller: ASAuthorizationController?
  private var rawNonce: String?
  private var state: String?

  init(anchor: UIWindow, completion: @escaping FlutterResult) {
    self.anchor = anchor
    self.completion = completion
  }

  private static func randomValue() -> String? {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = bytes.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
    }
    guard status == errSecSuccess else { return nil }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }

  func start() {
    guard let nonce = Self.randomValue(), let requestState = Self.randomValue() else {
      finish(FlutterError(code: "apple_sign_in_unavailable", message: "Apple 로그인을 준비하지 못했어요. 다시 시도해 주세요.", details: nil)); return
    }
    rawNonce = nonce
    state = requestState
    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.requestedScopes = [.fullName, .email]
    request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    request.state = requestState
    let controller = ASAuthorizationController(authorizationRequests: [request])
    self.controller = controller
    controller.delegate = self
    controller.presentationContextProvider = self
    controller.performRequests()
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    anchor
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
    guard controller === self.controller else { return }
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
          credential.state == state, let nonce = rawNonce,
          let tokenData = credential.identityToken,
          let token = String(data: tokenData, encoding: .utf8), !token.isEmpty,
          let codeData = credential.authorizationCode,
          let code = String(data: codeData, encoding: .utf8), !code.isEmpty,
          !credential.user.isEmpty else {
      finish(FlutterError(code: "apple_credential_invalid", message: "Apple 로그인 결과를 확인하지 못했어요. 다시 시도해 주세요.", details: nil)); return
    }
    let fullName = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
    finish([
      "identityToken": token,
      "authorizationCode": code,
      "userIdentifier": credential.user,
      "rawNonce": nonce,
      "fullName": fullName as Any? ?? NSNull()
    ])
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    guard controller === self.controller else { return }
    if let error = error as? ASAuthorizationError, error.code == .canceled {
      finish(nil)
    } else {
      finish(FlutterError(code: "apple_sign_in_failed", message: "Apple 로그인을 완료하지 못했어요. 다시 시도해 주세요.", details: nil))
    }
  }

  private func finish(_ value: Any?) {
    let callback = completion
    completion = nil
    controller = nil
    rawNonce = nil
    state = nil
    callback?(value)
  }
}
