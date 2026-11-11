import 'package:carcar/app/theme.dart';
import 'package:carcar/core/app_controller.dart';
import 'floor_icon_sync_test.dart' show FloorRepository;
import 'package:carcar/core/native_bridge.dart';
import 'package:carcar/features/launcher_icon_setting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    iconTest('$platform reads native launcher state', () async {
      debugDefaultTargetPlatformOverride = platform;
      expect((await NativeBridge.launcherIconState()).supported, isTrue);
      expect(calls.single.method, 'launcherIconState');
    });
  }
  iconTest('desktop does not invoke native icon methods', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect((await NativeBridge.launcherIconState()).supported, isFalse);
    expect(calls, isEmpty);
  });
  iconTest(
    'all supported floors map and unsupported floors restore default',
    () async {
      for (final floor in [
        ...List.generate(5, (i) => 'F${i + 1}'),
        ...List.generate(6, (i) => 'B${i + 1}'),
      ]) {
        expect(
          NativeBridge.iconForFloor(floor),
          'floor_${floor.toLowerCase()}',
        );
      }
      for (final floor in [null, '', 'F6', 'B7', 'B0', '지하 2층']) {
        expect(NativeBridge.iconForFloor(floor), isNull);
      }
    },
  );
  iconTest('legacy color IDs are read-only', () async {
    for (final id in NativeBridge.launcherIconIds) {
      await expectLater(NativeBridge.setLauncherIcon(id), throwsArgumentError);
    }
    expect(calls, isEmpty);
  });

  iconTest(
    'unsupported native response never confirms an icon change',
    () async {
      supported = false;
      expect((await NativeBridge.launcherIconState()).supported, isFalse);
      await expectLater(
        NativeBridge.setLauncherIcon('floor_b1'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'icon_change_unconfirmed',
          ),
        ),
      );
    },
  );

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
      NativeBridge.setLauncherIcon('floor_b2'),
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
      NativeBridge.setLauncherIcon('floor_b2'),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'icon_change_unconfirmed',
        ),
      ),
    );
  });

  Widget screen(AppController controller, {double scale = 1}) => MaterialApp(
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
          child: LauncherIconSetting(controller: controller),
        ),
      ),
    ),
  );
  testWidgets(
    'Android floor details are informative, with no switch and no icon write',
    (tester) async {
      final controller = AppController(FloorRepository());
      addTearDown(controller.dispose);
      await tester.pumpWidget(screen(controller));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('저장한 층수에 맞춰 자동으로 바뀌어요.'), findsOneWidget);
      await tester.tap(find.text('주차 층수 앱 아이콘'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.textContaining('F1~F5'), findsOneWidget);
      expect(find.textContaining('iPhone'), findsNothing);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'setLauncherIcon'), isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  iconWidgetTest('iPhone offers one switch, off by default, and no dialog', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController(
      FloorRepository(),
      preferences: await SharedPreferences.getInstance(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(screen(controller));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.text('주차 층수 앱 아이콘'), findsOneWidget);
    expect(find.text('켜면 층이 바뀔 때마다 iPhone이 확인 창을 띄워요.'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(calls.where((c) => c.method == 'setLauncherIcon'), isEmpty);
  });
  iconWidgetTest(
    'iPhone switch applies the confirmed floor and off restores the default',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final controller = AppController(
        FloorRepository(),
        preferences: preferences,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.pumpWidget(screen(controller));
      await tester.pumpAndSettle();
      List<Object?> written() => [
        for (final call in calls)
          if (call.method == 'setLauncherIcon')
            (call.arguments as Map)['iconId'],
      ];
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(preferences.getBool(AppController.floorIconPreferenceKey), isTrue);
      expect(written(), ['floor_b1']);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(
        preferences.getBool(AppController.floorIconPreferenceKey),
        isFalse,
      );
      expect(written(), ['floor_b1', null]);
      expect(current, isNull);
    },
  );
  iconWidgetTest('a switch that cannot be saved says so and stays off', (
    tester,
  ) async {
    // No device storage: the choice cannot be kept.
    final controller = AppController(FloorRepository());
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('기기 설정을 저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(calls.where((c) => c.method == 'setLauncherIcon'), isEmpty);
  });
  iconWidgetTest('a failed icon change is explained as an icon problem', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController(
      FloorRepository(),
      preferences: await SharedPreferences.getInstance(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    failChange = true;
    await tester.pumpWidget(screen(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    // Nothing was just parked and this already is the settings screen.
    expect(find.text('아이콘을 바꾸지 못했어요.'), findsOneWidget);
    expect(find.textContaining('주차 기록'), findsNothing);
    expect(find.textContaining('설정에서'), findsNothing);
    expect(find.text('아이콘 다시 맞추기'), findsOneWidget);
  });
  iconWidgetTest('warning exposes retry and native failure stays visible', (
    tester,
  ) async {
    final controller = AppController(FloorRepository());
    addTearDown(controller.dispose);
    controller.iconWarning = '아이콘을 확인해 주세요.';
    current = 'floor_b2';
    failChange = true;
    await tester.pumpWidget(screen(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('아이콘 다시 맞추기'));
    await tester.pumpAndSettle();
    expect(controller.iconWarning, isNotNull);
    expect(current, 'floor_b2');
    expect(calls.where((c) => c.method == 'setLauncherIcon'), hasLength(1));
  });
  testWidgets(
    'floor row fits narrow width and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = AppController(FloorRepository());
      addTearDown(controller.dispose);
      await tester.pumpWidget(screen(controller, scale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        expect(find.byType(SwitchListTile), findsOneWidget);
      } else {
        await tester.tap(find.text('주차 층수 앱 아이콘'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}
