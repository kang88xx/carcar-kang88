import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LauncherIconState {
  const LauncherIconState({required this.supported, this.iconId});
  final bool supported;
  final String? iconId;
}

/// Native services keep optional widget access tokens in platform secure storage.
class NativeBridge {
  static const _channel = MethodChannel('carcar/native');
  static bool get supportsOcr =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static bool get supportsFinding => supportsOcr;
  static bool get supportsPush => supportsOcr;

  static Future<Map<String, dynamic>> pushStatus() async {
    if (!supportsPush) {
      return {
        'supported': false,
        'configured': false,
        'granted': false,
        'enabled': false,
        'permission': 'notDetermined',
        'provider': 'none',
        'environment': 'production',
      };
    }
    final status = await _channel.invokeMapMethod<String, dynamic>(
      'pushStatus',
    );
    if (status == null) {
      throw PlatformException(
        code: 'push_unavailable',
        message: '알림 설정을 확인하지 못했어요.',
      );
    }
    return status;
  }

  /// Call with false on foreground refresh; only an explicit opt-in may prompt.
  static Future<Map<String, dynamic>> registerPush({
    bool requestPermission = true,
  }) async {
    if (!supportsPush) {
      throw PlatformException(
        code: 'unsupported',
        message: '휴대폰 앱에서 가족 알림을 사용할 수 있어요.',
      );
    }
    final registration = await _channel.invokeMapMethod<String, dynamic>(
      'registerPush',
      {'requestPermission': requestPermission},
    );
    final token = registration?['token'];
    if (registration == null ||
        token is! String ||
        token.isEmpty ||
        !['apns', 'fcm'].contains(registration['provider']) ||
        !['sandbox', 'production'].contains(registration['environment'])) {
      throw PlatformException(
        code: 'push_registration_invalid',
        message: '알림 등록 결과를 확인하지 못했어요.',
      );
    }
    return registration;
  }

  static Future<void> disablePush() async {
    if (supportsPush) await _channel.invokeMethod<void>('disablePush');
  }

  static bool get supportsLauncherIcons =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static const launcherIconIds = {
    'car_blue',
    'car_black',
    'car_white',
    'car_gold',
    'car_mint',
    'car_purple',
    'car_red',
    'car_gray',
  };

  static LauncherIconState _launcherState(Map<String, dynamic>? response) {
    final icon = response?['iconId'];
    if (response?['supported'] is! bool ||
        (icon != null && !launcherIconIds.contains(icon))) {
      throw PlatformException(
        code: 'icon_state_invalid',
        message: '앱 아이콘 정보를 확인하지 못했어요. 다시 시도해 주세요.',
      );
    }
    return LauncherIconState(
      supported: response!['supported'] as bool,
      iconId: icon as String?,
    );
  }

  static Future<LauncherIconState> launcherIconState() async {
    if (!supportsLauncherIcons) {
      return const LauncherIconState(supported: false);
    }
    return _launcherState(
      await _channel.invokeMapMethod<String, dynamic>('launcherIconState'),
    );
  }

  /// Changes only this device's launcher icon after an explicit user action.
  /// A null icon restores the primary app icon; vehicle settings are untouched.
  static Future<LauncherIconState> setLauncherIcon(String? iconId) async {
    if (iconId != null && !launcherIconIds.contains(iconId)) {
      throw ArgumentError.value(iconId, 'iconId', '지원하는 아이콘을 선택해 주세요.');
    }
    if (!supportsLauncherIcons) {
      throw PlatformException(
        code: 'unsupported',
        message: 'iPhone 또는 iPad 앱에서 아이콘을 바꿀 수 있어요.',
      );
    }
    final state = _launcherState(
      await _channel.invokeMapMethod<String, dynamic>('setLauncherIcon', {
        'iconId': iconId,
      }),
    );
    if (!state.supported || state.iconId != iconId) {
      throw PlatformException(
        code: 'icon_change_unconfirmed',
        message: '아이콘 변경을 확인하지 못했어요. 다시 시도해 주세요.',
      );
    }
    return state;
  }

  static Future<String> recognizeText(String path) async {
    if (!supportsOcr) {
      throw PlatformException(
        code: 'unsupported',
        message: '휴대폰 앱에서 사진 인식을 사용할 수 있어요.',
      );
    }
    return await _channel.invokeMethod<String>('recognizeText', {
          'path': path,
        }) ??
        '';
  }

  static Future<void> updateSnapshot(Map<String, dynamic> snapshot) async {
    if (supportsOcr) {
      await _channel.invokeMethod<void>('updateSnapshot', snapshot);
    }
  }

  static Future<void> updateWidgetSession(Map<String, dynamic> session) async {
    if (supportsOcr) {
      await _channel.invokeMethod<void>('updateWidgetSession', session);
    }
  }

  static Future<void> clearWidgetSession() async {
    if (supportsOcr) await _channel.invokeMethod<void>('clearWidgetSession');
  }

  static Future<void> clearSnapshot() async {
    if (supportsOcr) await _channel.invokeMethod<void>('clearSnapshot');
  }

  static Future<bool> startFinding(
    Map<String, dynamic> snapshot,
    int minutes,
  ) async {
    if (!supportsFinding) return false;
    if (![60, 120, 240, 480].contains(minutes)) {
      throw ArgumentError.value(minutes, 'minutes', '1·2·4·8시간 중 선택해 주세요.');
    }
    return await _channel.invokeMethod<bool>('startFinding', {
          ...snapshot,
          'minutes': minutes,
        }) ??
        false;
  }

  static Future<void> stopFinding() async {
    if (supportsFinding) await _channel.invokeMethod<void>('stopFinding');
  }
}
