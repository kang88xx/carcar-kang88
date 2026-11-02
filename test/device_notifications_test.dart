import 'dart:async';
import 'package:carcar/app/theme.dart';
import 'package:carcar/core/device_notifications.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/features/notification_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeviceAuth implements GoTrueClient {
  String? id = 'owner';
  @override
  User? get currentUser => id == null
      ? null
      : User(
          id: id!,
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DeviceClient implements SupabaseClient {
  DeviceClient(this.deviceAuth);
  final DeviceAuth deviceAuth;
  @override
  GoTrueClient get auth => deviceAuth;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePushNative implements NotificationNativeAdapter {
  FakePushNative(this.events);
  final List<String> events;
  bool granted = false, enabled = false, configured = true;
  Object? registrationError, disableError;
  Completer<void>? pendingRegister;
  final permissionRequests = <bool>[];
  @override
  Future<Map<String, dynamic>> pushStatus() async => {
    'supported': true,
    'configured': configured,
    'granted': granted,
    'enabled': enabled,
    'permission': granted ? 'authorized' : 'notDetermined',
  };
  @override
  Future<Map<String, dynamic>> registerPush({
    required bool requestPermission,
  }) async {
    events.add('native-register');
    permissionRequests.add(requestPermission);
    if (pendingRegister != null) await pendingRegister!.future;
    if (registrationError != null) throw registrationError!;
    if (!requestPermission && !granted) {
      throw PlatformException(code: 'push_permission_required');
    }
    granted = true;
    enabled = true;
    return {'provider': 'apns', 'token': 'a' * 64, 'environment': 'production'};
  }

  @override
  Future<void> disablePush() async {
    events.add('native-disable');
    enabled = false;
    if (disableError != null) throw disableError!;
  }
}

class FakeNotificationServer {
  FakeNotificationServer(this.events);
  final List<String> events;
  DeviceNotificationSettings settings = const DeviceNotificationSettings();
  bool deliveryAvailable = true;
  Object? loadError, saveError, unregisterError;
  Completer<void>? pendingSave;
  final calls = <Map<String, dynamic>>[];
  Future<dynamic> call(String name, Map<String, dynamic> args) async {
    events.add(name);
    calls.add({'name': name, ...args});
    if (name == 'get_my_device_settings') {
      if (loadError != null) throw loadError!;
    } else if (name == 'save_device_settings') {
      if (pendingSave != null) await pendingSave!.future;
      if (saveError != null) throw saveError!;
      settings = DeviceNotificationSettings(
        pushEnabled: args['p_push_enabled'] as bool,
        liveEnabled: args['p_live_enabled'] as bool,
        notifyOwn: args['p_notify_own'] as bool,
        quietStart: args['p_quiet_start'] as String?,
        quietEnd: args['p_quiet_end'] as String?,
        timezone: args['p_timezone'] as String,
        preferredLiveMinutes: args['p_preferred_live_minutes'] as int,
      );
    } else if (name == 'unregister_push_device') {
      if (unregisterError != null) throw unregisterError!;
      settings = settings.copyWith(pushEnabled: false);
      return null;
    }
    return {
      'delivery_available': deliveryAvailable,
      'installation_id': args['p_installation_id'],
      'push_enabled': settings.pushEnabled,
      'live_enabled': settings.liveEnabled,
      'notify_own': settings.notifyOwn,
      'quiet_start': settings.quietStart,
      'quiet_end': settings.quietEnd,
      'timezone': settings.timezone,
      'preferred_live_minutes': settings.preferredLiveMinutes,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DeviceAuth auth;
  late FakePushNative native;
  late FakeNotificationServer server;
  late SharedPreferences preferences;
  late DeviceNotificationController controller;
  late List<String> events;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    events = [];
    auth = DeviceAuth();
    native = FakePushNative(events);
    server = FakeNotificationServer(events);
    controller = DeviceNotificationController(
      client: DeviceClient(auth),
      preferences: preferences,
      native: native,
      rpc: server.call,
      platform: 'ios',
    );
  });
  tearDown(() => controller.dispose());

  test(
    'new installation defaults off and never asks permission on initialization',
    () async {
      await controller.initialize();
      expect(controller.initialized, isTrue);
      expect(controller.settings.pushEnabled, isFalse);
      expect(controller.settings.liveEnabled, isFalse);
      expect(controller.settings.notifyOwn, isFalse);
      expect(native.permissionRequests, isEmpty);
      final installation = preferences.getString(
        DeviceNotificationController.installationPreferenceKey,
      );
      expect(installation, matches(RegExp(r'^[0-9a-f-]{36}$')));
      await controller.refresh();
      expect(
        preferences.getString(
          DeviceNotificationController.installationPreferenceKey,
        ),
        installation,
      );
    },
  );

  test(
    'initial load failure is explicit and blocks saving unknown settings',
    () async {
      server.loadError = const AppException('서버 연결 실패');
      await controller.initialize();
      expect(controller.error, '서버 연결 실패');
      expect(controller.initialized, isFalse);
      await expectLater(
        controller.setPushEnabled(true),
        throwsA(isA<AppException>()),
      );
      expect(native.permissionRequests, isEmpty);
    },
  );

  test(
    'unavailable delivery blocks opt-in but allows independent settings',
    () async {
      server.deliveryAvailable = false;
      await controller.initialize();
      expect(controller.deliveryAvailable, isFalse);
      await expectLater(
        controller.setPushEnabled(true),
        throwsA(isA<AppException>()),
      );
      expect(native.permissionRequests, isEmpty);
      await controller.save(controller.settings.copyWith(liveEnabled: true));
      expect(controller.settings.liveEnabled, isTrue);
      expect(controller.settings.pushEnabled, isFalse);
    },
  );

  test(
    'permission denial leaves server and visible setting disabled',
    () async {
      await controller.initialize();
      native.registrationError = PlatformException(
        code: 'push_permission_denied',
      );
      await expectLater(
        controller.setPushEnabled(true),
        throwsA(isA<PlatformException>()),
      );
      expect(controller.settings.pushEnabled, isFalse);
      expect(controller.error, contains('알림 권한'));
      expect(
        server.calls.where((call) => call['name'] == 'save_device_settings'),
        isEmpty,
      );
      expect(native.enabled, isFalse);
    },
  );

  test(
    'enable waits for server confirmation and never persists the token',
    () async {
      await controller.initialize();
      server.pendingSave = Completer<void>();
      final operation = controller.setPushEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(controller.settings.pushEnabled, isFalse);
      expect(controller.saving, isTrue);
      server.pendingSave!.complete();
      await operation;
      expect(controller.settings.pushEnabled, isTrue);
      expect(controller.canReceive, isTrue);
      expect(native.permissionRequests, [true]);
      expect(preferences.getKeys(), {
        DeviceNotificationController.installationPreferenceKey,
      });
      expect(server.calls.last['p_push_token'], 'a' * 64);
    },
  );

  test(
    'failed enable rolls back local registration and remains retryable',
    () async {
      await controller.initialize();
      server.saveError = const AppException('저장 실패');
      await expectLater(
        controller.setPushEnabled(true),
        throwsA(isA<AppException>()),
      );
      expect(controller.settings.pushEnabled, isFalse);
      expect(controller.canReceive, isFalse);
      expect(native.enabled, isFalse);
      expect(controller.error, '저장 실패');
      server.saveError = null;
      await controller.setPushEnabled(true);
      expect(controller.canReceive, isTrue);
    },
  );

  test(
    'disable commits server first then clears native registration',
    () async {
      await controller.initialize();
      await controller.setPushEnabled(true);
      events.clear();
      await controller.setPushEnabled(false);
      expect(events, ['save_device_settings', 'native-disable']);
      expect(controller.settings.pushEnabled, isFalse);
      expect(controller.canReceive, isFalse);
    },
  );

  test(
    'failed disable does not silently show off or unregister native',
    () async {
      await controller.initialize();
      await controller.setPushEnabled(true);
      events.clear();
      server.saveError = const AppException('연결 끊김');
      await expectLater(
        controller.setPushEnabled(false),
        throwsA(isA<AppException>()),
      );
      expect(controller.settings.pushEnabled, isTrue);
      expect(events, ['save_device_settings']);
    },
  );

  test(
    'native disable failure retains confirmed server off and can retry cleanup',
    () async {
      await controller.initialize();
      await controller.setPushEnabled(true);
      native.disableError = const AppException('native cleanup failure');
      await expectLater(
        controller.setPushEnabled(false),
        throwsA(isA<AppException>()),
      );
      expect(controller.settings.pushEnabled, isFalse);
      expect(controller.error, contains('서버 설정은 저장'));
      native.disableError = null;
      await controller.setPushEnabled(false);
      expect(controller.error, isNull);
      expect(controller.canReceive, isFalse);
    },
  );

  test(
    'resume refreshes opted-in token without prompting and skips denied permission',
    () async {
      server.settings = const DeviceNotificationSettings(pushEnabled: true);
      native.granted = true;
      native.enabled = true;
      await controller.initialize();
      expect(native.permissionRequests, [false]);
      expect(controller.canReceive, isTrue);
      native.granted = false;
      await controller.refresh();
      expect(native.permissionRequests, [false]);
      expect(controller.warning, contains('기기 설정'));
      expect(controller.canReceive, isFalse);
    },
  );

  test(
    'server-off state clears stale native account delivery gate on resume',
    () async {
      native.granted = true;
      native.enabled = true;
      await controller.initialize();
      expect(native.enabled, isFalse);
      expect(events, contains('native-disable'));
      expect(native.permissionRequests, isEmpty);
    },
  );

  test(
    'ready to unready keeps independent editing without registering again',
    () async {
      await controller.initialize();
      await controller.setPushEnabled(true);
      expect(controller.canReceive, isTrue);
      expect(native.permissionRequests, [true]);

      server.deliveryAvailable = false;
      await controller.refresh();
      expect(controller.settings.pushEnabled, isTrue);
      expect(controller.deliveryAvailable, isFalse);
      expect(controller.canReceive, isFalse);
      events.clear();

      await controller.save(
        controller.settings.copyWith(
          liveEnabled: true,
          quietStart: '22:00',
          quietEnd: '07:00',
          preferredLiveMinutes: 240,
        ),
      );
      expect(controller.settings.pushEnabled, isTrue);
      expect(controller.settings.liveEnabled, isTrue);
      expect(controller.settings.quietStart, '22:00');
      expect(controller.settings.preferredLiveMinutes, 240);
      expect(controller.canReceive, isFalse);
      expect(native.permissionRequests, [true]);
      expect(events, ['save_device_settings']);
      expect(server.calls.last.containsKey('p_push_token'), isFalse);
      expect(server.calls.last.containsKey('p_push_provider'), isFalse);

      await controller.setPushEnabled(false);
      expect(controller.settings.pushEnabled, isFalse);
      expect(native.enabled, isFalse);
      await expectLater(
        controller.setPushEnabled(true),
        throwsA(isA<AppException>()),
      );
      expect(native.permissionRequests, [true]);
    },
  );

  test(
    'token refresh server failure is not reported as confirmed receiving',
    () async {
      server.settings = const DeviceNotificationSettings(pushEnabled: true);
      server.saveError = const AppException('새 토큰 저장 실패');
      native.granted = true;
      native.enabled = true;
      await controller.initialize();
      expect(controller.settings.pushEnabled, isTrue);
      expect(controller.canReceive, isFalse);
      expect(controller.error, '새 토큰 저장 실패');
    },
  );

  test(
    'logout disables local delivery even when server revocation fails',
    () async {
      await controller.initialize();
      await controller.setPushEnabled(true);
      events.clear();
      server.unregisterError = const AppException('offline');
      await expectLater(
        controller.unregisterForLogout(),
        throwsA(isA<AppException>()),
      );
      expect(events, ['unregister_push_device', 'native-disable']);
      expect(controller.settings.pushEnabled, isTrue);
      expect(native.enabled, isFalse);
      expect(controller.canReceive, isFalse);
      expect(controller.error, contains('서버 연결 해제를 확인하지 못했어요'));
      expect(auth.currentUser, isNotNull);
      server.unregisterError = null;
      events.clear();
      await controller.unregisterForLogout();
      expect(events, ['unregister_push_device', 'native-disable']);
      expect(controller.settings.pushEnabled, isFalse);
    },
  );

  test(
    'logout reports native cleanup failure after confirmed remote revoke',
    () async {
      await controller.initialize();
      await controller.setPushEnabled(true);
      native.disableError = StateError('sensitive platform details');
      await expectLater(
        controller.unregisterForLogout(),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'fixed message',
            contains('기기 알림 정리'),
          ),
        ),
      );
      expect(controller.settings.pushEnabled, isFalse);
      expect(controller.error, isNot(contains('sensitive')));
    },
  );

  test(
    'logout invalidates pending save and disables local delivery without racing revoke',
    () async {
      await controller.initialize();
      server.pendingSave = Completer<void>();
      final oldSave = controller.setPushEnabled(true);
      final oldResult = expectLater(oldSave, throwsA(isA<AppException>()));
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        controller.unregisterForLogout(),
        throwsA(isA<AppException>()),
      );
      expect(native.enabled, isFalse);
      expect(events, isNot(contains('unregister_push_device')));
      server.pendingSave!.complete();
      await oldResult;
      expect(controller.settings.pushEnabled, isFalse);
      expect(controller.canReceive, isFalse);
    },
  );

  test(
    'account switch during native registration cannot save under the new user',
    () async {
      await controller.initialize();
      native.pendingRegister = Completer<void>();
      final operation = controller.setPushEnabled(true);
      final expectation = expectLater(operation, throwsA(isA<AppException>()));
      await Future<void>.delayed(Duration.zero);
      auth.id = 'other';
      native.pendingRegister!.complete();
      await expectation;
      expect(
        server.calls.where((call) => call['name'] == 'save_device_settings'),
        isEmpty,
      );
      expect(controller.settings.pushEnabled, isFalse);
    },
  );

  test(
    'late server response after account switch never overwrites visible settings',
    () async {
      await controller.initialize();
      server.pendingSave = Completer<void>();
      final operation = controller.save(
        controller.settings.copyWith(liveEnabled: true),
      );
      final expectation = expectLater(operation, throwsA(isA<AppException>()));
      await Future<void>.delayed(Duration.zero);
      auth.id = 'other';
      server.pendingSave!.complete();
      await expectation;
      expect(controller.settings.liveEnabled, isFalse);
    },
  );

  test(
    'live display and quiet hours persist independently while push is off',
    () async {
      await controller.initialize();
      await controller.save(
        controller.settings.copyWith(
          liveEnabled: true,
          preferredLiveMinutes: 480,
          quietStart: '22:00',
          quietEnd: '07:00',
          timezone: 'Asia/Seoul',
        ),
      );
      expect(controller.settings.liveEnabled, isTrue);
      expect(controller.settings.pushEnabled, isFalse);
      expect(controller.settings.quietStart, '22:00');
      expect(controller.settings.quietEnd, '07:00');
      expect(native.permissionRequests, isEmpty);
      await controller.save(
        controller.settings.copyWith(clearQuietHours: true),
      );
      expect(controller.settings.quietStart, isNull);
      expect(controller.settings.quietEnd, isNull);
    },
  );

  test('invalid quiet hours or durations never reach the server', () async {
    await controller.initialize();
    for (final next in [
      const DeviceNotificationSettings(quietStart: '22:00'),
      const DeviceNotificationSettings(quietStart: '22:00', quietEnd: '22:00'),
      const DeviceNotificationSettings(quietStart: '24:00', quietEnd: '07:00'),
      const DeviceNotificationSettings(timezone: ''),
      const DeviceNotificationSettings(preferredLiveMinutes: 90),
    ]) {
      await expectLater(controller.save(next), throwsA(isA<AppException>()));
    }
    expect(
      server.calls.where((call) => call['name'] == 'save_device_settings'),
      isEmpty,
    );
  });

  test(
    'database time format is normalized and malformed settings are rejected',
    () {
      final values = {
        'push_enabled': false,
        'live_enabled': false,
        'notify_own': false,
        'quiet_start': '22:00:00',
        'quiet_end': '07:00:00',
        'timezone': 'Asia/Seoul',
        'preferred_live_minutes': 120,
      };
      expect(DeviceNotificationSettings.fromJson(values).quietStart, '22:00');
      expect(
        () => DeviceNotificationSettings.fromJson({
          ...values,
          'quiet_end': '07:00:02',
        }),
        throwsA(isA<AppException>()),
      );
      expect(
        () => DeviceNotificationSettings.fromJson({
          ...values,
          'push_enabled': 'true',
        }),
        throwsA(isA<AppException>()),
      );
    },
  );

  testWidgets(
    'demo controls are disabled and real settings fit narrow large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget app(Widget child) => MaterialApp(
        theme: buildTheme(),
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: widget!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      );
      await tester.pumpWidget(app(const NotificationSettings(isDemo: true)));
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      await controller.initialize();
      await tester.pumpWidget(
        app(NotificationSettings(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('알림 쉬는 시간'));
      await tester.tap(find.text('알림 쉬는 시간'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('시간 저장').hitTestable(), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(controller.settings.quietEnabled, isFalse);
    },
  );

  testWidgets(
    'turning live display off stops it only after server confirmation',
    (tester) async {
      server.settings = const DeviceNotificationSettings(liveEnabled: true);
      await controller.initialize();
      server.pendingSave = Completer<void>();
      var stops = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: NotificationSettings(
                controller: controller,
                onLiveDisabled: () async {
                  stops++;
                },
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('차량 찾기 표시 사용'));
      await tester.tap(find.text('차량 찾기 표시 사용'));
      await tester.pump();
      expect(stops, 0);
      expect(controller.settings.liveEnabled, isTrue);
      server.pendingSave!.complete();
      await tester.pumpAndSettle();
      expect(controller.settings.liveEnabled, isFalse);
      expect(stops, 1);
    },
  );

  testWidgets(
    'live stop failure reports unconfirmed display while keeping server setting off',
    (tester) async {
      server.settings = const DeviceNotificationSettings(liveEnabled: true);
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: NotificationSettings(
                controller: controller,
                onLiveDisabled: () async {
                  throw StateError('private native details');
                },
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('차량 찾기 표시 사용'));
      await tester.tap(find.text('차량 찾기 표시 사용'));
      await tester.pumpAndSettle();
      expect(controller.settings.liveEnabled, isFalse);
      expect(
        find.textContaining('현재 차량 찾기 표시의 종료를 확인하지 못했어요.'),
        findsOneWidget,
      );
      expect(find.textContaining('private native details'), findsNothing);
    },
  );

  testWidgets(
    'failed server preference save never claims live display was stopped',
    (tester) async {
      server.settings = const DeviceNotificationSettings(liveEnabled: true);
      await controller.initialize();
      server.saveError = const AppException('저장 실패');
      var stops = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: NotificationSettings(
                controller: controller,
                onLiveDisabled: () async {
                  stops++;
                },
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('차량 찾기 표시 사용'));
      await tester.tap(find.text('차량 찾기 표시 사용'));
      await tester.pumpAndSettle();
      expect(controller.settings.liveEnabled, isTrue);
      expect(stops, 0);
      expect(find.text('저장 실패'), findsOneWidget);
    },
  );
}
