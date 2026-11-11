import 'dart:async';
import 'package:carcar/app/theme.dart';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/invite_links.dart';
import 'package:carcar/core/models.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/features/shell.dart';
import 'package:carcar/main.dart';
import 'package:carcar/shared/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_test.dart' show TestAuth, TestClient, SessionRepository;

/// An account without a vehicle. Like the server, joining names a member
/// without a profile '가족' and never touches an existing profile name.
class InvitedRepository extends SessionRepository {
  InvitedRepository(super.userId, {this.name, this.profile = ''})
    : super(empty: true);
  final String? name;
  String profile;
  Object? joinError, nameError;
  Completer<void>? joinHold, nameHold;
  bool member = false;
  final log = <String>[];
  @override
  String? get accountName => name;
  @override
  Future<String> profileName() async {
    log.add('profileName');
    await nameHold?.future;
    return profile;
  }

  @override
  Future<void> updateProfileName(String name) async {
    log.add('updateProfileName:$name');
    if (nameError != null) throw nameError!;
    profile = name;
  }

  @override
  Future<String> join(String code) async {
    log.add('join:$code');
    await joinHold?.future;
    if (joinError != null) throw joinError!;
    if (profile.isEmpty) profile = '가족';
    member = true;
    return 'family-car';
  }

  @override
  Future<List<Vehicle>> vehicles() async => member
      ? [
          const Vehicle(
            id: 'family-car',
            ownerId: 'owner',
            name: '우리 가족 차',
            plate: '12가 3456',
            apartment: '집',
          ),
        ]
      : [];
  @override
  Future<List<ParkingRecord>> records(String vehicleId) async => [];
  @override
  Future<List<FamilyMember>> members(String vehicleId) async => [
    const FamilyMember(id: 'owner', name: '엄마', owner: true),
    FamilyMember(id: userId, name: profile, owner: false),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Line breaks are measured with the font the app ships.
  setUpAll(() async {
    final font = FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf'));
    await font.load();
  });
  final code = 'a' * 48;
  const invitedTitle = '가족 초대를 받았어요';
  const joinLabel = '참여하기';
  const pasteLabel = '받은 초대로 참여';
  const usedUp = '이미 사용했거나 24시간이 지난 초대예요. 가족에게 새 초대를 받아 주세요.';

  Future<(InvitedRepository, SharedPreferences, TestAuth)> open(
    WidgetTester tester, {
    bool invited = true,
    String? name,
    Object? joinError,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final auth = TestAuth();
    addTearDown(auth.dispose);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('carcar/native'),
          (_) async => null,
        );
    late InvitedRepository repository;
    await tester.pumpWidget(
      CarcarApp(
        preferences: preferences,
        client: TestClient(auth),
        initialLink: () async => invited ? Uri.parse(inviteLink(code)) : null,
        incomingLinks: const Stream<Uri>.empty(),
        repositoryFactory: (client) => repository = InvitedRepository(
          client.auth.currentUser!.id,
          name: name,
        )..joinError = joinError,
      ),
    );
    await tester.pumpAndSettle();
    if (invited) {
      // The sign-in screen names no provider: iPhone users continue with Apple.
      expect(find.text('가족 초대를 받았어요. 로그인하면 바로 참여할 수 있어요.'), findsOneWidget);
      expect(find.textContaining('Google 로그인'), findsNothing);
    }
    auth.signInAs('A');
    await tester.pumpAndSettle();
    return (repository, preferences, auth);
  }

  bool isFilled(WidgetTester tester, String label) => find
      .ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      )
      .evaluate()
      .isNotEmpty;

