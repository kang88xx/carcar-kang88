import 'dart:async';
import 'package:carcar/app/theme.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/features/auth_screen.dart';
import 'package:carcar/features/profile_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

class AccountAuth implements GoTrueClient {
  User? user = _user('owner');
  Object? error;
  Completer<void>? pending;
  String? requestedEmail, redirect, password;
  OtpType? resendType;
  int requests = 0, updates = 0;
  @override
  User? get currentUser => user;
  @override
  Future<void> resetPasswordForEmail(
    String email, {
    String? redirectTo,
    String? captchaToken,
  }) async {
    requests++;
    requestedEmail = email;
    redirect = redirectTo;
    if (pending != null) await pending!.future;
    if (error != null) throw error!;
  }

  @override
  Future<ResendResponse> resend({
    String? email,
    String? phone,
    required OtpType type,
    String? emailRedirectTo,
    String? captchaToken,
  }) async {
    requests++;
    requestedEmail = email;
    resendType = type;
    redirect = emailRedirectTo;
    if (error != null) throw error!;
    return ResendResponse();
  }

  @override
  Future<UserResponse> updateUser(
    UserAttributes attributes, {
    String? emailRedirectTo,
  }) async {
    updates++;
    password = attributes.password;
    if (error != null) throw error!;
    return UserResponse.fromJson(user!.toJson());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AccountClient implements SupabaseClient {
  AccountClient(this.testAuth);
  final AccountAuth testAuth;
  @override
  GoTrueClient get auth => testAuth;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ProfileRepository implements ParkingRepository {
  String name = '가족';
  Object? loadError, saveError;
  int writes = 0;
  Completer<void>? pending;
  @override
  bool get isDemo => false;
  @override
  Future<String> profileName() async {
    if (loadError != null) throw loadError!;
    return name;
  }

  @override
  Future<void> updateProfileName(String value) async {
    writes++;
    if (pending != null) await pending!.future;
    if (saveError != null) throw saveError!;
    name = validatedProfileName(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ProfileDisk implements SharedPreferences {
  ProfileDisk(this.backing);
  final SharedPreferences backing;
  bool fail = false;
  @override
  String? getString(String key) => backing.getString(key);
  @override
  Future<bool> setString(String key, String value) =>
      fail ? Future.value(false) : backing.setString(key, value);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: page));
    await tester.pumpAndSettle();
  }

  Future<void> openHelp(
    WidgetTester tester,
    AccountAuth auth, {
    bool recovery = true,
  }) async {
    await pumpPage(
      tester,
      AuthScreen(client: AccountClient(auth), onDemo: () async {}),
    );
    await tester.enterText(
      find.byType(TextFormField).first,
      '  me@example.com  ',
    );
    await tester.tap(find.text(recovery ? '비밀번호를 잊으셨나요?' : '가입 확인 메일 다시 받기'));
    await tester.pumpAndSettle();
  }

  Future<void> closeHelp(WidgetTester tester) async {
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets(
    'auth mode switch clears stale errors and preserves typed credentials',
    (tester) async {
      final auth = AccountAuth();
      await pumpPage(
        tester,
        AuthScreen(client: AccountClient(auth), onDemo: () async {}),
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'family@example.com',
      );
      await tester.enterText(find.byType(TextFormField).last, 'short');
      await tester.tap(find.text('처음 오셨나요? 계정 만들기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('계정 만들기'));
      await tester.pumpAndSettle();
      expect(find.text('비밀번호를 8자 이상 입력해 주세요.'), findsOneWidget);
      await tester.tap(find.text('이미 계정이 있어요 · 로그인'));
      await tester.pumpAndSettle();
      expect(find.text('비밀번호를 8자 이상 입력해 주세요.'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'family@example.com',
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).last)
            .controller!
            .text,
        'short',
      );
      expect(tester.state<FormState>(find.byType(Form)).validate(), isTrue);
      await tester.pumpAndSettle();
      await tester.tap(find.text('처음 오셨나요? 계정 만들기'));
      await tester.pumpAndSettle();
      expect(find.text('가족과 함께 시작해요'), findsOneWidget);
      expect(tester.state<FormState>(find.byType(Form)).validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('비밀번호를 8자 이상 입력해 주세요.'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).last)
            .controller!
            .text,
        'short',
      );
      await tester.enterText(find.byType(TextFormField).last, 'long-enough');
      expect(tester.state<FormState>(find.byType(Form)).validate(), isTrue);
      expect(auth.requests, 0);
    },
  );

  testWidgets(
    'recovery requests only email and prevents duplicate pending sends',
    (tester) async {
      final auth = AccountAuth()..pending = Completer<void>();
      await openHelp(tester, auth);
      await tester.tap(find.text('안내 메일 요청'));
      await tester.pump();
      expect(auth.requests, 1);
      expect(auth.requestedEmail, 'me@example.com');
      expect(auth.redirect, 'com.kang88.carcar://login-callback');
      expect(find.textContaining('등록된 계정이라면'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull,
      );
      auth.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('등록된 계정이라면'), findsOneWidget);
      expect(find.text('60초 후 다시 요청'), findsOneWidget);
      await closeHelp(tester);
    },
  );

  testWidgets(
    'email request validates email without requiring login password',
    (tester) async {
      final auth = AccountAuth();
      await openHelp(tester, auth);
      final dialog = find.byType(AlertDialog);
      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextFormField)),
        'invalid',
      );
      await tester.tap(find.text('안내 메일 요청'));
      await tester.pumpAndSettle();
      expect(auth.requests, 0);
      expect(find.text('이메일 주소를 확인해 주세요.'), findsOneWidget);
      await closeHelp(tester);
    },
  );

  testWidgets('mail errors preserve input and do not claim a sent message', (
    tester,
  ) async {
    final auth = AccountAuth()
      ..error = const AuthException(
        'server details should not leak',
        statusCode: '500',
      );
    await openHelp(tester, auth);
    await tester.tap(find.text('안내 메일 요청'));
    await tester.pumpAndSettle();
    expect(find.textContaining('메일 요청을 완료하지 못했어요.'), findsOneWidget);
    expect(find.textContaining('등록된 계정이라면'), findsNothing);
    expect(find.textContaining('server details'), findsNothing);
    auth.error = null;
    await tester.tap(find.text('안내 메일 요청'));
    await tester.pumpAndSettle();
    expect(auth.requests, 2);
    expect(auth.requestedEmail, 'me@example.com');
    await closeHelp(tester);
  });

  testWidgets('unknown account uses the same conditional notice', (
    tester,
  ) async {
    final auth = AccountAuth()
      ..error = const AuthException('user not found', code: 'user_not_found');
    await openHelp(tester, auth);
    await tester.tap(find.text('안내 메일 요청'));
    await tester.pumpAndSettle();
    expect(find.textContaining('등록된 계정이라면'), findsOneWidget);
    expect(find.textContaining('user not found'), findsNothing);
    await closeHelp(tester);
  });

  testWidgets('confirmation resend uses signup type and configured callback', (
    tester,
  ) async {
    final auth = AccountAuth();
    await openHelp(tester, auth, recovery: false);
    await tester.tap(find.text('안내 메일 요청'));
    await tester.pumpAndSettle();
    expect(auth.resendType, OtpType.signup);
    expect(auth.requestedEmail, 'me@example.com');
    expect(auth.redirect, 'com.kang88.carcar://login-callback');
    expect(find.textContaining('가입 확인이 필요한 계정이라면'), findsOneWidget);
    await closeHelp(tester);
  });

  testWidgets(
    'password recovery rejects mismatch and keeps input after server failure',
    (tester) async {
      final auth = AccountAuth()..error = const AuthException('unavailable');
      var complete = 0;
      await pumpPage(
        tester,
        PasswordRecoveryScreen(
          client: AccountClient(auth),
          onComplete: () async {
            complete++;
          },
          onCancel: () async {},
        ),
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'new-password-123',
      );
      await tester.enterText(find.byType(TextFormField).last, 'different');
      await tester.tap(find.text('비밀번호 변경'));
      await tester.pumpAndSettle();
      expect(auth.updates, 0);
      expect(find.text('두 비밀번호가 같아야 해요.'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).last,
        'new-password-123',
      );
      await tester.tap(find.text('비밀번호 변경'));
      await tester.pumpAndSettle();
      expect(auth.updates, 1);
      expect(complete, 0);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'new-password-123',
      );
      auth.error = null;
      await tester.tap(find.text('비밀번호 변경'));
      await tester.pumpAndSettle();
      expect(complete, 1);
      expect(auth.password, 'new-password-123');
    },
  );

