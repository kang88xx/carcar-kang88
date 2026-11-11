import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'native_bridge.dart';
import 'repository.dart';

typedef NotificationRpc =
    Future<dynamic> Function(String name, Map<String, dynamic> parameters);

class DeviceNotificationSettings {
  const DeviceNotificationSettings({
    this.pushEnabled = false,
    this.liveEnabled = false,
    this.notifyOwn = false,
    this.quietStart,
    this.quietEnd,
    this.timezone = 'Asia/Seoul',
    this.preferredLiveMinutes = 120,
  });

  final bool pushEnabled, liveEnabled, notifyOwn;
  final String? quietStart, quietEnd;
  final String timezone;
  final int preferredLiveMinutes;
  bool get quietEnabled => quietStart != null;

  static String? _time(Object? value) {
    if (value == null) return null;
    if (value is! String ||
        !RegExp(
          r'^(?:[01]\d|2[0-3]):[0-5]\d(?::00(?:\.0+)?)?$',
        ).hasMatch(value)) {
      throw const AppException('서버의 알림 시간을 확인하지 못했어요. 다시 불러와 주세요.');
    }
    return value.substring(0, 5);
  }

  factory DeviceNotificationSettings.fromJson(Map<String, dynamic> value) {
    if (value['push_enabled'] is! bool ||
        value['live_enabled'] is! bool ||
        value['notify_own'] is! bool ||
        value['timezone'] is! String ||
        value['preferred_live_minutes'] is! int) {
      throw const AppException('서버의 기기 설정을 확인하지 못했어요. 다시 불러와 주세요.');
    }
    final settings = DeviceNotificationSettings(
      pushEnabled: value['push_enabled'] as bool,
      liveEnabled: value['live_enabled'] as bool,
      notifyOwn: value['notify_own'] as bool,
      quietStart: _time(value['quiet_start']),
      quietEnd: _time(value['quiet_end']),
      timezone: value['timezone'] as String,
      preferredLiveMinutes: value['preferred_live_minutes'] as int,
    );
    settings.validate();
    return settings;
  }

  void validate() {
    if (![60, 120, 240, 480].contains(preferredLiveMinutes)) {
      throw const AppException('차량 찾기 시간은 1·2·4·8시간 중 선택해 주세요.');
    }
    if ((quietStart == null) != (quietEnd == null) ||
        (quietStart != null && quietStart == quietEnd)) {
      throw const AppException('알림을 쉬는 시작·종료 시간을 서로 다르게 입력해 주세요.');
    }
    if (quietStart != null &&
        (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(quietStart!) ||
            !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(quietEnd!))) {
      throw const AppException('시간을 00:00부터 23:59 사이로 입력해 주세요.');
    }
    if (timezone.length > 100 ||
        !RegExp(r'^[A-Za-z_+-]+(?:/[A-Za-z0-9_+.-]+)*$').hasMatch(timezone)) {
      throw const AppException('시간대 이름을 확인해 주세요. 예: Asia/Seoul');
    }
  }

  DeviceNotificationSettings copyWith({
    bool? pushEnabled,
    bool? liveEnabled,
    bool? notifyOwn,
    String? quietStart,
    String? quietEnd,
    bool clearQuietHours = false,
    String? timezone,
    int? preferredLiveMinutes,
  }) => DeviceNotificationSettings(
    pushEnabled: pushEnabled ?? this.pushEnabled,
    liveEnabled: liveEnabled ?? this.liveEnabled,
    notifyOwn: notifyOwn ?? this.notifyOwn,
    quietStart: clearQuietHours ? null : quietStart ?? this.quietStart,
    quietEnd: clearQuietHours ? null : quietEnd ?? this.quietEnd,
    timezone: timezone ?? this.timezone,
    preferredLiveMinutes: preferredLiveMinutes ?? this.preferredLiveMinutes,
  );

  Map<String, dynamic> parameters(String installationId, String platform) => {
    'p_installation_id': installationId,
    'p_platform': platform,
    'p_push_enabled': pushEnabled,
    'p_live_enabled': liveEnabled,
    'p_notify_own': notifyOwn,
    'p_quiet_start': quietStart,
    'p_quiet_end': quietEnd,
    'p_timezone': timezone,
    'p_preferred_live_minutes': preferredLiveMinutes,
  };
}

class NativePushStatus {
  const NativePushStatus({
    required this.supported,
    required this.configured,
    required this.granted,
    required this.enabled,
    required this.permission,
  });
  final bool supported, configured, granted, enabled;
  final String permission;

