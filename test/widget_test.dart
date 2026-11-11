import 'dart:io';
import 'package:carcar/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('carcar/native'),
          (_) async => null,
        );
  });
  Future<void> start(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      CarcarApp(preferences: await SharedPreferences.getInstance()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> demo(WidgetTester tester) async {
    await tester.ensureVisible(find.text('체험 시작하기'));
    await tester.tap(find.text('체험 시작하기'));
    await tester.pumpAndSettle();
  }

  testWidgets('settings footer shows the version from pubspec.yaml', (
    tester,
  ) async {
    final version = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
    await start(tester);
    await demo(tester);
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    expect(find.textContaining('차자리 $version\n'), findsOneWidget);
  });

  testWidgets('family alert switch opens the settings tab without scrolling', (
    tester,
  ) async {
    await start(tester, size: const Size(393, 852));
    await demo(tester);
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    final alert = find.text('가족 주차 알림');
    expect(alert.hitTestable(), findsOneWidget);
    for (final later in ['우리 주차장', '이 기기에서 보기', '개인정보와 계정']) {
      expect(
        tester.getTopLeft(alert).dy,
        lessThan(tester.getTopLeft(find.text(later)).dy),
      );
    }
  });

  testWidgets(
    'welcome explains local demo, opens home and records confirmed location',
    (tester) async {
      await start(tester);
      expect(find.textContaining('실제 가족 공유는'), findsOneWidget);
      await demo(tester);
      expect(find.text('마지막 주차 위치'), findsOneWidget);
      await tester.tap(find.text('주차 기록하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'B3'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'D'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, '주차 번호 (선택)'),
        '52',
      );
      final save = find.text('체험 기록 저장');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('D 구역'), findsOneWidget);
      expect(find.text('52번 자리'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('blank save is rejected and draft stays open', (tester) async {
    await start(tester);
    await demo(tester);
    await tester.tap(find.text('주차 기록하기'));
    await tester.pumpAndSettle();
    final save = find.text('체험 기록 저장');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('층수를 선택해 주세요.'), findsOneWidget);
    expect(find.text('어디에 주차했나요?'), findsOneWidget);
  });
  testWidgets('320px navigation and history empty search have no overflow', (
    tester,
  ) async {
    await start(tester, size: const Size(320, 740));
    await demo(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('주차 이력'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'not-a-location');
    await tester.pumpAndSettle();
    expect(find.text('검색한 기록이 없어요'), findsOneWidget);
    // Each page is titled with its tab name: once in the bar, once on top.
    await tester.tap(find.text('우리 가족'));
    await tester.pumpAndSettle();
    expect(find.text('우리 가족'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    expect(find.text('설정'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('logout returns to welcome and preserves explicit demo records', (
    tester,
  ) async {
    await start(tester);
    await demo(tester);
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('체험 종료'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('체험 종료'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('체험 종료'));
    await tester.pumpAndSettle();
    expect(find.text('체험 시작하기'), findsOneWidget);
    expect(find.text('마지막 주차 위치'), findsNothing);
  });
  testWidgets(
    'square widget guide needs no save permission and fits large text',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await start(tester, size: const Size(320, 740));
      await demo(tester);
      await tester.tap(find.text('설정'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('홈 화면 위젯'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('위젯에서 바로 기록'), findsNothing);
      expect(find.text('이전 위젯의 저장 권한'), findsNothing);
      await tester.tap(find.text('홈 화면 위젯'));
      await tester.pumpAndSettle();
      expect(find.textContaining('정사각형 위젯에서 마지막 주차 위치'), findsOneWidget);
      expect(find.text('다른 가족의 새 기록은 앱을 열면 위젯에 보여요.'), findsOneWidget);
      // Tests run as Android: its own note shows, the iPhone steps do not.
      expect(find.textContaining('Android 위젯의 실제 크기와 모양'), findsOneWidget);
      expect(find.text('iPhone'), findsNothing);
      expect(find.textContaining('별도의 위젯 저장 권한'), findsNothing);
      expect(find.text('위젯 설정으로 이동'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('large text remains usable on a narrow phone', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await start(tester, size: const Size(320, 740));
    expect(tester.takeException(), isNull);
    await demo(tester);
    expect(tester.takeException(), isNull);
    final recordButton = find.text('주차 기록하기');
    await tester.ensureVisible(recordButton);
    await tester.pumpAndSettle();
    await tester.tap(recordButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('체험 기록 저장'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('text editing preserves the draft without a confirmation panel', (
    tester,
  ) async {
    await start(tester);
    await demo(tester);
    await tester.tap(find.text('주차 기록하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'B1'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'A'));
    await tester.enterText(find.widgetWithText(TextField, '주차 번호 (선택)'), '73');
    await tester.pumpAndSettle();
    expect(find.text('B1 · A구역 · 73번'), findsNothing);
    expect(find.text('73'), findsOneWidget);
    final close = find.byTooltip('기록 창 닫기');
    await tester.ensureVisible(close);
    await tester.pumpAndSettle();
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.text('기록을 그만둘까요?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('어디에 주차했나요?'), findsOneWidget);
  });
  testWidgets('chips alone close without a discard confirmation', (
    tester,
  ) async {
    await start(tester);
    await demo(tester);
    await tester.tap(find.text('주차 기록하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'B1'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('기록 창 닫기'));
    await tester.pumpAndSettle();
    expect(find.text('기록을 그만둘까요?'), findsNothing);
    expect(find.text('어디에 주차했나요?'), findsNothing);
    expect(find.text('마지막 주차 위치'), findsOneWidget);
  });
}