  testWidgets('changed recovery account cannot update another user password', (
    tester,
  ) async {
    final auth = AccountAuth();
    await pumpPage(
      tester,
      PasswordRecoveryScreen(
        client: AccountClient(auth),
        onComplete: () async {},
        onCancel: () async {},
      ),
    );
    auth.user = _user('other');
    await tester.enterText(
      find.byType(TextFormField).first,
      'new-password-123',
    );
    await tester.enterText(find.byType(TextFormField).last, 'new-password-123');
    await tester.tap(find.text('비밀번호 변경'));
    await tester.pumpAndSettle();
    expect(auth.updates, 0);
    expect(find.textContaining('재설정 링크가 만료되었어요.'), findsOneWidget);
  });

  testWidgets(
    'completion failure retries logout callback without changing password again',
    (tester) async {
      final auth = AccountAuth();
      var attempts = 0;
      await pumpPage(
        tester,
        PasswordRecoveryScreen(
          client: AccountClient(auth),
          onComplete: () async {
            if (++attempts == 1) {
              throw const AppException('로그인 화면 전환을 다시 시도해 주세요.');
            }
          },
          onCancel: () async {},
        ),
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'new-password-123',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'new-password-123',
      );
      await tester.tap(find.text('비밀번호 변경'));
      await tester.pumpAndSettle();
      expect(auth.updates, 1);
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('로그인으로 돌아가기'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(auth.updates, 1);
    },
  );

  testWidgets(
    'profile editor keeps failed edits and only completes after confirmed save',
    (tester) async {
      final repo = ProfileRepository()..saveError = const AppException('저장 실패');
      bool? saved;
      await pumpPage(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await openProfileEditor(context, repo);
              },
              child: const Text('편집'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('편집'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.text('이름 저장'));
      await tester.pumpAndSettle();
      expect(repo.writes, 0);
      await tester.enterText(find.byType(TextFormField), '  아빠  ');
      await tester.tap(find.text('이름 저장'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('저장 실패'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '  아빠  ',
      );
      repo.saveError = null;
      await tester.tap(find.text('이름 저장'));
      await tester.pumpAndSettle();
      expect(saved, isTrue);
      expect(repo.name, '아빠');
    },
  );

  testWidgets(
    'profile load failure is retryable and cannot submit an unknown value',
    (tester) async {
      final repo = ProfileRepository()
        ..loadError = const AppException('불러오기 실패');
      await pumpPage(tester, ProfileEditorDialog(repository: repo));
      expect(find.text('불러오기 실패'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      repo.loadError = null;
      await tester.tap(find.byTooltip('다시 시도'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '가족',
      );
    },
  );

  test('profile name uses bounded Unicode character count', () {
    expect(validatedProfileName('  가족  '), '가족');
    expect(validatedProfileName('😀' * 40), '😀' * 40);
    expect(() => validatedProfileName('😀' * 41), throwsA(isA<AppException>()));
    expect(() => validatedProfileName('  '), throwsA(isA<AppException>()));
  });

  testWidgets(
    'recovery and profile forms fit a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget app(Widget page) => MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: page,
      );
      await tester.pumpWidget(
        app(
          PasswordRecoveryScreen(
            client: AccountClient(AccountAuth()),
            onComplete: () async {},
            onCancel: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('비밀번호 변경'));
      await tester.pumpAndSettle();
      expect(find.text('비밀번호 변경').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        app(ProfileEditorDialog(repository: ProfileRepository())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('이름 저장').hitTestable(), findsOneWidget);
    },
  );

  test(
    'demo profile persists, affects author name, and rolls back failed disk writes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final disk = ProfileDisk(prefs);
      final repo = DemoParkingRepository(disk);
      await repo.initialize();
      await repo.updateProfileName('  엄마  ');
      expect((await repo.members('demo-car')).first.name, '엄마');
      final reopened = DemoParkingRepository(prefs);
      await reopened.initialize();
      expect(await reopened.profileName(), '엄마');
      disk.fail = true;
      await expectLater(
        repo.updateProfileName('아빠'),
        throwsA(isA<AppException>()),
      );
      expect(await repo.profileName(), '엄마');
      expect(await reopened.profileName(), '엄마');
      await reopened.deleteAccount();
      expect(await reopened.profileName(), '나');
    },
  );

  test(
    'stale authenticated repository refuses profile access after account switch',
    () async {
      final auth = AccountAuth();
      final repo = SupabaseParkingRepository(AccountClient(auth));
      auth.user = _user('other');
      await expectLater(repo.profileName(), throwsA(isA<AppException>()));
      await expectLater(
        repo.updateProfileName('다른 사람'),
        throwsA(isA<AppException>()),
      );
    },
  );
}