  factory NativePushStatus.fromJson(Map<String, dynamic> value) {
    if (value['supported'] is! bool ||
        value['configured'] is! bool ||
        value['granted'] is! bool ||
        value['enabled'] is! bool ||
        value['permission'] is! String) {
      throw const AppException('기기의 알림 권한을 확인하지 못했어요. 다시 시도해 주세요.');
    }
    return NativePushStatus(
      supported: value['supported'] as bool,
      configured: value['configured'] as bool,
      granted: value['granted'] as bool,
      enabled: value['enabled'] as bool,
      permission: value['permission'] as String,
    );
  }

  NativePushStatus withEnabled(bool value) => NativePushStatus(
    supported: supported,
    configured: configured,
    granted: granted,
    enabled: value,
    permission: permission,
  );
}

abstract class NotificationNativeAdapter {
  Future<Map<String, dynamic>> pushStatus();
  Future<Map<String, dynamic>> registerPush({required bool requestPermission});
  Future<void> disablePush();
}

class PlatformNotificationAdapter implements NotificationNativeAdapter {
  const PlatformNotificationAdapter();
  @override
  Future<Map<String, dynamic>> pushStatus() => NativeBridge.pushStatus();
  @override
  Future<Map<String, dynamic>> registerPush({
    required bool requestPermission,
  }) => NativeBridge.registerPush(requestPermission: requestPermission);
  @override
  Future<void> disablePush() => NativeBridge.disablePush();
}

class DeviceNotificationController extends ChangeNotifier {
  DeviceNotificationController({
    required this.client,
    required this.preferences,
    NotificationNativeAdapter? native,
    NotificationRpc? rpc,
    String? platform,
  }) : native = native ?? const PlatformNotificationAdapter(),
       _rpc = rpc ?? ((name, params) => client.rpc(name, params: params)),
       userId = client.auth.currentUser!.id,
       platform =
           platform ??
           (kIsWeb
               ? null
               : switch (defaultTargetPlatform) {
                   TargetPlatform.iOS => 'ios',
                   TargetPlatform.android => 'android',
                   _ => null,
                 });

  static const installationPreferenceKey = 'carcar.device.installation_id';
  static const _timeout = Duration(seconds: 25);
  final SupabaseClient client;
  final SharedPreferences preferences;
  final NotificationNativeAdapter native;
  final NotificationRpc _rpc;
  final String userId;
  final String? platform;
  DeviceNotificationSettings settings = const DeviceNotificationSettings();
  NativePushStatus? pushStatus;
  bool loading = false, saving = false, initialized = false;
  bool deliveryAvailable = false;
  String? error, warning;
  bool _disposed = false;
  bool _registrationConfirmed = false;
  int _generation = 0;
  String? _installationId;

  bool get supported => platform == 'ios' || platform == 'android';
  bool get busy => loading || saving;
  bool get canReceive =>
      settings.pushEnabled &&
      deliveryAvailable &&
      _registrationConfirmed &&
      pushStatus?.granted == true &&
      pushStatus?.enabled == true;

  String _message(Object failure) {
    if (failure is PlatformException &&
        [
          'push_permission_required',
          'push_permission_denied',
        ].contains(failure.code)) {
      return '알림 권한이 꺼져 있어요. 기기 설정에서 차자리 알림을 허용해 주세요.';
    }
    if (failure is PlatformException &&
        [
          'push_unavailable',
          'push_not_configured',
          'unsupported',
        ].contains(failure.code)) {
      return '이 기기의 알림 서비스가 아직 준비되지 않았어요.';
    }
    return friendlyError(failure);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation) =>
      !_disposed &&
      generation == _generation &&
      client.auth.currentUser?.id == userId;

  void _requireCurrent(int generation) {
    if (!_current(generation)) {
      throw const AppException('로그인 상태가 변경되었어요. 현재 계정에서 다시 시도해 주세요.');
    }
  }

  Future<String> _installation(int generation) async {
    if (_installationId != null) return _installationId!;
    final stored = preferences.getString(installationPreferenceKey);
    if (stored != null &&
        RegExp(
          r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
        ).hasMatch(stored)) {
      return _installationId = stored;
    }
    final id = const Uuid().v4();
    if (!await preferences.setString(installationPreferenceKey, id)) {
      throw const AppException('기기 설정을 저장하지 못했어요. 저장 공간을 확인해 주세요.');
    }
    _requireCurrent(generation);
    return _installationId = id;
  }

