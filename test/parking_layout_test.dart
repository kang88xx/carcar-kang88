import 'package:carcar/app/theme.dart';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/models.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/features/parking_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FailingParkingRepository extends DemoParkingRepository {
  FailingParkingRepository(super.preferences);

  @override
  Future<ParkingRecord> save(
    String vehicleId,
    ParkingDraft draft,
    String key,
  ) async =>
      throw const AppException('연결을 확인하고 다시 시도해 주세요. 입력한 내용은 그대로 남아 있어요.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppController> openForm(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    bool longValuesWithSaveFailure = false,
    List<String>? customZones,
  }) async {
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('carcar/native'),
          (_) async => null,
        );
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = longValuesWithSaveFailure
        ? FailingParkingRepository(preferences)
        : DemoParkingRepository(preferences);
    await repository.initialize();
    if (customZones != null) {
      final vehicle = (await repository.vehicles()).single;
      await repository.updateApartment(
        vehicle.id,
        vehicle.apartment,
        vehicle.floors,
        customZones,
      );
    }
    if (longValuesWithSaveFailure) {
      final vehicle = (await repository.vehicles()).single;
      await repository.updateApartment(
        vehicle.id,
        vehicle.apartment,
        ['가나다라마바사아자차카타파하가나다라마바'],
        ['가나다라마바사아자차카타파하가나다라마바'],
      );
    }
    final controller = AppController(repository);
    await controller.initialize();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme().copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: SafeArea(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => openParkingForm(context, controller),
                child: const Text('기록 열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('기록 열기'));
    await tester.pumpAndSettle();
    return controller;
  }

  for (final width in [320.0, 393.0]) {
    testWidgets('iOS ${width}px keeps floor and zone groups in single rows', (
      tester,
    ) async {
      await openForm(tester, size: Size(width, 852), textScale: 1.3);
      expect(find.text('지상'), findsOneWidget);
      expect(find.text('지하'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'B6'), findsNothing);
      for (final row in [
        ['F1', 'F2', 'F3', 'F4', 'F5'],
        ['B1', 'B2', 'B3', 'B4', 'B5'],
        ['A', 'B', 'C', 'D', 'E', 'F'],
        ['가', '나', '다', '라', '마', '바'],
      ]) {
        final chips = row.map(
          (label) => find.widgetWithText(ChoiceChip, label),
        );
        await tester.ensureVisible(chips.first);
        await tester.pumpAndSettle();
        final bounds = chips.map(tester.getRect).toList();
        expect(
          bounds.every((rect) => (rect.top - bounds.first.top).abs() < 1),
          isTrue,
        );
        expect(bounds.first.left, greaterThanOrEqualTo(16));
        expect(bounds.last.right, lessThanOrEqualTo(width - 16));
      }
      expect(find.widgetWithText(TextField, '가족에게 남길 메모 (선택)'), findsNothing);
      expect(find.text('층수와 구역을 선택해 주세요.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final zone in ['F', '바']) {
    testWidgets('iOS form saves the $zone zone with no memo', (tester) async {
      final controller = await openForm(tester, size: const Size(393, 852));
      for (final label in ['F5', zone]) {
        final choice = find.widgetWithText(ChoiceChip, label);
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
      }
      final save = find.text('체험 기록 저장');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(ParkingForm), findsNothing);
      expect(controller.latest!.floor, 'F5');
      expect(controller.latest!.zone, zone);
      expect(controller.latest!.note, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('short custom Korean zones remain distinguishable at 320px', (
    tester,
  ) async {
    final controller = await openForm(
      tester,
      size: const Size(320, 740),
      textScale: 1.3,
      customZones: ['동문앞', '동문뒤'],
    );
    final floor = find.widgetWithText(ChoiceChip, 'F1');
    await tester.tap(floor);
    for (final label in ['동문앞', '동문뒤']) {
      final choice = find.widgetWithText(ChoiceChip, label);
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.text(label)).width, greaterThan(100));
      await tester.tap(choice);
      await tester.pumpAndSettle();
    }
    final save = find.text('체험 기록 저장');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(controller.latest!.zone, '동문뒤');
    expect(tester.takeException(), isNull);
  });

  testWidgets('save stays visible while parking fields scroll', (tester) async {
    await openForm(tester);
    final save = find.text('체험 기록 저장');
    expect(save.hitTestable(), findsOneWidget);
    final initialY = tester.getCenter(save).dy;
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.getCenter(save).dy, initialY);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('층수를 선택해 주세요.').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text and keyboard keep draft and save reachable', (
    tester,
  ) async {
    final controller = await openForm(
      tester,
      size: const Size(320, 640),
      textScale: 2,
    );
    for (final label in ['B3', 'D']) {
      final choice = find.widgetWithText(ChoiceChip, label);
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
    }
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final spot = find.widgetWithText(TextField, '주차 번호 (선택)');
    await tester.ensureVisible(spot);
    await tester.enterText(spot, '52');
    await tester.pumpAndSettle();
    expect(find.text('B3 · D구역 · 52번'), findsNothing);
    expect(find.widgetWithText(TextField, '가족에게 남길 메모 (선택)'), findsNothing);
    final save = find.text('체험 기록 저장');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expect(save.hitTestable(), findsOneWidget);
    expect(find.byTooltip('기록 창 닫기').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(ParkingForm), findsNothing);
    expect(controller.latest!.spot, '52');
    expect(controller.latest!.note, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long confirmation and save error remain usable on a small phone',
    (tester) async {
      const longValue = '가나다라마바사아자차카타파하가나다라마바';
      expect(longValue.runes.length, 20);
      await openForm(
        tester,
        size: const Size(320, 740),
        textScale: 1.3,
        longValuesWithSaveFailure: true,
      );
      final choices = find.widgetWithText(ChoiceChip, longValue);
      for (var index = 0; index < 2; index++) {
        await tester.ensureVisible(choices.at(index));
        await tester.tap(choices.at(index));
        await tester.pumpAndSettle();
      }
      final spot = find.widgetWithText(TextField, '주차 번호 (선택)');
      await tester.ensureVisible(spot);
      await tester.enterText(spot, longValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final save = find.text('체험 기록 저장');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final error = find.text('연결을 확인하고 다시 시도해 주세요. 입력한 내용은 그대로 남아 있어요.');
      await tester.ensureVisible(error);
      await tester.pumpAndSettle();
      expect(error.hitTestable(), findsOneWidget);
      expect(tester.widget<TextField>(spot).controller!.text, longValue);
      expect(find.byTooltip('기록 창 닫기').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
