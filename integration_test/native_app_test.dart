import 'dart:io';
import 'dart:ui' as ui;

import 'package:carcar/core/models.dart';
import 'package:carcar/core/native_bridge.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Run on an isolated Android emulator or iOS Simulator, never a family phone.
/// This exercises the real platform channel and real SharedPreferences plugin.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native demo saves, persists and exposes actual OCR',
    (tester) async {
      binding.reportData = <String, dynamic>{
        'platform': Platform.operatingSystem,
      };
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(DemoParkingRepository.storageKey);
      await app.main();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('체험 시작하기'));
      await tester.tap(find.text('체험 시작하기'));
      await tester.pumpAndSettle();
      expect(find.text('마지막 주차 위치'), findsOneWidget);

      await tester.ensureVisible(find.text('주차 위치 기록하기'));
      await tester.tap(find.text('주차 위치 기록하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'B3'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'D'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, '주차 번호 (선택)'),
        '52',
      );
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.pumpAndSettle();
      final save = find.text('이 위치로 체험 기록 저장');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('52번 자리'), findsOneWidget);

      binding.reportData!['savedPosition'] = 'B3 / D / 52';
      // Opening the form may scroll the home page. Capture the confirmed
      // position from the top after the transient save message has disappeared.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('마지막 주차 위치').hitTestable(), findsOneWidget);
      expect(find.text('52번 자리').hitTestable(), findsOneWidget);
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
      }
      final screenshot = await binding.takeScreenshot('native-home');
      if (Platform.isAndroid) {
        // The Android adb runner also retrieves this device-local capture.
        await File(
          '${Directory.systemTemp.path}/carcar-native-home.png',
        ).writeAsBytes(screenshot);
      }

      if (Platform.isIOS) {
        // Read real capabilities without asking for notification permission or
        // changing the current launcher icon. UIKit's real icon change prompts
        // are deliberately outside this unattended Simulator scenario.
        final iconBefore = await NativeBridge.launcherIconState().timeout(
          const Duration(seconds: 10),
        );
        expect(iconBefore.supported, isTrue);
        final iconAfter = await NativeBridge.setLauncherIcon(
          iconBefore.iconId,
        ).timeout(const Duration(seconds: 10));
        expect(iconAfter.supported, isTrue);
        expect(iconAfter.iconId, iconBefore.iconId);
        final iconReadBack = await NativeBridge.launcherIconState().timeout(
          const Duration(seconds: 10),
        );
        expect(iconReadBack.iconId, iconBefore.iconId);

        final push = await NativeBridge.pushStatus().timeout(
          const Duration(seconds: 10),
        );
        for (final key in ['supported', 'configured', 'granted', 'enabled']) {
          expect(push[key], isA<bool>(), reason: 'pushStatus.$key');
        }
        expect(push['supported'], isTrue);
        expect(push['configured'], isTrue);
        expect(push['provider'], 'apns');
        expect(push['environment'], 'sandbox');
        expect([
          'notDetermined',
          'denied',
          'authorized',
          'provisional',
          'ephemeral',
        ], contains(push['permission']));
        expect(
          push['granted'],
          [
            'authorized',
            'provisional',
            'ephemeral',
          ].contains(push['permission']),
        );
        expect(push.containsKey('token'), isFalse);
        binding.reportData!['iosCapabilities'] = {
          'launcherIconsSupported': iconBefore.supported,
          'launcherCurrentIcon': iconBefore.iconId,
          'launcherNoOpConfirmed': true,
          'pushConfigured': push['configured'],
          'pushPermission': push['permission'],
          'pushGranted': push['granted'],
          'pushEnabled': push['enabled'],
          'pushProvider': push['provider'],
          'pushEnvironment': push['environment'],
          'pushRegistrationAttempted': false,
          'launcherActualChangeRequested': false,
        };
      }

      final fresh = DemoParkingRepository(
        await SharedPreferences.getInstance(),
      );
      await fresh.initialize();
      final vehicle = (await fresh.vehicles()).first;
      final records = await fresh.records(vehicle.id);
      expect(records.first.spot, '52');
      expect(records.first.floor, 'B3');
      expect(records.first.zone, 'D');
      binding.reportData!['freshRepositoryPersistence'] = true;

      await tester.tap(find.text('주차 이력'));
      await tester.pumpAndSettle();
      expect(find.text('D구역 · 52번'), findsOneWidget);
      binding.reportData!['historyVisible'] = true;
      await binding.takeScreenshot('native-history');

      if (Platform.isIOS) {
        final profileBefore = await fresh.profileName();
        final iconBefore = await NativeBridge.launcherIconState().timeout(
          const Duration(seconds: 10),
        );
        final pushBefore = await NativeBridge.pushStatus().timeout(
          const Duration(seconds: 10),
        );
        await tester.tap(find.text('설정'));
        await tester.pumpAndSettle();
        expect(find.text('나에게 맞게 사용하기').hitTestable(), findsOneWidget);
        await binding.takeScreenshot('native-settings-top');

        Future<void> reveal(String label) async {
          await tester.scrollUntilVisible(
            find.text(label),
            300,
            scrollable: find.byType(Scrollable).first,
            maxScrolls: 12,
          );
          await tester.pumpAndSettle();
          expect(find.text(label).hitTestable(), findsOneWidget);
        }

        await reveal('앱 아이콘');
        await tester.tap(find.text('앱 아이콘'));
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog);
        expect(find.text('홈 화면 앱 아이콘'), findsOneWidget);
        final choices = find.descendant(
          of: dialog,
          matching: find.byType(ChoiceChip),
        );
        expect(choices, findsNWidgets(9));
        expect(
          tester.widgetList<ChoiceChip>(choices).where((chip) => chip.selected),
          hasLength(1),
        );
        expect(
          tester
              .widget<FilledButton>(
                find.descendant(
                  of: dialog,
                  matching: find.byType(FilledButton),
                ),
              )
              .onPressed,
          isNull,
        );
        await binding.takeScreenshot('native-launcher-picker');
        await tester.tap(
          find.descendant(of: dialog, matching: find.text('취소')),
        );
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);

        await reveal('알림과 차량 찾기');
        final familyToggle = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, '가족 주차 알림'),
        );
        expect(familyToggle.value, isFalse);
        expect(familyToggle.onChanged, isNull);
        await binding.takeScreenshot('native-settings-notifications');

        await reveal('개인정보와 계정');
        await binding.takeScreenshot('native-settings-account');
        await reveal('내 이름');
        await tester.tap(find.text('내 이름'));
        await tester.pumpAndSettle();
        expect(dialog, findsOneWidget);
        final nameField = find.widgetWithText(TextFormField, '가족에게 표시할 이름');
        expect(
          tester.widget<TextFormField>(nameField).controller!.text,
          profileBefore,
        );
        await binding.takeScreenshot('native-profile-editor');
        await tester.tap(
          find.descendant(of: dialog, matching: find.text('취소')),
        );
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);

        final afterSettings = DemoParkingRepository(
          await SharedPreferences.getInstance(),
        );
        await afterSettings.initialize();
        expect(await afterSettings.profileName(), profileBefore);
        expect(
          (await afterSettings.vehicles())
              .map((item) => item.toJson())
              .toList(),
          (await fresh.vehicles()).map((item) => item.toJson()).toList(),
        );
        expect(
          (await afterSettings.records(
            vehicle.id,
          )).map((item) => item.toJson()).toList(),
          records.map((item) => item.toJson()).toList(),
        );
        final iconAfter = await NativeBridge.launcherIconState().timeout(
          const Duration(seconds: 10),
        );
        expect(iconAfter.iconId, iconBefore.iconId);
        final pushAfter = await NativeBridge.pushStatus().timeout(
          const Duration(seconds: 10),
        );
        for (final key in ['permission', 'granted', 'enabled']) {
          expect(
            pushAfter[key],
            pushBefore[key],
            reason: 'unchanged push.$key',
          );
        }
        await tester.tap(find.text('주차 이력'));
        await tester.pumpAndSettle();
        expect(find.text('D구역 · 52번'), findsOneWidget);
        binding.reportData!['iosSettingsInspection'] = {
          'launcherChoiceCount': 9,
          'launcherApplyDisabledWithoutChange': true,
          'launcherPickerCancelled': true,
          'demoFamilyNotificationsDisabled': true,
          'profileEditorCancelled': true,
          'profileVehiclesAndRecordsUnchanged': true,
          'launcherIconUnchanged': true,
          'notificationPermissionAndOptInUnchanged': true,
          'historyStillVisible': true,
          'authenticatedSettingsTested': false,
        };
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 900, 500),
        Paint()..color = Colors.white,
      );
      final text = TextPainter(
        text: const TextSpan(
          text: 'B2\nC24',
          style: TextStyle(
            fontSize: 150,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 850);
      text.paint(canvas, const Offset(40, 40));
      final image = await recorder.endRecording().toImage(900, 500);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final fixture = File('${Directory.systemTemp.path}/carcar-ocr-sign.png');
      await fixture.writeAsBytes(png!.buffer.asUint8List());
      final recognized = await NativeBridge.recognizeText(
        fixture.path,
      ).timeout(const Duration(seconds: 45));
      final suggestion = parseParkingText(recognized);
      expect(suggestion.floor, 'B2');
      expect(suggestion.zone, 'C');
      expect(suggestion.spot, '24');
      binding.reportData!['ocrFixtureResult'] = recognized;
      binding.reportData!['ocrFixtureParsed'] = 'B2 / C / 24';
      image.dispose();
      await fixture.delete();
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
