import 'dart:convert';

import 'package:carcar/app/theme.dart';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/models.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/features/shell.dart';
import 'package:flutter/material.dart';
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

  Future<void> showHome(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    bool longValues = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
        theme: buildTheme(),
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