  DeviceNotificationSettings _decode(Object? raw, String id) {
    if (raw is! Map ||
        raw['installation_id'] != id ||
        (raw['user_id'] != null && raw['user_id'] != userId)) {
      throw const AppException('현재 계정의 기기 설정을 확인하지 못했어요. 다시 불러와 주세요.');
    }
    final parsed = DeviceNotificationSettings.fromJson(
      Map<String, dynamic>.from(raw),
    );
    deliveryAvailable = raw['delivery_available'] == true;
    return parsed;
  }

  Future<NativePushStatus> _status(int generation) async {
    final value = NativePushStatus.fromJson(
      await native.pushStatus().timeout(_timeout),
    );
    _requireCurrent(generation);
    pushStatus = value;
    return value;
  }

  Future<Map<String, dynamic>> _registration(
    int generation, {
    required bool requestPermission,
  }) async {
    final registration = await native
        .registerPush(requestPermission: requestPermission)
        .timeout(_timeout);
    _requireCurrent(generation);
    final provider = registration['provider'];
    final token = registration['token'];
    final environment = registration['environment'];
    if ((platform == 'ios' && provider != 'apns') ||
        (platform == 'android' && provider != 'fcm') ||
        !['sandbox', 'production'].contains(environment) ||
        (provider == 'fcm' && environment != 'production') ||
        token is! String ||
        !(provider == 'apns'
            ? RegExp(r'^[0-9a-fA-F]{64,200}$').hasMatch(token)
            : RegExp(r'^[A-Za-z0-9:_-]{32,4096}$').hasMatch(token))) {
      throw const AppException('알림 기기 등록을 확인하지 못했어요. 다시 시도해 주세요.');
    }
    return {
      'p_push_provider': provider,
      'p_push_token': token,
      'p_push_environment': environment,
    };
  }

  Future<void> initialize() => refresh();

