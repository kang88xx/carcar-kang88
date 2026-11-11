import 'dart:async';
import 'package:carcar/app/theme.dart';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/models.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/features/parking_form.dart';
import 'package:carcar/shared/components.dart';
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

/// The first request never answers, like a connection that stalls after it
/// was opened. Later requests reach the repository normally.
class StallingParkingRepository extends DemoParkingRepository {
  StallingParkingRepository(super.preferences);
  final keys = <String>[];

  @override
  Future<ParkingRecord> save(String vehicleId, ParkingDraft draft, String key) {
    keys.add(key);
    return keys.length == 1
        ? Completer<ParkingRecord>().future
        : super.save(vehicleId, draft, key);
  }
}

/// Local storage that reports itself as a signed-in account, to show the
/// wording a real family sees. It never claims a server round trip.
class SignedInParkingRepository extends DemoParkingRepository {
  SignedInParkingRepository(super.preferences);

  @override
  bool get isDemo => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppController> openForm(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    bool longValuesWithSaveFailure = false,
    bool saveFails = false,
    FakeViewPadding padding = const FakeViewPadding(top: 59, bottom: 34),
    bool stallFirstSave = false,
    bool signedIn = false,
    TargetPlatform platform = TargetPlatform.iOS,
    List<String>? customZones,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
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
    final repository = longValuesWithSaveFailure || saveFails
        ? FailingParkingRepository(preferences)
        : stallFirstSave
        ? StallingParkingRepository(preferences)
        : signedIn
        ? SignedInParkingRepository(preferences)
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
        theme: buildTheme().copyWith(platform: platform),
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

  testWidgets('parking number keeps its limit without a visible counter', (
    tester,
  ) async {
    await openForm(tester);
    final spot = find.widgetWithText(TextField, '주차 번호 (선택)');
    await tester.ensureVisible(spot);
    await tester.enterText(spot, '1' * 30);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(spot).controller!.text, '1' * 20);
    expect(find.textContaining(RegExp(r'^\d+\s*/\s*\d+$')), findsNothing);
  });

  testWidgets('sheet shows the question and the demo note, not the car name', (
    tester,
  ) async {
    final controller = await openForm(tester);
    expect(find.text('어디에 주차했나요?'), findsOneWidget);
    expect(find.text(controller.vehicle!.name), findsNothing);
    expect(find.text('체험 기록 저장'), findsOneWidget);
    expect(find.text('이 기기에만 저장돼요.'), findsOneWidget);
  });

