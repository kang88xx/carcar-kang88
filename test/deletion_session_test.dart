import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:carcar/features/auth_screen.dart';
import 'package:carcar/features/shell.dart';
import 'package:carcar/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_test.dart' show SessionRepository, TestAuth, TestClient;

class _LogoutRepository extends SessionRepository {
  _LogoutRepository(super.userId, this.auth);
  final TestAuth auth;
  int signOutCalls = 0;
  Completer<void>? completion;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    await auth.signOut();
    await completion?.future;
  }
}

class _GatedStorage extends GotrueAsyncStorage {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String?> getItem({required String key}) async => null;
  @override
  Future<void> setItem({required String key, required String value}) async {}
  @override
  Future<void> removeItem({required String key}) async {
    entered.complete();
    await release.future;
  }
}

class _RealHttpOverrides extends HttpOverrides {}

Session _session(String id) => Session(
  accessToken:
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': id, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.c2ln',
  refreshToken: 'refresh-$id',
  tokenType: 'bearer',
  user: User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('carcar/native'),
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('carcar/native'), null);
  });

  Future<void> mount(
    WidgetTester tester,
    TestAuth auth, {
    List<_LogoutRepository>? repositories,
  }) async {
    await tester.pumpWidget(
      CarcarApp(
        preferences: await SharedPreferences.getInstance(),
        client: TestClient(auth),
        repositoryFactory: (_) {
          final repository = _LogoutRepository(auth.currentUser!.id, auth);
          repositories?.add(repository);
          return repository;
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final event in [
    AuthChangeEvent.signedOut,
    AuthChangeEvent.signedIn,
    AuthChangeEvent.passwordRecovery,
  ]) {
    testWidgets('obsolete $event from A leaves B signed in', (tester) async {
      final auth = TestAuth()..signInAs('A');
      final oldSession = auth.session;
      await mount(tester, auth);
      auth.signInAs('B');
      await tester.pumpAndSettle();
      final currentController = tester
          .widget<AppShell>(find.byType(AppShell))
          .controller;
      auth.events.add(
        AuthState(
          event,
          event == AuthChangeEvent.signedOut ? null : oldSession,
        ),
      );
      await tester.pumpAndSettle();
      expect(auth.currentUser?.id, 'B');
      expect(find.text('B 전용 차량'), findsOneWidget);
      expect(find.text('A 전용 차량'), findsNothing);
      expect(find.byType(PasswordRecoveryScreen), findsNothing);
      expect(
        tester.widget<AppShell>(find.byType(AppShell)).controller,
        same(currentController),
      );
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    });
  }

  testWidgets('late A deletion completion preserves B controller', (
    tester,
  ) async {
    final auth = TestAuth()..signInAs('A');
    await mount(tester, auth);
    final oldShell = tester.widget<AppShell>(find.byType(AppShell));
    auth.signInAs('B');
    await tester.pumpAndSettle();
    final currentController = tester
        .widget<AppShell>(find.byType(AppShell))
        .controller;
    await oldShell.onAccountDeleted!(oldShell.controller);
    await tester.pumpAndSettle();
    expect(auth.currentUser?.id, 'B');
    expect(find.text('B 전용 차량'), findsOneWidget);
    expect(
      tester.widget<AppShell>(find.byType(AppShell)).controller,
      same(currentController),
    );
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });

  testWidgets('account switch before logout resumes does not sign out B', (
    tester,
  ) async {
    final auth = TestAuth()..signInAs('A');
    final repositories = <_LogoutRepository>[];
    await mount(tester, auth, repositories: repositories);
    final oldShell = tester.widget<AppShell>(find.byType(AppShell));
    final logout = oldShell.onLogout();
    auth.signInAs('B');
    await logout;
    await tester.pumpAndSettle();
    expect(auth.currentUser?.id, 'B');
    expect(
      repositories.every((repository) => repository.signOutCalls == 0),
      isTrue,
    );
    expect(find.text('B 전용 차량'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });

  testWidgets('late A logout completion does not clear B', (tester) async {
    final auth = TestAuth()..signInAs('A');
    final repositories = <_LogoutRepository>[];
    await mount(tester, auth, repositories: repositories);
    final oldShell = tester.widget<AppShell>(find.byType(AppShell));
    final release = Completer<void>();
    repositories.single.completion = release;
    final logout = oldShell.onLogout();
    await tester.pumpAndSettle();
    expect(repositories.first.signOutCalls, 1);
    auth.signInAs('B');
    await tester.pumpAndSettle();
    release.complete();
    await logout;
    await tester.pumpAndSettle();
    expect(auth.currentUser?.id, 'B');
    expect(find.text('B 전용 차량'), findsOneWidget);
    expect(repositories.last.signOutCalls, 0);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });

  testWidgets(
    'real SDK delayed local sign-out retains newer B session and screen',
    (tester) async {
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final storage = _GatedStorage();
          final requests = <String?>[];
          server.listen((request) async {
            expect(request.uri.path, '/auth/v1/logout');
            requests.add(
              request.headers.value(HttpHeaders.authorizationHeader),
            );
            request.response.statusCode = HttpStatus.noContent;
            await request.response.close();
          });
          final client = SupabaseClient(
            'http://127.0.0.1:${server.port}',
            'public-test-key',
            authOptions: AuthClientOptions(
              autoRefreshToken: false,
              pkceAsyncStorage: storage,
            ),
          );
          try {
            final original = _session('A');
            await client.auth.recoverSession(jsonEncode(original.toJson()));
            await tester.pumpWidget(
              CarcarApp(
                preferences: await SharedPreferences.getInstance(),
                client: client,
                repositoryFactory: (_) =>
                    SessionRepository(client.auth.currentUser!.id),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('A 전용 차량'), findsOneWidget);
            final logout = client.auth.signOut(scope: SignOutScope.local);
            await storage.entered.future;
            expect(client.auth.currentSession, isNull);
            await client.auth.recoverSession(
              jsonEncode(_session('B').toJson()),
            );
            await tester.pumpAndSettle();
            expect(find.text('B 전용 차량'), findsOneWidget);
            final currentController = tester
                .widget<AppShell>(find.byType(AppShell))
                .controller;
            storage.release.complete();
            await logout;
            await tester.pumpAndSettle();
            expect(requests, ['Bearer ${original.accessToken}']);
            expect(client.auth.currentUser?.id, 'B');
            expect(find.text('B 전용 차량'), findsOneWidget);
            expect(
              tester.widget<AppShell>(find.byType(AppShell)).controller,
              same(currentController),
            );
          } finally {
            if (!storage.release.isCompleted) storage.release.complete();
            await tester.pumpWidget(const SizedBox());
            await client.dispose();
            await server.close(force: true);
          }
        }, _RealHttpOverrides()),
      );
    },
  );
}