  /// Never prompts for permission. An opted-in device refreshes its token only
  /// after confirming that OS permission is already granted.
  Future<void> refresh() async {
    if (_disposed || busy || !supported) return;
    final generation = ++_generation;
    loading = true;
    error = null;
    warning = null;
    _notify();
    try {
      _requireCurrent(generation);
      final id = await _installation(generation);
      _requireCurrent(generation);
      final raw = await _rpc('get_my_device_settings', {
        'p_installation_id': id,
      }).timeout(_timeout);
      _requireCurrent(generation);
      settings = _decode(raw, id);
      initialized = true;
      _registrationConfirmed = false;
      final status = await _status(generation);
      if (settings.pushEnabled) {
        if (!deliveryAvailable) {
          warning = '가족 알림 서비스가 준비 중이에요. 준비되면 다시 연결할 수 있어요.';
        } else if (!status.supported || !status.configured) {
          warning = '이 기기의 알림 서비스가 준비되지 않았어요. 가족 알림을 받을 수 없어요.';
        } else if (!status.granted) {
          warning = '기기 설정에서 차자리 알림이 꺼져 있어요. 허용한 뒤 앱을 다시 열어 주세요.';
        } else {
          final registration = await _registration(
            generation,
            requestPermission: false,
          );
          final saved = await _rpc('save_device_settings', {
            ...settings.parameters(id, platform!),
            ...registration,
          }).timeout(_timeout);
          _requireCurrent(generation);
          settings = _decode(saved, id);
          await _status(generation);
          _registrationConfirmed = settings.pushEnabled;
        }
      } else if (status.enabled) {
        await native.disablePush().timeout(_timeout);
        _requireCurrent(generation);
        pushStatus = status.withEnabled(false);
      }
    } on Object catch (failure) {
      if (_current(generation)) error = _message(failure);
    } finally {
      if (_current(generation)) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> setPushEnabled(bool enabled) =>
      save(settings.copyWith(pushEnabled: enabled));

  /// [quiet] is for a copy the user is not waiting on: the save still runs
  /// one at a time, but a failed attempt leaves no error on the settings.
  Future<void> save(
    DeviceNotificationSettings next, {
    bool quiet = false,
  }) async {
    if (!supported || !initialized) {
      throw const AppException('휴대폰 앱에서 기기 설정을 먼저 불러와 주세요.');
    }
    if (busy) throw const AppException('기기 설정을 처리 중이에요. 잠시만 기다려 주세요.');
    next.validate();
    if (next.pushEnabled && !settings.pushEnabled && !deliveryAvailable) {
      throw const AppException('가족 알림 서비스가 준비 중이에요. 준비되면 이 기기에서 켤 수 있어요.');
    }
    final generation = ++_generation;
    _requireCurrent(generation);
    final previous = settings;
    saving = true;
    error = null;
    warning = null;
    var registered = false;
    var committed = false;
    _notify();
    try {
      final id = await _installation(generation);
      _requireCurrent(generation);
      Map<String, dynamic> registration = {};
      // Existing opt-in needs no new token when editing independent settings,
      // including while delivery is temporarily unavailable on the server.
      if (next.pushEnabled && !previous.pushEnabled) {
        final status = await _status(generation);
        if (!status.supported || !status.configured) {
          throw const AppException('이 기기의 알림 서비스가 아직 준비되지 않았어요.');
        }
        registered = true;
        registration = await _registration(generation, requestPermission: true);
      }
      final saved = await _rpc('save_device_settings', {
        ...next.parameters(id, platform!),
        ...registration,
      }).timeout(_timeout);
      _requireCurrent(generation);
      settings = _decode(saved, id);
      committed = true;
      if (!settings.pushEnabled &&
          (previous.pushEnabled || pushStatus?.enabled == true)) {
        _registrationConfirmed = false;
        await native.disablePush().timeout(_timeout);
        _requireCurrent(generation);
        if (pushStatus != null) pushStatus = pushStatus!.withEnabled(false);
      } else if (registered) {
        await _status(generation);
        _registrationConfirmed = settings.pushEnabled;
      }
    } on Object catch (failure) {
      if (_current(generation)) {
        error = committed
            ? '서버 설정은 저장했지만 기기 알림 정리를 확인하지 못했어요. 다시 시도해 주세요.'
            : quiet
            ? null
            : _message(failure);
        if (registered && !committed && !previous.pushEnabled) {
          try {
            await native.disablePush().timeout(_timeout);
            _requireCurrent(generation);
            if (pushStatus != null) pushStatus = pushStatus!.withEnabled(false);
          } on Object {
            if (_current(generation)) {
              warning = '기기 알림 정리를 확인하지 못했어요. 설정을 다시 불러와 주세요.';
            }
          }
        }
      }
      rethrow;
    } finally {
      if (_current(generation)) {
        saving = false;
        _notify();
      }
    }
  }

  /// Call before auth sign-out. Local delivery is disabled even when remote
  /// revocation fails; callers may continue local logout and show the warning.
  Future<void> unregisterForLogout() async {
    if (!supported) return;
    final operationWasPending = busy;
    final generation = ++_generation;
    _requireCurrent(generation);
    loading = false;
    saving = true;
    error = null;
    var serverRevoked = false;
    var localDisabled = false;
    _notify();
    try {
      if (operationWasPending) {
        // An older RPC may still commit; local delivery must stop regardless.
        // Report remote revocation as unconfirmed rather than racing that RPC.
        throw const AppException('진행 중인 기기 설정이 있어요.');
      }
      final id = await _installation(generation);
      _requireCurrent(generation);
      await _rpc('unregister_push_device', {
        'p_installation_id': id,
      }).timeout(_timeout);
      _requireCurrent(generation);
      settings = settings.copyWith(pushEnabled: false);
      serverRevoked = true;
    } on Object {
      // Only fixed diagnostics below reach the UI, never upstream token data.
    } finally {
      if (_current(generation)) {
        _registrationConfirmed = false;
        try {
          await native.disablePush().timeout(_timeout);
          _requireCurrent(generation);
          localDisabled = true;
          if (pushStatus != null) pushStatus = pushStatus!.withEnabled(false);
        } on Object {
          // Native implementations close the local gate before OS cleanup;
          // an error still means completion could not be confirmed.
        }
      }
      if (_current(generation)) {
        if (!serverRevoked) {
          error = localDisabled
              ? '기기 알림은 껐지만 서버 연결 해제를 확인하지 못했어요. 연결된 상태에서 다시 로그인해 알림을 해제해 주세요.'
              : '서버와 기기 알림 연결 해제를 확인하지 못했어요. 기기 설정에서 차자리 알림을 끄고, 연결된 상태에서 다시 로그인해 알림을 해제해 주세요.';
        } else if (!localDisabled) {
          error = '서버 알림은 해제했지만 기기 알림 정리를 확인하지 못했어요. 기기 설정에서 차자리 알림을 확인해 주세요.';
        }
        saving = false;
        _notify();
      }
    }
    _requireCurrent(generation);
    if (error != null) throw AppException(error!);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
