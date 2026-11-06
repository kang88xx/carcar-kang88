import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:carcar/app/theme.dart';
import 'package:carcar/core/native_bridge.dart';
import 'package:carcar/features/auth_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RealHttpOverrides extends HttpOverrides {}

const _token = 'eyJhbGciOiJSUzI1NiJ9.e30.c2ln';
final _nonce = List.filled(64, 'a').join();
final _credential = AppleCredential(
  identityToken: _token,
  authorizationCode: 'single-use-code',
  userIdentifier: 'apple-user',
  rawNonce: _nonce,
  fullName: '가족',
);

Session _session(String id) => Session(
  accessToken:
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.c2ln',
  refreshToken: 'refresh-$id',
  tokenType: 'bearer',
  user: User(
    id: id,
    appMetadata: const {},
    userMetadata: const {'full_name': '기존 이름'},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);

class AppleAuth implements GoTrueClient {
  Session? session;
  Completer<void>? pending;
  Session? responseSession;
  final events = StreamController<AuthState>.broadcast(sync: true);
  @override
  Stream<AuthState> get onAuthStateChange => events.stream;
  @override
  void dispose() {}
  @override
  Future<AuthResponse> recoverSession(String value) async {
    session = Session.fromJson(jsonDecode(value));
    return AuthResponse(session: session);
  }

  Object? error;
  bool omitSession = false;
  int requests = 0;
  OAuthProvider? provider;
  String? idToken, nonce;

  @override
  User? get currentUser => session?.user;
  @override
  Session? get currentSession => session;

  @override
  Future<AuthResponse> signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
    String? captchaToken,
  }) async {
    requests++;
    this.provider = provider;
    this.idToken = idToken;
    this.nonce = nonce;
    if (error != null) throw error!;
    if (omitSession) return AuthResponse();
    await pending?.future;
    return AuthResponse(session: responseSession ?? _session('apple-owner'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AppleClient implements SupabaseClient {
  AppleClient(this.testAuth);
  final AppleAuth testAuth;
  @override
  GoTrueClient get auth => testAuth;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('carcar/native');

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required AppleAuth auth,
    Future<AppleCredential?> Function()? apple,
    Future<bool> Function()? google,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AuthScreen(
          client: AppleClient(auth),
          onDemo: () async {},
          onAppleSignIn: apple,
          createAppleAuth: () => auth,
          onGoogleSignIn: google,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Apple login is offered beside Google only on iOS',
    (tester) async {
      await pumpPage(tester, auth: AppleAuth());
      expect(
        find.text('Apple로 계속하기'),
        defaultTargetPlatform == TargetPlatform.iOS
            ? findsOneWidget
            : findsNothing,
      );
      expect(find.text('Google로 계속하기'), findsOneWidget);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'Apple sheet cancellation leaves login available without a session',
    (tester) async {
      final auth = AppleAuth();
      await pumpPage(tester, auth: auth, apple: () async => null);
      await tester.tap(find.text('Apple로 계속하기'));
      await tester.pumpAndSettle();
      expect(auth.requests, 0);
      expect(auth.currentSession, isNull);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Apple로 계속하기'),
                matching: find.byWidgetPredicate(
                  (widget) => widget is FilledButton,
                ),
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.textContaining('완료하지 못했어요'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Apple credentials and raw nonce reach Supabase without changing names',
    (tester) async {
      final auth = AppleAuth();
      await pumpPage(tester, auth: auth, apple: () async => _credential);
      await tester.tap(find.text('Apple로 계속하기'));
      await tester.pumpAndSettle();
      expect(auth.requests, 1);
      expect(auth.provider, OAuthProvider.apple);
      expect(auth.idToken, _token);
      expect(auth.nonce, _nonce);
      expect(auth.currentSession?.user.userMetadata?['full_name'], '기존 이름');
      expect(find.textContaining('확인하지 못했어요'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('native errors hide credentials and allow a retry', (
    tester,
  ) async {
    final auth = AppleAuth();
    var attempts = 0;
    await pumpPage(
      tester,
      auth: auth,
      apple: () async {
        if (++attempts == 1) {
          throw PlatformException(code: 'failed', message: 'secret $_token');
        }
        return _credential;
      },
    );
    await tester.tap(find.text('Apple로 계속하기'));
    await tester.pumpAndSettle();
    expect(auth.requests, 0);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining(_token), findsNothing);
    expect(find.textContaining('다시 시도해 주세요'), findsOneWidget);
    await tester.tap(find.text('Apple로 계속하기'));
    await tester.pumpAndSettle();
    expect(auth.requests, 1);
    expect(find.textContaining('다시 시도해 주세요'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Supabase failure is not reported as successful Apple login', (
    tester,
  ) async {
    final auth = AppleAuth()..error = const AuthException('private-detail');
    await pumpPage(tester, auth: auth, apple: () async => _credential);
    await tester.tap(find.text('Apple로 계속하기'));
    await tester.pumpAndSettle();
    expect(auth.currentSession, isNull);
    expect(find.textContaining('private-detail'), findsNothing);
    expect(find.textContaining('로그인 요청을 완료하지 못했어요'), findsOneWidget);
    auth.error = null;
    await tester.tap(find.text('Apple로 계속하기'));
    await tester.pumpAndSettle();
    expect(auth.requests, 2);
    expect(auth.currentSession, isNotNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('missing server session is rejected', (tester) async {
    final auth = AppleAuth()..omitSession = true;
    await pumpPage(tester, auth: auth, apple: () async => _credential);
    await tester.tap(find.text('Apple로 계속하기'));
    await tester.pumpAndSettle();
    expect(find.text('Apple 로그인을 확인하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('pending Apple request blocks Apple and Google duplicates', (
    tester,
  ) async {
    final pending = Completer<AppleCredential?>();
    var appleRequests = 0, googleRequests = 0;
    await pumpPage(
      tester,
      auth: AppleAuth(),
      apple: () {
        appleRequests++;
        return pending.future;
      },
      google: () async {
        googleRequests++;
        return true;
      },
    );
    await tester.tap(find.text('Apple로 계속하기'));
    await tester.pump();
    await tester.tap(find.text('Apple로 계속하기'));
    await tester.tap(find.text('Google로 계속하기'));
    expect(appleRequests, 1);
    expect(googleRequests, 0);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.ancestor(
              of: find.text('Google로 계속하기'),
              matching: find.byWidgetPredicate(
                (widget) => widget is OutlinedButton,
              ),
            ),
          )
          .onPressed,
      isNotNull,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('pending Google launch blocks Apple authentication', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var appleRequests = 0;
    await pumpPage(
      tester,
      auth: AppleAuth(),
      google: () => pending.future,
      apple: () async {
        appleRequests++;
        return _credential;
      },
    );
    await tester.tap(find.text('Google로 계속하기'));
    await tester.pump();
    await tester.tap(find.text('Apple로 계속하기'));
    expect(appleRequests, 0);
    pending.complete(true);
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'late native credential cannot replace a newly signed-in account',
    (tester) async {
      final auth = AppleAuth();
      final pending = Completer<AppleCredential?>();
      await pumpPage(tester, auth: auth, apple: () => pending.future);
      await tester.tap(find.text('Apple로 계속하기'));
      await tester.pump();
      auth.session = _session('other-owner');
      pending.complete(_credential);
      await tester.pumpAndSettle();
      expect(auth.requests, 0);
      expect(auth.currentUser?.id, 'other-owner');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('disposed login ignores a late native credential', (
    tester,
  ) async {
    final auth = AppleAuth();
    final pending = Completer<AppleCredential?>();
    await pumpPage(tester, auth: auth, apple: () => pending.future);
    await tester.tap(find.text('Apple로 계속하기'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(_credential);
    await tester.pumpAndSettle();
    expect(auth.requests, 0);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  for (final transition in ['other-user', 'login-logout', 'dispose']) {
    testWidgets('pending token exchange ignores $transition', (tester) async {
      final auth = AppleAuth()..pending = Completer<void>();
      await pumpPage(tester, auth: auth, apple: () async => _credential);
      await tester.tap(find.text('Apple로 계속하기'));
      await tester.pump();
      expect(auth.requests, 1);
      if (transition == 'dispose') {
        await tester.pumpWidget(const SizedBox());
      } else {
        auth.session = _session('other-owner');
        auth.events.add(AuthState(AuthChangeEvent.signedIn, auth.session));
        if (transition == 'login-logout') auth.session = null;
      }
      auth.pending!.complete();
      await tester.pumpAndSettle();
      expect(
        auth.currentUser?.id,
        transition == 'other-user' ? 'other-owner' : null,
      );
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }

  testWidgets(
    'client replacement releases busy state and ignores old response',
    (tester) async {
      final oldAuth = AppleAuth()..pending = Completer<void>();
      await pumpPage(tester, auth: oldAuth, apple: () async => _credential);
      await tester.tap(find.text('Apple로 계속하기'));
      await tester.pump();
      final next = AppleAuth();
      await pumpPage(tester, auth: next, apple: () async => _credential);
      await tester.tap(find.text('Apple로 계속하기'));
      await tester.pumpAndSettle();
      expect(next.currentUser?.id, 'apple-owner');
      oldAuth.pending!.complete();
      await tester.pumpAndSettle();
      expect(oldAuth.currentSession, isNull);
      expect(next.currentUser?.id, 'apple-owner');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  for (final invalid in ['refresh', 'expired']) {
    testWidgets('invalid $invalid session is never adopted', (tester) async {
      final fresh = _session('apple-owner');
      final session = Session(
        accessToken: fresh.accessToken,
        tokenType: 'bearer',
        user: fresh.user,
        refreshToken: invalid == 'refresh' ? null : 'refresh',
      );
      if (invalid == 'expired') session.expiresAt = 1;
      final auth = AppleAuth()..responseSession = session;
      await pumpPage(tester, auth: auth, apple: () async => _credential);
      await tester.tap(find.text('Apple로 계속하기'));
      await tester.pumpAndSettle();
      expect(auth.currentSession, isNull);
      expect(find.text('Apple 로그인을 확인하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }

  for (final switchAccount in [false, true]) {
    testWidgets(
      'real SDK exchange with replay and account switch=$switchAccount',
      (tester) async {
        await tester.runAsync(
          () => HttpOverrides.runWithHttpOverrides(() async {
            final server = await HttpServer.bind(
              InternetAddress.loopbackIPv4,
              0,
            );
            final received = Completer<void>();
            final release = Completer<void>();
            final shared = SupabaseClient(
              'http://127.0.0.1:${server.port}',
              'public-test-key',
              authOptions: const AuthClientOptions(autoRefreshToken: false),
            );
            // Seed the ReplaySubject before the login screen subscribes.
            await shared.auth.signOut(scope: SignOutScope.local);
            server.listen((request) async {
              final body = jsonDecode(await utf8.decoder.bind(request).join());
              expect(request.uri.queryParameters['grant_type'], 'id_token');
              expect(body['nonce'], _nonce);
              received.complete();
              await release.future;
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode(_session('apple-owner').toJson()),
              );
              await request.response.close();
            });
            try {
              tester.view.physicalSize = const Size(1200, 1600);
              tester.view.devicePixelRatio = 1;
              await tester.pumpWidget(
                MaterialApp(
                  theme: buildTheme(),
                  home: AuthScreen(
                    client: shared,
                    onDemo: () async {},
                    onAppleSignIn: () async => _credential,
                    createAppleAuth: () => GoTrueClient(
                      url: 'http://127.0.0.1:${server.port}/auth/v1',
                      headers: {'apikey': 'public-test-key'},
                      autoRefreshToken: false,
                    ),
                  ),
                ),
              );
              await Future<void>.delayed(Duration.zero);
              await tester.pump();
              await tester.tap(find.text('Apple로 계속하기'));
              await received.future.timeout(const Duration(seconds: 5));
              expect(shared.auth.currentSession, isNull);
              if (switchAccount) {
                await shared.auth.recoverSession(
                  jsonEncode(_session('other-owner').toJson()),
                );
              }
              release.complete();
              for (var i = 0; i < 50; i++) {
                await Future<void>.delayed(const Duration(milliseconds: 10));
                await tester.pump();
                final button = tester.widget<FilledButton>(
                  find.byWidgetPredicate((w) => w is FilledButton),
                );
                if (button.onPressed != null) break;
              }
              expect(
                shared.auth.currentUser?.id,
                switchAccount ? 'other-owner' : 'apple-owner',
              );
              await tester.pumpWidget(const SizedBox());
            } finally {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
              await shared.dispose();
              await server.close(force: true);
            }
          }, RealHttpOverrides()),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  test('native bridge returns complete ephemeral credentials', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'signInWithApple');
          expect(call.arguments, isNull);
          return {
            'identityToken': _token,
            'authorizationCode': 'one-use-code',
            'userIdentifier': 'apple-user',
            'rawNonce': _nonce,
            'fullName': ' 가족 ',
          };
        });
    final credential = await NativeBridge.signInWithApple();
    expect(credential?.identityToken, _token);
    expect(credential?.authorizationCode, 'one-use-code');
    expect(credential?.userIdentifier, 'apple-user');
    expect(credential?.rawNonce, _nonce);
    expect(credential?.fullName, '가족');
  });

  test('native bridge cancellation returns null', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    expect(await NativeBridge.signInWithApple(), isNull);
  });

  test(
    'malformed native credentials are rejected without exposing their values',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      for (final patch in [
        {'identityToken': ''},
        {'identityToken': 'private-invalid-token'},
        {'authorizationCode': ''},
        {'userIdentifier': ''},
        {'rawNonce': 'short'},
        {'fullName': 4},
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              channel,
              (_) async => {
                'identityToken': _token,
                'authorizationCode': 'one-use-code',
                'userIdentifier': 'apple-user',
                'rawNonce': _nonce,
                ...patch,
              },
            );
        await expectLater(
          NativeBridge.signInWithApple(),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'apple_credential_invalid',
            ),
          ),
        );
      }
    },
  );

  test(
    'unsupported platforms never invoke native Apple authentication',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            calls++;
            return null;
          });
      await expectLater(
        NativeBridge.signInWithApple(),
        throwsA(isA<PlatformException>()),
      );
      expect(calls, 0);
    },
  );
}
