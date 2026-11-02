import 'dart:async';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/invite_links.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/features/management.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RegistrationRepository implements ParkingRepository {
  Completer<bool>? pending;
  bool available = true;
  @override
  Future<bool> isPlateAvailable(String plate) async =>
      pending == null ? available : pending!.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RegistrationController extends AppController {
  RegistrationController(super.repository);
  bool fail = false;
  int creates = 0;
  String? joined;
  @override
  Future<void> createVehicle(
    String apartment,
    String plate,
    String name,
    String nickname,
  ) async {
    creates++;
    if (fail) throw AppException('이미 등록된 차량이에요.');
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
                    ? await openJoinVehicle(
                        context,
                        controller,
                        initialCode: initial,
                      )
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
  }

  Future<void> fill(WidgetTester tester) async {
    final fields = find.byType(TextFormField);
    for (var i = 0; i < 4; i++) {
      await tester.enterText(
        fields.at(i),
        ['우리 차', '123가4567', '우리 집', '가족'][i],
      );
    }
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

  testWidgets('registration requires a fresh plate check after edits', (
    tester,
  ) async {
    await open(tester);
    await fill(tester);
    expect(saveEnabled(tester), isFalse);
    await tap(tester, '차량 번호 중복 확인');
    expect(saveEnabled(tester), isTrue);
    await tester.enterText(find.byType(TextFormField).at(1), '123가4568');
    await tester.pump();
    expect(saveEnabled(tester), isFalse);
  });
  testWidgets('late availability response cannot approve a changed plate', (
    tester,
  ) async {
    repository.pending = Completer<bool>();
    await open(tester);
    await fill(tester);
    await tester.ensureVisible(find.text('차량 번호 중복 확인'));
    await tester.tap(find.text('차량 번호 중복 확인'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).at(1), '123가4568');
    repository.pending!.complete(true);
    await tester.pumpAndSettle();
    expect(saveEnabled(tester), isFalse);
    expect(find.text('등록할 수 있는 차량 번호예요.'), findsNothing);
  });
  testWidgets('duplicate plate directs the user to a family invitation', (
    tester,
  ) async {
    repository.available = false;
    await open(tester);
    await fill(tester);
    await tap(tester, '차량 번호 중복 확인');
    expect(saveEnabled(tester), isFalse);
    expect(find.textContaining('처음 등록한 가족'), findsOneWidget);
  });
  testWidgets('server conflict preserves input and requires another check', (
    tester,
  ) async {
    controller.fail = true;
    await open(tester);
    await fill(tester);
    await tap(tester, '차량 번호 중복 확인');
    await tap(tester, '차량 등록하기');
    expect(controller.creates, 1);
    expect(find.text('123가4567'), findsOneWidget);
    expect(saveEnabled(tester), isFalse);
    expect(find.text('이미 등록된 차량이에요.'), findsOneWidget);
  });
  testWidgets('confirmed registration returns true and closes', (tester) async {
    bool? result;
    await open(tester, result: (value) => result = value);
    await fill(tester);
    await tap(tester, '차량 번호 중복 확인');
    await tap(tester, '차량 등록하기');
    expect(result, isTrue);
    expect(find.byType(Dialog), findsNothing);
  });
  testWidgets(
    'prefilled invitation requires explicit confirmation and accepts its link',
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
  testWidgets('closing a prefilled invitation returns false', (tester) async {
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
