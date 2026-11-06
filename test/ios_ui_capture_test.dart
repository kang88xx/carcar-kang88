import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:carcar/app/theme.dart';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/models.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/features/shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Actual Flutter rendering under iOS layout settings, not an iOS runtime test.
/// Run explicitly with --dart-define=CAPTURE_IOS_UI=true to write the PNG files.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('CAPTURE_IOS_UI');
  const outputPath = 'docs/qa/ios-fixed-header';
  final report = <Map<String, Object?>>[];

  setUpAll(() async {
    if (!capture) return;
    final text = FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([text.load(), icons.load()]);
  });

  tearDownAll(() async {
    if (!capture) return;
    await Directory(outputPath).create(recursive: true);
    await File('$outputPath/capture-results.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'rendering': 'Flutter widget test engine with TargetPlatform.iOS',
        'nativeIosRuntimeTested': false,
        'debugDisableShadows': false,
        'data': 'isolated local demo fixture; no server calls',
        'safeArea': {'top': 59, 'bottom': 34},
        'captures': report,
      }),
    );
  });

  Future<GlobalKey> showHome(
    WidgetTester tester,
    Size size,
    double textScale,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const channel = MethodChannel('carcar/native');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launcherIconState') return {'supported': false};
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    const vehicle = Vehicle(
      id: 'demo-car',
      ownerId: 'demo-me',
      name: '우리 가족 차',
      plate: '123가 4567',
      apartment: '우리집 아파트',
      latestId: 'ios-layout-record',
    );
    final record = ParkingRecord(
      id: 'ios-layout-record',
      vehicleId: vehicle.id,
      floor: 'F4',
      zone: 'B',
      spot: '12',
      note: '',
      createdBy: 'demo-me',
      createdAt: DateTime(2026, 11, 6, 11, 30),
    );
    SharedPreferences.setMockInitialValues({
      DemoParkingRepository.storageKey: jsonEncode({
        'profileName': '나',
        'vehicles': [vehicle.toJson()],
        'records': [
          record.toJson(),
          for (var i = 1; i <= 12; i++)
            {
              ...record.toJson(),
              'id': 'ios-history-$i',
              'created_at': record.createdAt
                  .subtract(Duration(hours: i))
                  .toIso8601String(),
            },
        ],
      }),
    });
    final preferences = await SharedPreferences.getInstance();
    final repository = DemoParkingRepository(preferences);
    await repository.initialize();
    final controller = AppController(repository, preferences: preferences);
    await controller.initialize();
    addTearDown(controller.dispose);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme().copyWith(platform: TargetPlatform.iOS),
          home: AppShell(
            controller: controller,
            preferences: preferences,
            onLogout: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return boundaryKey;
  }

  Future<void> saveCapture(
    WidgetTester tester,
    GlobalKey boundaryKey,
    String name,
    Size size,
    double textScale,
  ) async {
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(outputPath).create(recursive: true);
      await File('$outputPath/$name.png').writeAsBytes(
        bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      image.dispose();
    });
    report.add({
      'file': '$name.png',
      'logicalWidth': size.width,
      'logicalHeight': size.height,
      'textScale': textScale,
      'pixelRatio': 2,
      'result': 'passed',
    });
  }

  void expectOneRow(WidgetTester tester, List<String> labels, double width) {
    final rects = [
      for (final label in labels)
        tester.getRect(find.widgetWithText(ChoiceChip, label)),
    ];
    for (var i = 0; i < rects.length; i++) {
      expect(rects[i].top, closeTo(rects.first.top, 0.1));
      expect(rects[i].left, greaterThanOrEqualTo(0));
      expect(rects[i].right, lessThanOrEqualTo(width));
      if (i > 0) {
        expect(rects[i].left, greaterThanOrEqualTo(rects[i - 1].right));
      }
    }
  }

  for (final scenario in [
    (name: '393', size: const Size(393, 852), scale: 1.0),
    (name: '320', size: const Size(320, 740), scale: 1.0),
    (name: '320-large', size: const Size(320, 740), scale: 1.3),
    (name: '393-large', size: const Size(393, 852), scale: 1.3),
  ]) {
    testWidgets('capture iOS home and grouped parking form ${scenario.name}', (
      tester,
    ) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        final key = await showHome(tester, scenario.size, scenario.scale);
        expect(tester.getSize(find.byType(NavigationBar)).height, 72);
        expect(find.text('최근 주차 기록'), findsNothing);
        expect(find.text('사진 기록'), findsNothing);
        const tabs = ['주차 위치', '주차 이력', '우리 가족', '설정'];
        for (final label in tabs) {
          final navLabel = find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          );
          expect(navLabel.hitTestable(), findsOneWidget);
          final rect = tester.getRect(navLabel);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(scenario.size.width));
        }
        for (final tab in [
          (index: 0, name: 'home'),
          (index: 1, name: 'history'),
          (index: 2, name: 'family'),
          (index: 3, name: 'settings'),
        ]) {
          await tester.tap(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text(tabs[tab.index]),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            tab.index,
          );
          await saveCapture(
            tester,
            key,
            '${tab.name}-${scenario.name}',
            scenario.size,
            scenario.scale,
          );
          final header = find.byKey(const ValueKey('app-shell-header'));
          final body = find.byKey(const ValueKey('app-shell-scroll'));
          final headerRect = tester.getRect(header);
          final scrollable = tester.state<ScrollableState>(
            find.descendant(of: body, matching: find.byType(Scrollable)).first,
          );
          final beforePixels = scrollable.position.pixels;
          await tester.drag(body, const Offset(0, -280));
          await tester.pumpAndSettle();
          expect(tester.getRect(header), headerRect);
          if (scrollable.position.maxScrollExtent > 0) {
            expect(scrollable.position.pixels, greaterThan(beforePixels));
          } else {
            expect(scrollable.position.pixels, beforePixels);
          }
          expect(find.byTooltip('최신 위치 새로고침').hitTestable(), findsOneWidget);
          expect(find.byTooltip('설정 열기').hitTestable(), findsOneWidget);
          await saveCapture(
            tester,
            key,
            '${tab.name}-scrolled-${scenario.name}',
            scenario.size,
            scenario.scale,
          );
          report.last.addAll({
            'headerUnchanged': true,
            'headerControlsReachable': true,
            'scrollNeeded': scrollable.position.maxScrollExtent > 0,
            'scrollOffset': scrollable.position.pixels,
          });
        }
        final apartment = find.text('우리집 아파트');
        await tester.ensureVisible(apartment);
        await tester.pumpAndSettle();
        await tester.tap(apartment);
        await tester.pumpAndSettle();
        expect(find.text('우리 주차장 설정'), findsOneWidget);
        final apartmentSave = find.text('설정 저장');
        await tester.ensureVisible(apartmentSave);
        await tester.pumpAndSettle();
        expect(apartmentSave.hitTestable(), findsOneWidget);
        expect(find.byTooltip('닫기').hitTestable(), findsOneWidget);
        await saveCapture(
          tester,
          key,
          'apartment-${scenario.name}',
          scenario.size,
          scenario.scale,
        );
        await tester.tap(find.byTooltip('닫기'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(tabs[0]),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          0,
        );
        final record = find.text('주차 기록하기');
        await tester.ensureVisible(record);
        await tester.pumpAndSettle();
        if (record.hitTestable().evaluate().isEmpty) {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -240),
          );
          await tester.pumpAndSettle();
        }
        expect(record.hitTestable(), findsOneWidget);
        final recordParagraph = tester.renderObject<RenderParagraph>(record);
        final recordLine = recordParagraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: '주차 기록하기'.length),
        );
        expect(recordLine, isNotEmpty);
        expect(recordLine.map((box) => box.top).toSet(), hasLength(1));
        await tester.tap(record);
        await tester.pumpAndSettle();
        expect(find.text('지상'), findsOneWidget);
        expect(find.text('지하'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'B6'), findsNothing);
        expect(find.text('가족에게 남길 메모 (선택)'), findsNothing);
        expect(find.text('층수와 구역을 선택해 주세요.'), findsNothing);
        for (final labels in [
          ['F1', 'F2', 'F3', 'F4', 'F5'],
          ['B1', 'B2', 'B3', 'B4', 'B5'],
          ['A', 'B', 'C', 'D', 'E', 'F'],
          ['가', '나', '다', '라', '마', '바'],
        ]) {
          expectOneRow(tester, labels, scenario.size.width);
        }
        await saveCapture(
          tester,
          key,
          'parking-${scenario.name}',
          scenario.size,
          scenario.scale,
        );
        for (final label in ['B3', '바']) {
          final choice = find.widgetWithText(ChoiceChip, label);
          await tester.ensureVisible(choice);
          await tester.tap(choice);
          await tester.pumpAndSettle();
          expect(tester.widget<ChoiceChip>(choice).selected, isTrue);
        }
        final save = find.text('체험 기록 저장');
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        expect(save.hitTestable(), findsOneWidget);
        expect(find.byTooltip('기록 창 닫기').hitTestable(), findsOneWidget);
        await saveCapture(
          tester,
          key,
          'parking-selected-${scenario.name}',
          scenario.size,
          scenario.scale,
        );
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
        debugDisableShadows = previousShadows;
      }
    }, skip: !capture);
  }
}
