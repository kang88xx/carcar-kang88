import 'dart:async';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/models.dart';
import 'package:carcar/core/repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'controller_test.dart' show ControlledRepository;

class WidgetRepository extends ControlledRepository {
  WidgetRepository({this.account = 'owner', this.demo = false});
  final String account;
  final bool demo;
  bool expired = false;
  @override
  String get userId => account;
  @override
  bool get isDemo => demo;
  @override
  Map<String, dynamic>? widgetSession(Vehicle vehicle) => expired
      ? null
      : {
          'url': 'https://example.supabase.co',
          'publishableKey': 'sb_publishable_test',
          'accessToken': 'test-access-token',
          'expiresAt': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          'userId': userId,
          'vehicleId': vehicle.id,
          'floors': vehicle.floors,
          'zones': vehicle.zones,
        };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('carcar/native');
  late SharedPreferences preferences;
  late WidgetRepository repository;
  late AppController controller;
  late List<MethodCall> calls;
  bool rejectSecureWrite = false;
  Completer<void>? pendingSecureWrite;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    calls = [];
    rejectSecureWrite = false;
    pendingSecureWrite = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'launcherIconState') return {'supported': false};
          calls.add(call);
          if (call.method == 'updateWidgetSession') {
            if (rejectSecureWrite) throw PlatformException(code: 'locked');
            await pendingSecureWrite?.future;
          }
          return null;
        });
    repository = WidgetRepository();
    controller = AppController(repository, preferences: preferences);
    await controller.initialize();
    calls.clear();
  });
  tearDown(() {
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'quick save is opt-in and a read-only snapshot contains no credentials',
    () async {
      expect(controller.widgetQuickSaveEnabled, isFalse);
      await controller.refresh();
      expect(calls.map((c) => c.method), [
        'clearWidgetSession',
        'updateSnapshot',
      ]);
      final snapshot = calls.last.arguments as Map;
      expect(snapshot['vehicleId'], 'car');
      expect(snapshot['userId'], 'owner');
      expect(snapshot.keys, isNot(contains('accessToken')));
      expect(snapshot.keys, isNot(contains('refreshToken')));
    },
  );
  test(
    'enable stores secure session before activating the preference',
    () async {
      pendingSecureWrite = Completer<void>();
      final enable = controller.setWidgetQuickSaveEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(controller.widgetQuickSaveEnabled, isFalse);
      expect(calls.single.method, 'updateWidgetSession');
      expect(
        (calls.single.arguments as Map).containsKey('refreshToken'),
        isFalse,
      );
      pendingSecureWrite!.complete();
      await enable;
      expect(controller.widgetQuickSaveEnabled, isTrue);
      expect(calls.last.method, 'updateSnapshot');
    },
  );
  test('failed secure storage never enables quick save', () async {
    rejectSecureWrite = true;
    await expectLater(
      controller.setWidgetQuickSaveEnabled(true),
      throwsA(isA<PlatformException>()),
    );
    expect(controller.widgetQuickSaveEnabled, isFalse);
  });
  test(
    'disable erases native credentials and persists across controllers',
    () async {
      await controller.setWidgetQuickSaveEnabled(true);
      calls.clear();
      await controller.setWidgetQuickSaveEnabled(false);
      expect(controller.widgetQuickSaveEnabled, isFalse);
      expect(calls.first.method, 'clearWidgetSession');
      expect(calls.any((c) => c.method == 'updateWidgetSession'), isFalse);
      controller.dispose();
      controller = AppController(repository, preferences: preferences);
      expect(controller.widgetQuickSaveEnabled, isFalse);
    },
  );
  test('permission is scoped to the account on this device', () async {
    await controller.setWidgetQuickSaveEnabled(true);
    controller.dispose();
    controller = AppController(
      WidgetRepository(account: 'other'),
      preferences: preferences,
    );
    await controller.initialize();
    expect(controller.widgetQuickSaveEnabled, isFalse);
  });
  test('expired session cannot enable quick save', () async {
    repository.expired = true;
    await expectLater(
      controller.setWidgetQuickSaveEnabled(true),
      throwsA(isA<AppException>()),
    );
    expect(controller.widgetQuickSaveEnabled, isFalse);
    expect(calls, isEmpty);
  });
  test('expired session clears credentials during refresh', () async {
    await controller.setWidgetQuickSaveEnabled(true);
    repository.expired = true;
    calls.clear();
    await controller.refresh();
    expect(calls.map((c) => c.method), [
      'clearWidgetSession',
      'updateSnapshot',
    ]);
  });
  test('demo cannot authorize background server writes', () async {
    controller.dispose();
    controller = AppController(
      WidgetRepository(demo: true),
      preferences: preferences,
    );
    await controller.initialize();
    await expectLater(
      controller.setWidgetQuickSaveEnabled(true),
      throwsA(isA<AppException>()),
    );
    expect(controller.widgetQuickSaveEnabled, isFalse);
  });
  test(
    'revoked membership clears widget context with the protected snapshot',
    () async {
      await controller.setWidgetQuickSaveEnabled(true);
      repository.available.clear();
      calls.clear();
      await controller.refresh();
      expect(calls.map((c) => c.method), ['clearSnapshot']);
    },
  );
  test(
    'disposed controller cannot restore an old snapshot after logout',
    () async {
      await controller.setWidgetQuickSaveEnabled(true);
      pendingSecureWrite = Completer<void>();
      calls.clear();
      final refresh = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      pendingSecureWrite!.complete();
      await refresh;
      expect(calls.any((c) => c.method == 'updateSnapshot'), isFalse);
      controller = AppController(repository, preferences: preferences);
    },
  );
}
