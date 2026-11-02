import 'package:carcar/app/theme.dart';
import 'package:carcar/core/native_bridge.dart';
import 'package:carcar/features/launcher_icon_setting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('carcar/native');
  late List<MethodCall> calls;
  String? current;
  bool supported = true;
  bool failChange = false;
  setUp(() {
    debugDefaultTargetPlatformOverride = null;
    calls = [];
    current = null;
    supported = true;
    failChange = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'setLauncherIcon') {
            if (failChange) throw PlatformException(code: 'icon_change_failed');
            current = (call.arguments as Map)['iconId'] as String?;
          }
          return {'supported': supported, 'iconId': current};
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void iconTest(String description, Future<void> Function() body) {
    test(description, () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await body();
    });
  }

  void iconWidgetTest(String description, WidgetTesterCallback body) {
    testWidgets(
      description,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  iconTest('non-iOS support query does not call a native plugin', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect((await NativeBridge.launcherIconState()).supported, isFalse);
    await expectLater(
      NativeBridge.setLauncherIcon('car_blue'),
      throwsA(isA<PlatformException>()),
    );
    expect(calls, isEmpty);
  });

  iconTest('unknown icon cannot reach the native channel', () async {
    await expectLater(
      NativeBridge.setLauncherIcon('../OtherIcon'),
      throwsArgumentError,
    );
    expect(calls, isEmpty);
  });

  iconTest(
    'native support and current icon are read without changing it',
    () async {
      current = 'car_red';
      final state = await NativeBridge.launcherIconState();
      expect(state.iconId, 'car_red');
      expect(state.supported, isTrue);
      expect(calls.map((c) => c.method), ['launcherIconState']);
    },
  );

  iconTest(
    'default restoration passes null and verifies the native result',
    () async {
      current = 'car_red';
      final state = await NativeBridge.setLauncherIcon(null);
      expect(state.iconId, isNull);
      expect((calls.single.arguments as Map).containsKey('iconId'), isTrue);
      expect((calls.single.arguments as Map)['iconId'], isNull);
    },
  );

  iconTest('native errors never become successful icon changes', () async {
    current = 'car_red';
    failChange = true;
    await expectLater(
      NativeBridge.setLauncherIcon('car_blue'),
      throwsA(isA<PlatformException>()),
    );
    expect(current, 'car_red');
  });

  iconTest('mismatched native response is not reported as applied', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return {'supported': true, 'iconId': 'car_red'};
        });
    await expectLater(
      NativeBridge.setLauncherIcon('car_blue'),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'icon_change_unconfirmed',
        ),
      ),
    );
  });

  Widget screen({String vehicleIcon = 'car_blue', double scale = 1}) =>
      MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: LauncherIconSetting(vehicleIconId: vehicleIcon),
            ),
          ),
        ),
      );

  iconWidgetTest(
    'vehicle color changes never change the launcher automatically',
    (tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.pumpWidget(screen(vehicleIcon: 'car_red'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'setLauncherIcon'), isEmpty);
      expect(find.text('기본 · 이 기기에만 적용돼요.'), findsOneWidget);
    },
  );

  iconWidgetTest('selecting and cancelling does not apply an icon', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('앱 아이콘'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '블루'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'setLauncherIcon'), isEmpty);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'setLauncherIcon'), isEmpty);
    expect(current, isNull);
  });

  iconWidgetTest('explicit apply updates only the local icon', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('앱 아이콘'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '블루'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 기기에 적용'));
    await tester.pumpAndSettle();
    expect(current, 'car_blue');
    expect(calls.where((c) => c.method == 'setLauncherIcon').length, 1);
    expect(find.text('블루 · 이 기기에만 적용돼요.'), findsOneWidget);
  });

  iconWidgetTest('failed apply keeps the confirmed previous selection', (
    tester,
  ) async {
    current = 'car_red';
    failChange = true;
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('앱 아이콘'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '블루'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 기기에 적용'));
    await tester.pumpAndSettle();
    expect(find.text('레드 · 이 기기에만 적용돼요.'), findsOneWidget);
    expect(find.text('이 기기의 앱 아이콘을 바꿨어요.'), findsNothing);
  });

  iconWidgetTest('unsupported device has no enabled picker', (tester) async {
    supported = false;
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
    expect(find.text('이 기기에서는 앱 아이콘 변경을 지원하지 않아요.'), findsOneWidget);
  });

  iconWidgetTest('picker remains usable at narrow width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(screen(scale: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('앱 아이콘'));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNWidgets(9));
    expect(tester.takeException(), isNull);
  });
}
