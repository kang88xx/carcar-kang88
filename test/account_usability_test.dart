import 'dart:async';
import 'package:carcar/app/theme.dart';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/features/auth_screen.dart';
import 'package:carcar/features/management.dart';
import 'package:carcar/features/profile_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets(
    'Google launch prevents duplicate requests without claiming sign-in',
    (tester) async {
      final pending = Completer<bool>();
      var requests = 0;
      await pumpPage(
        tester,
        AuthScreen(
          client: AccountClient(AccountAuth()),
          onDemo: () async {},
          onGoogleSignIn: () {
            requests++;
            return pending.future;
          },
        ),
      );
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('Google로 계속하기'));
      await tester.pump();
      expect(requests, 1);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byWidgetPredicate((w) => w is OutlinedButton),
            )
            .onPressed,
        isNull,
      );
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(find.textContaining('Google에서 로그인하면'), findsOneWidget);
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byWidgetPredicate((w) => w is OutlinedButton),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'Google launch failure permits retry and keeps invitation notice',
    (tester) async {
      var attempts = 0;
      await pumpPage(
        tester,
        AuthScreen(
          client: AccountClient(AccountAuth()),
          onDemo: () async {},
          startupNotice: '가족 초대를 받았어요.',
          onGoogleSignIn: () async => ++attempts > 1,
        ),
      );
      await tester.tap(find.text('Google로 계속하기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('로그인 창을 열지 못했어요'), findsOneWidget);
      expect(find.text('가족 초대를 받았어요.'), findsOneWidget);
      await tester.tap(find.text('Google로 계속하기'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.textContaining('로그인 창을 열지 못했어요'), findsNothing);
      expect(find.textContaining('Google에서 로그인하면'), findsOneWidget);
    },
  );

  testWidgets('Google server errors do not expose details or report success', (
    tester,
  ) async {
    await pumpPage(
      tester,
      AuthScreen(
        client: AccountClient(AccountAuth()),
        onDemo: () async {},
        onGoogleSignIn: () async => throw const AuthException(
          'private server detail',
          statusCode: '500',
        ),
      ),
    );
    await tester.tap(find.text('Google로 계속하기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('private server detail'), findsNothing);
    expect(find.textContaining('Google에서 로그인하면'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byWidgetPredicate((w) => w is OutlinedButton),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('unconfigured app offers local demo and no unavailable login', (
    tester,
  ) async {
    var demos = 0;
    await pumpPage(
      tester,
      AuthScreen(
        client: null,
        onDemo: () async {
          demos++;
        },
      ),
    );
    expect(find.text('Google로 계속하기'), findsNothing);
    await tester.tap(find.text('체험 시작하기'));
    await tester.pumpAndSettle();
    expect(demos, 1);
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

  testWidgets('profile name keeps its limit without a visible counter', (
    tester,
  ) async {
    await pumpPage(
      tester,
      ProfileEditorDialog(repository: ProfileRepository()),
    );
    final name = find.byType(TextField);
    expect(tester.widget<TextField>(name).maxLength, 40);
    await tester.enterText(name, '가' * 50);
    await tester.pump();
    expect(tester.widget<TextField>(name).controller!.text, '가' * 40);
    expect(find.textContaining(RegExp(r'^\d+\s*/\s*\d+$')), findsNothing);
  });

  test('sign-in name suggestion comes only from a non-empty account name', () {
    User user(Map<String, dynamic>? data) => User(
      id: 'owner',
      appMetadata: const {},
      userMetadata: data,
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    );
    expect(accountDisplayName(user({'full_name': ' 김민수 '})), '김민수');
    expect(
      accountDisplayName(user({'full_name': ' ', 'name': 'Minsu'})),
      'Minsu',
    );
    expect(
      accountDisplayName(user({'full_name': 7, 'email': 'a@b.c'})),
      isNull,
    );
    expect(accountDisplayName(user(null)), isNull);
    expect(accountDisplayName(null), isNull);
    // Never longer than a profile name may be.
    expect(
      validatedProfileName(accountDisplayName(user({'name': '가' * 60}))!),
      '가' * 40,
    );
  });

  test('server errors read as what the user can do next', () {
    expect(
      friendlyError(
        const PostgrestException(message: 'invalid_plate', code: '22023'),
      ),
      '차량 번호를 확인해 주세요. 예: 123가 4567',
    );
    // Sign-in is Apple or Google only: nothing to type, nothing to re-enter.
    for (final error in const [
      AuthException('Invalid login', code: 'invalid_credentials'),
      AuthException('Email not confirmed', code: 'email_not_confirmed'),
      AuthException('private detail', statusCode: '500'),
    ]) {
      expect(friendlyError(error), '로그인을 완료하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
    // One invitation is for one person: say so and what to ask the family for.
    expect(
      friendlyError(const InvalidInviteException()),
      '이미 사용했거나 24시간이 지난 초대예요. 가족에게 새 초대를 받아 주세요.',
    );
  });

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

  testWidgets(
    'customer support shows selectable contacts and copies exact values',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = DemoParkingRepository(preferences);
      await repository.initialize();
      final controller = AppController(repository);
      addTearDown(controller.dispose);
      String? clipboard;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String;
            }
            if (call.method == 'Clipboard.getData') return {'text': clipboard};
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsScreen(
                controller: controller,
                preferences: preferences,
                onLogout: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('고객지원'));
      await tester.tap(find.text('고객지원'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.widgetWithText(SelectableText, 'kang88xx@gmail.com'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(
          SelectableText,
          'https://kang88xx.github.io/carcar-kang88/support/',
        ),
        findsOneWidget,
      );
      expect(clipboard, isNull);
      await tester.tap(find.text('이메일 복사'));
      await tester.pumpAndSettle();
      expect(
        (await Clipboard.getData(Clipboard.kTextPlain))?.text,
        'kang88xx@gmail.com',
      );
      await tester.tap(find.text('고객지원 링크 복사'));
      await tester.pumpAndSettle();
      expect(
        (await Clipboard.getData(Clipboard.kTextPlain))?.text,
        'https://kang88xx.github.io/carcar-kang88/support/',
      );
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
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
