import 'dart:async';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/native_bridge.dart';
import 'package:carcar/core/repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'session_test.dart' show TestAuth, TestClient, SessionRepository;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'old repository cannot register or join after account changes',
    () async {
      final auth = TestAuth()..signInAs('A');
      final repository = SupabaseParkingRepository(TestClient(auth));
      auth.signInAs('B');
      await expectLater(
        repository.createVehicle('집', '12가3456', '차', '이름'),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        repository.join('a' * 48),
        throwsA(isA<AppException>()),
      );
      auth.dispose();
    },
  );
  test(
    'disposed controller blocks registration and invitation before repository calls',
    () async {
      final controller = AppController(SessionRepository('A'));
      controller.dispose();
      await expectLater(
        controller.createVehicle('집', '12가3456', '차', '이름'),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        controller.join('a' * 48),
        throwsA(isA<AppException>()),
      );
    },
  );
  test(
    'pending old icon completes before logout reset and new account icon',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final gate = Completer<void>();
      final entered = Completer<void>();
      String? icon;
      final writes = <String?>[];
      const channel = MethodChannel('carcar/native');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'setLauncherIcon') {
              final target = (call.arguments as Map)['iconId'] as String?;
              writes.add(target);
              if (target == 'floor_b1') {
                entered.complete();
                await gate.future;
              }
              icon = target;
            }
            return {'supported': true, 'iconId': icon};
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final old = NativeBridge.syncLauncherIcon('floor_b1');
      await entered.future;
      final cleanup = NativeBridge.syncLauncherIcon(null);
      final staleQueued = NativeBridge.syncLauncherIcon(
        'floor_b2',
        isCurrent: () => false,
      );
      final next = NativeBridge.syncLauncherIcon('floor_f2');
      gate.complete();
      await Future.wait([old, cleanup, staleQueued, next]);
      expect(writes, ['floor_b1', null, 'floor_f2']);
      await NativeBridge.syncLauncherIcon('floor_f2');
      expect(writes.length, 3);
      expect(icon, 'floor_f2');
    },
  );
}
