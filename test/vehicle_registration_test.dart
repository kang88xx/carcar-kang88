import 'dart:async';
import 'package:carcar/app/theme.dart';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/invite_links.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/features/management.dart';
import 'package:carcar/shared/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegistrationRepository implements ParkingRepository {
  @override
  String? accountName;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RegistrationController extends AppController {
  RegistrationController(super.repository);
  bool fail = false;
  Object? failure;
  Completer<void>? pending;
  final created = <List<String>>[];
  int get creates => created.length;
  String? joined;
  @override
  Future<void> createVehicle(
    String apartment,
    String plate,
    String name,
    String nickname,
  ) async {
    created.add([apartment, plate, name, nickname]);
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<void> join(String code) async {
    if (fail) throw AppException('초대가 만료됐어요.');
    joined = code;
  }
}

void main() {
  late RegistrationRepository repository;
  late RegistrationController controller;
  setUp(() {
    repository = RegistrationRepository();
    controller = RegistrationController(repository);
  });

  Future<void> open(
    WidgetTester tester, {
    bool join = false,
    String? initial,
    void Function(bool)? result,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final value = join
                    ? await openJoinVehicle(context, controller)
                    : await openCreateVehicle(context, controller);
                result?.call(value);
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    if (initial != null) {
      await tester.enterText(find.byType(TextFormField), initial);
    }
  }

  Finder field(int index) => find.byType(TextFormField).at(index);
  Finder under(int index, String text) =>
      find.descendant(of: field(index), matching: find.text(text));
  TextField input(WidgetTester tester, int index) => tester.widget<TextField>(
    find.descendant(of: field(index), matching: find.byType(TextField)),
  );
  bool focused(WidgetTester tester, int index) => tester
      .widget<EditableText>(
        find.descendant(of: field(index), matching: find.byType(EditableText)),
      )
      .focusNode
      .hasFocus;
  final counter = find.textContaining(RegExp(r'^\d+\s*/\s*\d+$'));

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

  const duplicate = PostgrestException(
    message: 'plate_already_registered',
    code: '23505',
  );
  const duplicateMessage = '이미 등록된 차량번호예요. 처음 등록한 가족에게 초대 링크나 코드를 받아 주세요.';

  testWidgets('sheet asks for the plate first and nothing about the apartment', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(input(tester, 0).decoration!.labelText, '차량 번호');
    expect(input(tester, 1).decoration!.labelText, '차량 별명');
    expect(input(tester, 2).decoration!.labelText, '내 이름');
    expect(focused(tester, 0), isTrue);
    expect(input(tester, 1).controller!.text, '우리 차');
    expect(input(tester, 2).controller!.text, isEmpty);
    expect(find.text('아파트 이름'), findsNothing);
    expect(find.text('차량 번호 중복 확인'), findsNothing);
    // Nothing has to be checked first: the one action is ready from the start.
    expect(saveEnabled(tester), isTrue);
    expect(controller.creates, 0);
  });
  testWidgets('one tap registers once with the default apartment name', (
    tester,
  ) async {
    bool? result;
    await open(tester, result: (value) => result = value);
    await tester.enterText(field(0), '123가4567');
    await tester.enterText(field(2), '가족');
    await tap(tester, '차량 등록하기');
    expect(controller.created, [
      ['우리 아파트', '123가4567', '우리 차', '가족'],
    ]);
    expect(result, isTrue);
    expect(find.byType(Dialog), findsNothing);
  });
  testWidgets('nothing closes or repeats while the server has not answered', (
    tester,
  ) async {
    bool? result;
    controller.pending = Completer<void>();
    await open(tester, result: (value) => result = value);
    await tester.enterText(field(0), '123가4567');
    await tester.enterText(field(2), '가족');
    await tester.ensureVisible(find.text('차량 등록하기'));
    await tester.tap(find.text('차량 등록하기'));
    await tester.pump();
    expect(saveEnabled(tester), isFalse);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(controller.creates, 1);
    expect(result, isNull);
    expect(find.byType(Dialog), findsOneWidget);
    controller.pending!.complete();
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
  testWidgets('account name fills my name and can still be edited', (
    tester,
  ) async {
    repository.accountName = '김민수';
    await open(tester);
    expect(input(tester, 2).controller!.text, '김민수');
    await tester.enterText(field(0), '123가4567');
    await tester.enterText(field(2), '아빠');
    await tap(tester, '차량 등록하기');
    expect(controller.created.single, ['우리 아파트', '123가4567', '우리 차', '아빠']);
  });
  testWidgets('empty fields are named in plain sentences and nothing is sent', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(field(1), '');
    await tap(tester, '차량 등록하기');
    expect(under(0, '차량 번호를 입력해 주세요.'), findsOneWidget);
    expect(under(1, '차량 별명을 입력해 주세요.'), findsOneWidget);
    expect(under(2, '내 이름을 입력해 주세요.'), findsOneWidget);
    expect(find.textContaining('을(를)'), findsNothing);
    expect(controller.creates, 0);
  });
  testWidgets('duplicate plate is explained under the plate field', (
    tester,
  ) async {
    bool? result;
    controller.failure = duplicate;
    await open(tester, result: (value) => result = value);
    await tester.enterText(field(0), '123가4567');
    await tester.enterText(field(2), '가족');
    await tap(tester, '차량 등록하기');
    expect(controller.creates, 1);
    expect(under(0, duplicateMessage), findsOneWidget);
    // Long enough to wrap: the part about asking for an invitation must show.
    expect(input(tester, 0).decoration!.errorMaxLines, 3);
    expect(find.byType(StatusNotice), findsNothing);
    // Not registered: the sheet stays open with the input, ready to retry.
    expect(result, isNull);
    expect(input(tester, 0).controller!.text, '123가4567');
    expect(saveEnabled(tester), isTrue);
    await tester.enterText(field(0), '123가4568');
    await tester.pump();
    expect(find.text(duplicateMessage), findsNothing);
    controller.failure = null;
    await tap(tester, '차량 등록하기');
    expect(controller.creates, 2);
    expect(result, isTrue);
  });
  testWidgets('wrong plate format is explained under the plate field', (
    tester,
  ) async {
    controller.failure = const PostgrestException(
      message: 'invalid_plate',
      code: '22023',
    );
    await open(tester);
    await tester.enterText(field(0), '!!');
    await tester.enterText(field(2), '가족');
    await tap(tester, '차량 등록하기');
    expect(under(0, '차량 번호를 확인해 주세요. 예: 123가 4567'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
  });
  testWidgets('a connection failure is not blamed on the plate', (
    tester,
  ) async {
    controller.failure = StateError('offline');
    await open(tester);
    await tester.enterText(field(0), '123가4567');
    await tester.enterText(field(2), '가족');
    await tap(tester, '차량 등록하기');
    const message = '연결이 불안정해요. 다시 시도해 주세요.';
    expect(under(0, message), findsNothing);
    expect(find.widgetWithText(StatusNotice, message), findsOneWidget);
    expect(input(tester, 0).controller!.text, '123가4567');
    expect(find.byType(Dialog), findsOneWidget);
  });
  group('with the keyboard open', () {
    setUpAll(() async {
      final font = FontLoader('NotoSansKR')
        ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf'));
      await font.load();
    });
    for (final (size, top, keyboard) in const [
      (Size(375, 667), 20.0, 260.0),
      (Size(393, 852), 59.0, 336.0),
    ]) {
      testWidgets('the register button stays on screen at '
          '${size.width}x${size.height}, also after a connection error', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = FakeViewPadding(top: top);
        tester.view.viewPadding = FakeViewPadding(top: top);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetViewInsets);
        controller.failure = StateError('offline');
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openCreateVehicle(context, controller),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('열기'));
        await tester.pumpAndSettle();
        // The plate field takes focus on open, so the keyboard is up at once.
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        await tester.pumpAndSettle();
        final visibleEnd = size.height - keyboard;
        final button = find.byType(FilledButton);
        expect(tester.getRect(button).bottom, lessThanOrEqualTo(visibleEnd));
        expect(button.hitTestable(), findsOneWidget);

        await tester.enterText(field(0), '123가4567');
        await tester.enterText(field(2), '가족');
        await tester.tap(button);
        await tester.pumpAndSettle();
        const message = '연결이 불안정해요. 다시 시도해 주세요.';
        final notice = find.widgetWithText(StatusNotice, message);
        expect(notice.hitTestable(), findsOneWidget);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(message))
              .getBoxesForSelection(
                const TextSelection(
                  baseOffset: 0,
                  extentOffset: message.length,
                ),
              )
              .map((box) => box.top)
              .toSet(),
          hasLength(1),
        );
        // The message above the button did not push it behind the keyboard.
        expect(tester.getRect(button).bottom, lessThanOrEqualTo(visibleEnd));
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
  testWidgets('keyboard action walks the fields and submits on the last', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(field(0), '123가4567');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(focused(tester, 1), isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(focused(tester, 2), isTrue);
    expect(input(tester, 2).textInputAction, TextInputAction.done);
    await tester.enterText(field(2), '가족');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.created.single, ['우리 아파트', '123가4567', '우리 차', '가족']);
  });
  testWidgets('length limits stay without visible character counters', (
    tester,
  ) async {
    await open(tester);
    expect(
      [for (var i = 0; i < 3; i++) input(tester, i).maxLength],
      [20, 40, 40],
    );
    expect(counter, findsNothing);
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    await open(tester, join: true);
    expect(input(tester, 0).maxLength, 2048);
    expect(counter, findsNothing);
  });
  testWidgets(
    'pasted invitation requires explicit confirmation and accepts its link',
    (tester) async {
      final code = 'a' * 48;
      bool? result;
      await open(
        tester,
        join: true,
        initial: inviteLink(code),
        result: (value) => result = value,
      );
      expect(controller.joined, isNull);
      await tap(tester, '가족 차량에 참여하기');
      expect(controller.joined, code);
      expect(result, isTrue);
    },
  );
  testWidgets('invalid and expired invitations stay open without joining', (
    tester,
  ) async {
    await open(tester, join: true, initial: 'wrong');
    await tap(tester, '가족 차량에 참여하기');
    expect(controller.joined, isNull);
    expect(find.text('올바른 초대 코드 또는 링크를 입력해 주세요.'), findsOneWidget);
    controller.fail = true;
    await tester.enterText(find.byType(TextFormField), 'b' * 48);
    await tap(tester, '가족 차량에 참여하기');
    expect(find.text('초대가 만료됐어요.'), findsOneWidget);
    expect(controller.joined, isNull);
  });
  testWidgets('closing a pasted invitation returns false', (tester) async {
    bool? result;
    await open(
      tester,
      join: true,
      initial: 'c' * 48,
      result: (value) => result = value,
    );
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(controller.joined, isNull);
  });
}
