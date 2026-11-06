import 'dart:convert';

import 'package:carcar/app/theme.dart';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/models.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/features/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const longFloor = '지하동쪽연결주차장가족전용층';
  const longZone = '엘리베이터연결통로옆주차구역';
  const longSpot = '12345678901234567890';
  const profileName = '함께차를이용하는가족구성원이름';
  const note = '엘리베이터 연결 통로 옆에 주차했어요.';
  final recordedAt = DateTime(2026, 11, 4, 12, 30);

  setUpAll(() async {
    final font = FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf'));
    await font.load();
  });

  Future<void> showHome(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    bool longValues = false,
    double bottomInset = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    tester.view.padding = FakeViewPadding(bottom: bottomInset);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPadding);
    const channel = MethodChannel('carcar/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final stored = <String, Object>{};
    if (longValues) {
      const vehicle = Vehicle(
        id: 'demo-car',
        ownerId: 'demo-me',
        name: '우리 가족이 함께 사용하는 차',
        plate: '123가 4567',
        apartment: '우리 가족 아파트 동쪽 주차장',
        floors: [longFloor],
        zones: [longZone],
        latestId: 'layout-record',
      );
      // Apartment settings allow 1–20 characters per configured floor/zone;
      // parking numbers allow 20 and profile names allow 40 characters.
      expect(longFloor.runes.length, lessThanOrEqualTo(20));
      expect(longZone.runes.length, lessThanOrEqualTo(20));
      expect(validatedProfileName(profileName), profileName);
      expect(
        const ParkingDraft(
          floor: longFloor,
          zone: longZone,
          spot: longSpot,
          note: note,
        ).validate(vehicle),
        isNull,
      );
      final record = ParkingRecord(
        id: 'layout-record',
        vehicleId: vehicle.id,
        floor: longFloor,
        zone: longZone,
        spot: longSpot,
        note: note,
        createdBy: 'demo-me',
        createdAt: recordedAt,
      );
      stored[DemoParkingRepository.storageKey] = jsonEncode({
        'profileName': profileName,
        'vehicles': [vehicle.toJson()],
        'records': [record.toJson()],
      });
    }
    SharedPreferences.setMockInitialValues(stored);
    final preferences = await SharedPreferences.getInstance();
    final repository = DemoParkingRepository(preferences);
    await repository.initialize();
    final controller = AppController(repository);
    await controller.initialize();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme().copyWith(platform: TargetPlatform.iOS),
        home: AppShell(
          controller: controller,
          preferences: preferences,
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('home record action opens without scrolling on a normal phone', (
    tester,
  ) async {
    await showHome(tester);
    final record = find.text('주차 위치 기록하기');
    expect(record.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(record);
    await tester.pumpAndSettle();
    expect(find.text('어디에 주차했나요?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'iOS navigation counts its 34px inset once at $width / ${scale}x',
        (tester) async {
          await showHome(
            tester,
            size: Size(width, 844),
            textScale: scale,
            bottomInset: 34,
          );
          final bar = find.byType(NavigationBar);
          final rect = tester.getRect(bar);
          expect(rect.height, 72);
          expect(rect.bottom, 844 - 34 - 8);
          final centers = [
            for (final label in ['주차 위치', '주차 이력', '우리 가족', '설정'])
              tester.getCenter(
                find.descendant(of: bar, matching: find.text(label)),
              ),
          ];
          for (var i = 1; i < centers.length; i++) {
            expect(centers[i].dy, centers.first.dy);
            expect(
              centers[i].dx - centers[i - 1].dx,
              closeTo((width - 24) / 4, 0.01),
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final size in [const Size(320, 740), const Size(393, 852)]) {
    testWidgets(
      'iOS ${size.width}px navigation leaves readable gaps across all tabs at 1.3x',
      (tester) async {
        await showHome(tester, size: size, textScale: 1.3, bottomInset: 34);
        const labels = ['주차 위치', '주차 이력', '우리 가족', '설정'];
        final bar = find.byType(NavigationBar);
        for (var selected = 0; selected < labels.length; selected++) {
          await tester.tap(
            find.descendant(of: bar, matching: find.text(labels[selected])),
          );
          await tester.pumpAndSettle();
          expect(tester.widget<NavigationBar>(bar).selectedIndex, selected);
          final bounds = tester.getRect(bar);
          expect(bounds.bottom, size.height - 34 - 8);
          final slotWidth = bounds.width / labels.length;
          Rect? previous;
          for (var index = 0; index < labels.length; index++) {
            final label = labels[index];
            final finder = find.descendant(of: bar, matching: find.text(label));
            final paragraph = tester.renderObject<RenderParagraph>(finder);
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: label.length),
            );
            expect(boxes, hasLength(1), reason: '$label must stay on one line');
            final painted = boxes.single.toRect().shift(
              paragraph.localToGlobal(Offset.zero),
            );
            expect(
              painted.left,
              greaterThanOrEqualTo(bounds.left + slotWidth * index + 6),
              reason: '$label needs space before its text',
            );
            expect(
              painted.right,
              lessThanOrEqualTo(bounds.left + slotWidth * (index + 1) - 6),
              reason: '$label needs space after its text',
            );
            expect(painted.bottom, lessThanOrEqualTo(bounds.bottom - 7));
            if (previous != null) {
              expect(painted.left - previous.right, greaterThanOrEqualTo(12));
            }
            previous = painted;
            expect(finder.hitTestable(), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('home keeps widget guidance and history stays in its own tab', (
    tester,
  ) async {
    await showHome(tester, bottomInset: 34);
    for (final removed in ['사진 기록', '차량 찾기', '이력 보기', '위젯', '최근 주차 기록']) {
      expect(find.text(removed), findsNothing);
    }
    expect(find.text('마지막 주차 위치'), findsOneWidget);
    await tester.ensureVisible(find.text('추가 방법 보기'));
    await tester.pumpAndSettle();
    expect(find.text('추가 방법 보기').hitTestable(), findsOneWidget);
    expect(find.text('위젯 설정'), findsOneWidget);
    expect(find.text('가족과 함께 사용하는 모습을 둘러보세요'), findsOneWidget);
    await tester.tap(find.text('주차 이력'));
    await tester.pumpAndSettle();
    expect(find.text('쌓여 가는 주차 기록'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('C구역 · 24번'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets(
      '320px home preserves long location and metadata at ${scale}x',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await showHome(
            tester,
            size: const Size(320, 740),
            textScale: scale,
            longValues: true,
          );
          expect(tester.takeException(), isNull);
          for (final text in [longFloor, '$longZone 구역', '$longSpot번 자리']) {
            final field = find.text(text).first;
            await tester.ensureVisible(field);
            await tester.pumpAndSettle();
            expect(field.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          final metadata = '$profileName 기록 · ${formatDate(recordedAt)}';
          for (final text in [note, metadata]) {
            await tester.ensureVisible(find.text(text));
            await tester.pumpAndSettle();
            expect(find.bySemanticsLabel(text), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          final record = find.text('주차 위치 기록하기');
          await tester.ensureVisible(record);
          await tester.pumpAndSettle();
          expect(record.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
