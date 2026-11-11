import 'dart:io';

import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/native_bridge.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/main.dart' as app;
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Capture the unchanged app in its existing, clearly labelled demo mode.
/// scripts/store_screenshots.sh permits only its dedicated iOS Simulators.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture native demo screens for the store', (tester) async {
    expect(Platform.isIOS, isTrue);
    expect(const bool.fromEnvironment('CARCAR_STORE_SIMULATOR'), isTrue);
    // iOS does not expose the Simulator host environment to Dart. The runner
    // validates this ID against simctl before passing it to Flutter drive.
    const simulatorId = String.fromEnvironment('CARCAR_STORE_DEVICE_ID');
    expect(RegExp(r'^[0-9A-F-]{36}$').hasMatch(simulatorId), isTrue);
    expect(const String.fromEnvironment('SUPABASE_URL'), isEmpty);
    expect(const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'), isEmpty);

    void checkpoint(String label) =>
        debugPrintSynchronously('[CARCAR_STORE] $label');

    Future<void> settle() async {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 25),
      );
    }

    Future<void> capture(String name) async {
      await settle();
      expect(tester.takeException(), isNull);
      // The host captures an opaque JPEG from the same native framebuffer.
      // Keep the actual screen stable while it runs; do not resize or repaint.
      checkpoint('capture:$name');
      await Future<void>.delayed(const Duration(seconds: 4));
      await binding.takeScreenshot(name);
    }

    checkpoint('test-start');
    binding.reportData = {
      'captureSource': 'iOS Simulator native app',
      'simulatorUDID': simulatorId,
      'dataSource': 'built-in local demo',
      'physicalTestVerified': false,
      'backendTested': false,
      'authenticationTested': false,
      'nativeHomeWidgetCaptured': false,
    };
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(DemoParkingRepository.storageKey);
    // The iPhone floor icon starts off. Capture as a device that switched it
    // on, so the icon checks and the native notice watcher below still apply.
    await preferences.setBool(AppController.floorIconPreferenceKey, true);
    await app.main();
    await settle();
    await tester.ensureVisible(find.text('체험 시작하기'));
    await tester.tap(find.text('체험 시작하기'));
    await settle();
    expect(find.text('마지막 주차 위치'), findsOneWidget);
    // The existing native watcher dismisses only this app's icon notices.
    await Future<void>.delayed(const Duration(seconds: 3));
    await settle();
    expect((await NativeBridge.launcherIconState()).iconId, 'floor_b2');

    checkpoint('video-start');
    await Future<void>.delayed(const Duration(seconds: 2));
    await capture('01-home');

    final record = find.text('주차 기록하기');
    await Scrollable.ensureVisible(tester.element(record), alignment: 0.5);
    await settle();
    expect(record.hitTestable(), findsOneWidget);
    await tester.tap(record);
    await settle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'B3'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'D'));
    await tester.enterText(find.widgetWithText(TextField, '주차 번호 (선택)'), '52');
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await settle();
    await capture('02-parking-entry');

    final save = find.text('체험 기록 저장');
    await tester.ensureVisible(save);
    await settle();
    await tester.tap(save);
    await settle();
    await Future<void>.delayed(const Duration(seconds: 5));
    await settle();
    expect(find.text('52번 자리'), findsOneWidget);
    expect((await NativeBridge.launcherIconState()).iconId, 'floor_b3');

    await tester.tap(find.text('우리 가족').last);
    await settle();
    expect(find.text('가족 · 예시'), findsOneWidget);
    await capture('03-family');

    await tester.tap(find.text('주차 이력').last);
    await settle();
    expect(find.text('D구역 · 52번'), findsOneWidget);
    await capture('04-history');
    checkpoint('video-stop');
    binding.reportData!['localDemoSaveVerified'] = true;
    binding.reportData!['savedPosition'] = 'B3 / D / 52';
  });
}
