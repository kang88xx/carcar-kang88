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
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
        theme: buildTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openParkingForm(context, controller),
              child: const Text('기록 열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('기록 열기'));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('save stays visible while parking fields scroll', (tester) async {
    await openForm(tester);
    final save = find.text('이 위치로 체험 기록 저장');
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
    expect(find.text('B3 · D구역 · 52번'), findsOneWidget);
    final note = find.widgetWithText(TextField, '가족에게 남길 메모 (선택)');
    await tester.ensureVisible(note);
    await tester.enterText(note, '입구 옆');
    await tester.pumpAndSettle();
    final save = find.text('이 위치로 체험 기록 저장');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expect(save.hitTestable(), findsOneWidget);
    expect(find.byTooltip('기록 창 닫기').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(ParkingForm), findsNothing);
    expect(controller.latest!.spot, '52');
    expect(controller.latest!.note, '입구 옆');
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
      final save = find.text('이 위치로 체험 기록 저장');
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