  testWidgets('an invited member joins with one tap on the main button', (
    tester,
  ) async {
    final (repository, preferences, _) = await open(tester, name: '김민수');
    expect(find.text(invitedTitle), findsOneWidget);
    expect(isFilled(tester, joinLabel), isTrue);
    expect(isFilled(tester, '새 차량 등록'), isFalse);
    expect(find.text(pasteLabel), findsNothing);
    // Receiving the link and signing in never joins on their own.
    expect(repository.log, isEmpty);
    expect(PendingInvite(preferences).code, code);

    await tester.tap(find.text(joinLabel));
    await tester.pumpAndSettle();
    expect(repository.log.first, 'join:$code');
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('우리 가족 차'), findsOneWidget);
    expect(find.text(invitedTitle), findsNothing);
    expect(PendingInvite(preferences).code, isNull);
    // The joiner is greeted by the sign-in account name.
    expect(find.textContaining('김민수님'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a joiner the server named 가족 is never greeted as 가족님', (
    tester,
  ) async {
    final (repository, _, _) = await open(tester);
    await tester.tap(find.text(joinLabel));
    await tester.pumpAndSettle();
    expect(repository.profile, '가족');
    expect(find.text('우리 가족 차'), findsOneWidget);
    expect(find.textContaining('가족님'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a used or expired invitation explains why and returns the normal card',
    (tester) async {
      final (repository, preferences, _) = await open(
        tester,
        joinError: const InvalidInviteException(),
      );
      await tester.tap(find.text(joinLabel));
      await tester.pumpAndSettle();
      expect(repository.member, isFalse);
      expect(find.text(usedUp), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(PendingInvite(preferences).code, isNull);
      expect(find.text(invitedTitle), findsNothing);
      expect(find.text('우리 가족의 차 한 대'), findsOneWidget);
      expect(find.text(joinLabel), findsNothing);
      expect(isFilled(tester, '새 차량 등록'), isTrue);
      expect(find.text(pasteLabel), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a temporary failure keeps the invitation for another tap', (
    tester,
  ) async {
    final (repository, preferences, _) = await open(
      tester,
      joinError: const AppException('시도가 많아 잠시 제한되었어요. 10분 뒤 다시 시도해 주세요.'),
    );
    await tester.tap(find.text(joinLabel));
    await tester.pumpAndSettle();
    expect(find.textContaining('잠시 제한되었어요'), findsOneWidget);
    expect(find.text(invitedTitle), findsOneWidget);
    expect(PendingInvite(preferences).code, code);
    expect(repository.member, isFalse);

    repository.joinError = null;
    await tester.tap(find.text(joinLabel));
    await tester.pumpAndSettle();
    expect(find.text('우리 가족 차'), findsOneWidget);
    expect(find.byType(StatusNotice), findsNothing);
    expect(PendingInvite(preferences).code, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without an invitation the paste button opens the sheet', (
    tester,
  ) async {
    final (repository, _, _) = await open(tester, invited: false);
    expect(find.text('우리 가족의 차 한 대'), findsOneWidget);
    expect(find.text(joinLabel), findsNothing);
    expect(isFilled(tester, '새 차량 등록'), isTrue);
    // The card never asks for a 'code': the family shares a link.
    expect(find.textContaining('코드'), findsNothing);
    await tester.tap(find.text(pasteLabel));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('초대 코드 또는 링크'), findsOneWidget);
    expect(find.text('가족 차량에 참여하기'), findsOneWidget);
    expect(repository.log, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (invited, label) in const [
    (false, pasteLabel),
    (true, joinLabel),
  ]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('"$label" stays on one line at 320px x$scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await open(tester, invited: invited);
        final lines = tester
            .renderObject<RenderParagraph>(find.text(label))
            .getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: label.length),
            )
            .map((box) => box.top)
            .toSet();
        expect(lines, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('an unreadable link asks for the link the family sent', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = TestAuth();
    addTearDown(auth.dispose);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('carcar/native'),
          (_) async => null,
        );
    await tester.pumpWidget(
      CarcarApp(
        preferences: await SharedPreferences.getInstance(),
        client: TestClient(auth),
        initialLink: () async => null,
        incomingLinks: Stream<Uri>.error(StateError('unreadable')),
        repositoryFactory: (client) =>
            InvitedRepository(client.auth.currentUser!.id),
      ),
    );
    auth.signInAs('A');
    await tester.pumpAndSettle();
    expect(find.text('초대 링크를 읽지 못했어요. 받은 링크를 붙여 넣어 주세요.'), findsOneWidget);
    // Only a link is shared, so nothing here asks for a code.
    expect(find.textContaining('코드'), findsNothing);
    expect(find.text(pasteLabel), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('while joining, the card shows progress and locks its exits', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('carcar/native'),
          (_) async => null,
        );
    SharedPreferences.setMockInitialValues({});
    final repository = InvitedRepository('A')..joinHold = Completer<void>();
    final controller = AppController(repository);
    await controller.initialize();
    addTearDown(controller.dispose);
    final clearing = Completer<void>();
    var cleared = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AppShell(
          controller: controller,
          preferences: await SharedPreferences.getInstance(),
          onLogout: () async {},
          pendingInvite: code,
          onClearInvite: () {
            cleared++;
            return clearing.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    VoidCallback? action<T extends ButtonStyleButton>(String label) =>
        tester.widget<T>(find.widgetWithText(T, label)).onPressed;
    expect(action<OutlinedButton>('새 차량 등록'), isNotNull);
    expect(action<TextButton>('로그아웃'), isNotNull);

    await tester.tap(find.text(joinLabel));
    await tester.pump();
    // Sent, not answered: one spinner on the pressed button, nothing else.
    expect(find.bySemanticsLabel('$joinLabel 처리 중'), findsOneWidget);
    expect(find.text(joinLabel), findsNothing);
    expect(action<OutlinedButton>('새 차량 등록'), isNull);
    expect(action<TextButton>('로그아웃'), isNull);
    expect(repository.log, ['join:$code']);

    repository.joinHold!.complete();
    await tester.pump();
    await tester.pump();
    // Joined and loaded, the used invitation not yet cleared from the device:
    // it must not be reported as an invitation that cannot be used.
    expect(find.text('우리 가족 차'), findsOneWidget);
    expect(cleared, 1);
    expect(find.textContaining('이미 연결된 차량이 있어요'), findsNothing);
    expect(find.text('받은 초대 닫기'), findsNothing);
    clearing.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stalled name step never keeps a joined member waiting', (
    tester,
  ) async {
    final repository = InvitedRepository('A', name: '김민수')
      ..nameHold = Completer<void>();
    final controller = AppController(repository);
    addTearDown(controller.dispose);
    var done = false;
    unawaited(controller.join(code).then((_) => done = true));
    await tester.pump();
    // The invitation is checked first; the optional name never delays it.
    expect(repository.log, ['join:$code', 'profileName']);
    expect(repository.member, isTrue);
    expect(done, isFalse);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(done, isTrue);
    expect(controller.vehicle?.id, 'family-car');
    expect(repository.profile, '가족');
  });

  group('first name of a joiner', () {
    test('comes from the sign-in account when no profile exists', () async {
      final repository = InvitedRepository('A', name: '김민수');
      final controller = AppController(repository);
      addTearDown(controller.dispose);
      await controller.join(code);
      // Only after the server accepted the invitation.
      expect(repository.log, [
        'join:$code',
        'profileName',
        'updateProfileName:김민수',
      ]);
      expect(repository.profile, '김민수');
      expect(controller.author('A'), '김민수');
    });
    test('is not written when the invitation is refused', () async {
      final repository = InvitedRepository('A', name: '김민수')
        ..joinError = const InvalidInviteException();
      final controller = AppController(repository);
      addTearDown(controller.dispose);
      await expectLater(
        controller.join(code),
        throwsA(isA<InvalidInviteException>()),
      );
      // No profile row is left to shadow the name typed at registration.
      expect(repository.log, ['join:$code']);
      expect(repository.profile, isEmpty);
      expect(repository.member, isFalse);
    });
    test('never replaces a name the member already has', () async {
      final repository = InvitedRepository('A', name: '김민수', profile: '아빠');
      final controller = AppController(repository);
      addTearDown(controller.dispose);
      await controller.join(code);
      expect(repository.log, ['join:$code', 'profileName']);
      expect(repository.profile, '아빠');
    });
    test('stays the server default when the account has no name', () async {
      final repository = InvitedRepository('A');
      final controller = AppController(repository);
      addTearDown(controller.dispose);
      await controller.join(code);
      expect(repository.log, ['join:$code']);
      expect(repository.profile, '가족');
    });
    test('is optional: a failed name write does not block joining', () async {
      final repository = InvitedRepository('A', name: '김민수')
        ..nameError = StateError('offline');
      final controller = AppController(repository);
      addTearDown(controller.dispose);
      await controller.join(code);
      expect(repository.member, isTrue);
      expect(repository.profile, '가족');
      expect(controller.vehicle?.id, 'family-car');
    });
  });
}
