import 'package:carcar/core/native_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('carcar/native');
  late List<MethodCall> calls;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'registerPush') {
            return {
              'provider': 'apns',
              'environment': 'sandbox',
              'token': 'opaque-test-token',
            };
          }
          if (call.method == 'pushStatus') {
            return {
              'supported': true,
              'configured': true,
              'permission': 'denied',
              'granted': false,
              'enabled': false,
              'provider': 'apns',
              'environment': 'sandbox',
            };
          }
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('checking permission never registers or requests a prompt', () async {
    final status = await NativeBridge.pushStatus();
    expect(status['granted'], isFalse);
    expect(calls.map((c) => c.method), ['pushStatus']);
  });

  test('foreground refresh explicitly forbids permission prompt', () async {
    final registration = await NativeBridge.registerPush(
      requestPermission: false,
    );
    expect(calls.single.method, 'registerPush');
    expect(calls.single.arguments, {'requestPermission': false});
    expect(registration['provider'], 'apns');
  });

  test('explicit opt-in may request permission', () async {
    await NativeBridge.registerPush();
    expect(calls.single.arguments, {'requestPermission': true});
  });

  test(
    'disable calls native cleanup without passing account credentials',
    () async {
      await NativeBridge.disablePush();
      expect(calls.single.method, 'disablePush');
      expect(calls.single.arguments, isNull);
    },
  );

  test('denied registration is not converted to success', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'push_permission_required');
        });
    await expectLater(
      NativeBridge.registerPush(),
      throwsA(isA<PlatformException>()),
    );
  });

  test('empty token or unsupported provider fails validation', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          return {'provider': 'none', 'environment': 'production', 'token': ''};
        });
    await expectLater(
      NativeBridge.registerPush(),
      throwsA(isA<PlatformException>()),
    );
  });

  test('desktop has no native calls and cannot claim registration', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect((await NativeBridge.pushStatus())['supported'], isFalse);
    await NativeBridge.disablePush();
    await expectLater(
      NativeBridge.registerPush(),
      throwsA(isA<PlatformException>()),
    );
    expect(calls, isEmpty);
  });
}