  testWidgets('real account has no caption and saves a typed unit once', (
    tester,
  ) async {
    final controller = await openForm(tester, signedIn: true);
    expect(find.text('저장 후 가족과 위치를 공유해요.'), findsNothing);
    expect(find.text('이 기기에만 저장돼요.'), findsNothing);
    expect(find.text(controller.vehicle!.name), findsNothing);
    for (final label in ['B3', 'D']) {
      final choice = find.widgetWithText(ChoiceChip, label);
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
    }
    final spot = find.widgetWithText(TextField, '주차 번호 (선택)');
    await tester.ensureVisible(spot);
    await tester.enterText(spot, '24번');
    await tester.pumpAndSettle();
    final save = find.text('주차 기록 저장');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(ParkingForm), findsNothing);
    expect(controller.latest!.spot, '24번');
    expect(find.text('B3 · D구역 · 24번에 주차 기록을 저장했어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'iPhone opens digits for the parking number, Android keeps text',
    (tester) async {
      final spot = find.widgetWithText(TextField, '주차 번호 (선택)');
      await openForm(tester);
      expect(
        tester.widget<TextField>(spot).keyboardType,
        const TextInputType.numberWithOptions(signed: true),
      );
      await tester.pumpWidget(const SizedBox());
      await openForm(tester, platform: TargetPlatform.android);
      expect(tester.widget<TextField>(spot).keyboardType, TextInputType.text);
    },
  );

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
    // A missing floor is not a connection problem.
    expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('haptics', () {
    late List<String> felt;
    setUp(() {
      felt = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              felt.add(call.arguments as String);
            }
            return null;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    const click = 'HapticFeedbackType.selectionClick';
    const success = 'HapticFeedbackType.successNotification';
    Future<void> choose(WidgetTester tester, String label) async {
      final choice = find.widgetWithText(ChoiceChip, label);
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
    }

    testWidgets('a floor or zone chip clicks once for each change', (
      tester,
    ) async {
      await openForm(tester);
      expect(felt, isEmpty);
      await choose(tester, 'B2');
      expect(felt, [click]);
      // The same chip again changes nothing.
      await choose(tester, 'B2');
      expect(felt, [click]);
      await choose(tester, 'C');
      await choose(tester, 'B3');
      expect(felt, [click, click, click]);
    });

    testWidgets('success is felt only once the save is confirmed', (
      tester,
    ) async {
      await openForm(tester, stallFirstSave: true);
      await choose(tester, 'B3');
      await choose(tester, 'D');
      final save = find.text('체험 기록 저장');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump(const Duration(seconds: 14));
      // Sent but unanswered, then timed out: nothing claims success.
      expect(felt, [click, click]);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(ParkingForm), findsOneWidget);
      expect(felt, [click, click]);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(ParkingForm), findsNothing);
      expect(felt, [click, click, success]);
    });
  });

  testWidgets('stalled save unlocks the sheet with the chosen floor and zone', (
    tester,
  ) async {
    final controller = await openForm(tester, stallFirstSave: true);
    final repository = controller.repository as StallingParkingRepository;
    final confirmed = controller.latest?.id;
    for (final label in ['B3', 'D']) {
      final choice = find.widgetWithText(ChoiceChip, label);
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
    }
    VoidCallback? close() => tester
        .widget<RoundCloseButton>(find.byType(RoundCloseButton))
        .onPressed;
    final save = find.text('체험 기록 저장');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump(const Duration(seconds: 14));
    // Still waiting for the server: locked, and nothing claims success.
    expect(controller.saving, isTrue);
    expect(close(), isNull);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(controller.saving, isFalse);
    expect(controller.latest?.id, confirmed);
    expect(find.textContaining('저장했어요'), findsNothing);
    expect(find.byType(ParkingForm), findsOneWidget);
    expect(find.text('연결이 불안정해요. 다시 시도해 주세요.'), findsOneWidget);
    for (final label in ['B3', 'D']) {
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
            .selected,
        isTrue,
      );
    }
    expect(close(), isNotNull);
    // The same draft goes out again under the same idempotency key.
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(ParkingForm), findsNothing);
    expect(repository.keys, hasLength(2));
    expect(repository.keys[1], repository.keys[0]);
    expect(controller.latest!.floor, 'B3');
    expect(controller.latest!.zone, 'D');
    expect(tester.takeException(), isNull);
  });

  testWidgets('375x667: a save error never pushes the save button away', (
    tester,
  ) async {
    const size = Size(375, 667);
    await openForm(
      tester,
      size: size,
      padding: const FakeViewPadding(top: 20),
      saveFails: true,
    );
    for (final label in ['B2', 'C']) {
      final choice = find.widgetWithText(ChoiceChip, label);
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
    }
    final fields = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('체험 기록 저장'));
    await tester.pumpAndSettle();
    // Message and button sit below the scrolling fields, both on screen
    // without the user having to scroll for the button to press again.
    final error = find.text('연결을 확인하고 다시 시도해 주세요. 입력한 내용은 그대로 남아 있어요.');
    expect(error.hitTestable(), findsOneWidget);
    final button = find.byType(FilledButton);
    expect(
      find.descendant(of: find.byWidget(fields.widget), matching: button),
      findsNothing,
    );
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(size.height));
    expect(button.hitTestable(), findsOneWidget);
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
