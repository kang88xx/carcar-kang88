import 'dart:async';
import 'package:carcar/core/models.dart';
import 'package:carcar/core/invite_links.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/main.dart';
import 'package:carcar/features/auth_screen.dart';
import 'package:carcar/shared/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TestAuth implements GoTrueClient {
  final events = StreamController<AuthState>.broadcast();
  Session? session;
  AuthChangeEvent lastEvent = AuthChangeEvent.initialSession;
  @override
  Session? get currentSession => session;
  @override
  User? get currentUser => session?.user;
  @override
  Stream<AuthState> get onAuthStateChange =>
      Stream<AuthState>.multi((listener) {
        listener.add(AuthState(lastEvent, session));
        final subscription = events.stream.listen(
          listener.add,
          onError: listener.addError,
          onDone: listener.close,
        );
        listener.onCancel = subscription.cancel;
      });
  void signInAs(String id, {AuthChangeEvent event = AuthChangeEvent.signedIn}) {
    session = Session(
      accessToken: 'test-token',
      tokenType: 'bearer',
      user: User(
        id: id,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );
    lastEvent = event;
    events.add(AuthState(event, session));
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {
    session = null;
    lastEvent = AuthChangeEvent.signedOut;
    events.add(AuthState(lastEvent, null));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  void dispose() {
    events.close();
  }
}

class TestClient implements SupabaseClient {
  TestClient(this.testAuth);
  final TestAuth testAuth;
  @override
  GoTrueClient get auth => testAuth;
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SessionRepository implements ParkingRepository {
  SessionRepository(this.userId, {this.empty = false});
  @override
  final String userId;
  final bool empty;
  bool disposed = false;
  @override
  bool get isDemo => false;
  @override
  String? get accountName => null;
  @override
  Future<List<Vehicle>> vehicles() async => empty
      ? []
      : [
          Vehicle(
            id: 'car-$userId',
            ownerId: userId,
            name: '$userId 전용 차량',
            plate: '12가 3456',
            apartment: '집',
            latestId: 'record-$userId',
          ),
        ];
  @override
  Future<List<ParkingRecord>> records(String vehicleId) async => [
    ParkingRecord(
      id: 'record-$userId',
      vehicleId: vehicleId,
      floor: 'B1',
      zone: 'A',
      spot: '1',
      note: '$userId 비공개 메모',
      createdBy: userId,
      createdAt: DateTime(2026),
    ),
  ];
  @override
  Future<List<FamilyMember>> members(String vehicleId) async => [
    FamilyMember(id: userId, name: userId, owner: true),
  ];
  @override
  void watch(void Function() onChange) {}
  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class OfflineRepository extends SessionRepository {
  OfflineRepository(super.userId, {super.empty});
  bool offline = true;
  @override
  Future<List<Vehicle>> vehicles() async {
    if (offline) throw StateError('offline');
    return super.vehicles();
  }
}

const lastUserKey = 'carcar.session.user';

List<String> trackNativeCalls({bool failCleanup = false}) {
  final calls = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('carcar/native'), (
        call,
      ) async {
        calls.add(call.method);
        if (failCleanup && call.method == 'clearSnapshot') {
          throw PlatformException(code: 'cleanup_failed');
        }
        return null;
      });
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('same user restart keeps widget, finding display and push', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({lastUserKey: 'A'});
    final preferences = await SharedPreferences.getInstance();
    final auth = TestAuth()
      ..signInAs('A', event: AuthChangeEvent.initialSession);
    final calls = trackNativeCalls();
    await tester.pumpWidget(
      CarcarApp(
        preferences: preferences,
        client: TestClient(auth),
        repositoryFactory: (c) => SessionRepository(c.auth.currentUser!.id),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A 전용 차량'), findsOneWidget);
    expect(calls, isNot(contains('clearSnapshot')));
    expect(calls, isNot(contains('disablePush')));
    expect(calls, isNot(contains('stopFinding')));
    expect(preferences.getString(lastUserKey), 'A');
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });
  testWidgets('restart as a different user cleans before opening home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({lastUserKey: 'A'});
    final preferences = await SharedPreferences.getInstance();
    final auth = TestAuth()
      ..signInAs('B', event: AuthChangeEvent.initialSession);
    final calls = trackNativeCalls();
    var callsBeforeRepository = <String>[];
    await tester.pumpWidget(
      CarcarApp(
        preferences: preferences,
        client: TestClient(auth),
        repositoryFactory: (c) {
          callsBeforeRepository = List.of(calls);
          return SessionRepository(c.auth.currentUser!.id);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(
      callsBeforeRepository,
      containsAll(['clearSnapshot', 'disablePush']),
    );
    expect(find.text('B 전용 차량'), findsOneWidget);
    expect(preferences.getString(lastUserKey), 'B');
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });
  testWidgets('logout cleans the device and forgets the stored user', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final auth = TestAuth();
    final calls = trackNativeCalls();
    await tester.pumpWidget(
      CarcarApp(
        preferences: preferences,
        client: TestClient(auth),
        repositoryFactory: (c) => SessionRepository(c.auth.currentUser!.id),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    auth.signInAs('A');
    await tester.pumpAndSettle();
    expect(calls, containsAll(['clearSnapshot', 'disablePush']));
    expect(preferences.getString(lastUserKey), 'A');
    calls.clear();
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(calls, containsAll(['clearSnapshot', 'disablePush']));
    expect(preferences.getString(lastUserKey), isNull);
    // The same user signing in again after a logout is cleaned like anyone.
    calls.clear();
    auth.signInAs('A');
    await tester.pumpAndSettle();
    expect(calls, containsAll(['clearSnapshot', 'disablePush']));
    expect(find.text('A 전용 차량'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });
  testWidgets('unconfirmed cleanup never records the user as cleaned', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({lastUserKey: 'A'});
    final preferences = await SharedPreferences.getInstance();
    final auth = TestAuth()
      ..signInAs('B', event: AuthChangeEvent.initialSession);
    final calls = trackNativeCalls(failCleanup: true);
    await tester.pumpWidget(
      CarcarApp(
        preferences: preferences,
        client: TestClient(auth),
        repositoryFactory: (c) => SessionRepository(c.auth.currentUser!.id),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, contains('clearSnapshot'));
    expect(find.text('B 전용 차량'), findsOneWidget);
    expect(preferences.getString(lastUserKey), isNull);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });
  testWidgets('signing in shows progress, not the login screen, until home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = TestAuth();
    final cleanup = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('carcar/native'), (
          call,
        ) async {
          if (call.method == 'clearSnapshot') await cleanup.future;
          return null;
        });
    await tester.pumpWidget(
      CarcarApp(
        preferences: await SharedPreferences.getInstance(),
        client: TestClient(auth),
        repositoryFactory: (c) => SessionRepository(c.auth.currentUser!.id),
      ),
    );
    await tester.pump();
    expect(find.byType(AuthScreen), findsOneWidget);
    // Back from the provider with a session; the device is still being
    // prepared for this account.
    auth.signInAs('A');
    await tester.pump();
    await tester.pump();
    expect(find.byType(AuthScreen), findsNothing);
    expect(find.text('Google로 계속하기'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Progress is not success: no home content before it is loaded.
    expect(find.text('A 전용 차량'), findsNothing);
    cleanup.complete();
    await tester.pumpAndSettle();
    expect(find.text('A 전용 차량'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });
  testWidgets('opening the app signed in never flashes the login screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({lastUserKey: 'A'});
    final auth = TestAuth()
      ..signInAs('A', event: AuthChangeEvent.initialSession);
    trackNativeCalls();
    await tester.pumpWidget(
      CarcarApp(
        preferences: await SharedPreferences.getInstance(),
        client: TestClient(auth),
        repositoryFactory: (c) => SessionRepository(c.auth.currentUser!.id),
      ),
    );
    // First frame, before the stored session has been delivered.
    expect(find.byType(AuthScreen), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('A 전용 차량'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });
  testWidgets('starting the demo forgets the stored user', (tester) async {
    SharedPreferences.setMockInitialValues({lastUserKey: 'A'});
    final preferences = await SharedPreferences.getInstance();
    trackNativeCalls();
    await tester.pumpWidget(CarcarApp(preferences: preferences));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('체험 시작하기'));
    await tester.tap(find.text('체험 시작하기'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsNothing);
    expect(preferences.getString(lastUserKey), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('A to B auth event clears A cache before B becomes visible', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = TestAuth()..signInAs('A');
    final client = TestClient(auth);
    final repos = <SessionRepository>[];
    var clearCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('carcar/native'), (
          call,
        ) async {
          if (call.method == 'clearSnapshot') clearCount++;
          return null;
        });
    await tester.pumpWidget(
      CarcarApp(
        preferences: await SharedPreferences.getInstance(),
        client: client,
        repositoryFactory: (c) {
          final repo = SessionRepository(c.auth.currentUser!.id);
          repos.add(repo);
          return repo;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A 전용 차량'), findsOneWidget);
    auth.signInAs('B');
    await tester.pumpAndSettle();
    expect(find.text('A 전용 차량'), findsNothing);
    expect(find.text('A 비공개 메모'), findsNothing);
    expect(find.text('B 전용 차량'), findsOneWidget);
    expect(repos.first.disposed, isTrue);
    expect(clearCount, greaterThanOrEqualTo(1));
    await tester.pumpWidget(const SizedBox());
    await client.dispose();
    auth.dispose();
  });
  testWidgets(
    'account without a vehicle can still reach deletion and privacy',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final auth = TestAuth()..signInAs('A');
      final client = TestClient(auth);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('carcar/native'),
            (_) async => null,
          );
      await tester.pumpWidget(
        CarcarApp(
          preferences: await SharedPreferences.getInstance(),
          client: client,
          repositoryFactory: (c) =>
              SessionRepository(c.auth.currentUser!.id, empty: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('우리 가족의 차 한 대'), findsOneWidget);
      await tester.tap(find.text('설정'));
      await tester.pumpAndSettle();
      expect(find.text('개인정보 처리 안내'), findsOneWidget);
      expect(find.text('계정 삭제'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await client.dispose();
      auth.dispose();
    },
  );
  for (final empty in [false, true]) {
    testWidgets('failed first load offers retry, not first-run onboarding '
        '(${empty ? 'no vehicle' : 'existing vehicle'})', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final auth = TestAuth()..signInAs('A');
      trackNativeCalls();
      late OfflineRepository repository;
      await tester.pumpWidget(
        CarcarApp(
          preferences: await SharedPreferences.getInstance(),
          client: TestClient(auth),
          repositoryFactory: (c) => repository = OfflineRepository(
            c.auth.currentUser!.id,
            empty: empty,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('주차 위치를 불러오지 못했어요'), findsOneWidget);
      expect(find.text('연결을 확인한 뒤 다시 시도해 주세요.'), findsOneWidget);
      expect(find.text('우리 가족의 차 한 대'), findsNothing);
      expect(find.text('새 차량 등록'), findsNothing);
      expect(find.text('받은 초대로 참여'), findsNothing);
      // One message for one problem: the banner does not repeat it.
      expect(find.byType(StatusNotice), findsNothing);
      // Settings, and with them logout, stay reachable while offline.
      await tester.tap(find.text('설정'));
      await tester.pumpAndSettle();
      expect(find.text('로그아웃'), findsOneWidget);
      await tester.tap(find.text('주차 위치'));
      await tester.pumpAndSettle();
      repository.offline = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('주차 위치를 불러오지 못했어요'), findsNothing);
      expect(find.text('새 차량 등록'), empty ? findsOneWidget : findsNothing);
      expect(find.text('A 전용 차량'), empty ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    });
  }
  testWidgets('a failed reload after a first load keeps the first-run card', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = TestAuth()..signInAs('A');
    trackNativeCalls();
    late OfflineRepository repository;
    await tester.pumpWidget(
      CarcarApp(
        preferences: await SharedPreferences.getInstance(),
        client: TestClient(auth),
        repositoryFactory: (c) =>
            repository = OfflineRepository(c.auth.currentUser!.id, empty: true)
              ..offline = false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('우리 가족의 차 한 대'), findsOneWidget);
    repository.offline = true;
    await tester.tap(find.byTooltip('최신 위치 새로고침'));
    await tester.pumpAndSettle();
    // "No vehicle" was confirmed once, so the way in stays under the error.
    expect(
      find.widgetWithText(StatusNotice, '연결이 불안정해요. 다시 시도해 주세요.'),
      findsOneWidget,
    );
    expect(find.text('주차 위치를 불러오지 못했어요'), findsNothing);
    expect(find.text('우리 가족의 차 한 대'), findsOneWidget);
    expect(find.text('새 차량 등록'), findsOneWidget);
    expect(find.text('받은 초대로 참여'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });
  testWidgets('cold recovery link opens password form before private home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = TestAuth()
      ..signInAs('A', event: AuthChangeEvent.passwordRecovery);
    var repositoriesOpened = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('carcar/native'),
          (_) async => null,
        );
    await tester.pumpWidget(
      CarcarApp(
        preferences: await SharedPreferences.getInstance(),
        client: TestClient(auth),
        repositoryFactory: (client) {
          repositoriesOpened++;
          return SessionRepository(client.auth.currentUser!.id);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PasswordRecoveryScreen), findsOneWidget);
    expect(repositoriesOpened, 0);
    auth.events.add(AuthState(AuthChangeEvent.userUpdated, auth.session));
    await tester.pumpAndSettle();
    expect(find.byType(PasswordRecoveryScreen), findsOneWidget);
    expect(repositoriesOpened, 0);
    final recovery = tester.widget<PasswordRecoveryScreen>(
      find.byType(PasswordRecoveryScreen),
    );
    await recovery.onCancel();
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(auth.currentSession, isNull);
    expect(find.text('A 전용 차량'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });
  testWidgets(
    'account change dismisses registration and preserves pending invitation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final code = 'a' * 48;
      final auth = TestAuth();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('carcar/native'),
            (_) async => null,
          );
      await tester.pumpWidget(
        CarcarApp(
          preferences: preferences,
          client: TestClient(auth),
          initialLink: () async => Uri.parse(inviteLink(code)),
          incomingLinks: const Stream<Uri>.empty(),
          repositoryFactory: (client) =>
              SessionRepository(client.auth.currentUser!.id, empty: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(PendingInvite(preferences).code, code);
      auth.signInAs('A');
      await tester.pumpAndSettle();
      expect(find.text('가족 초대를 받았어요'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.text('새 차량 등록'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      auth.signInAs('B');
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(PendingInvite(preferences).code, code);
      expect(find.text('가족 초대를 받았어요'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    },
  );
  testWidgets('auth stream network errors do not crash the signed-in app', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = TestAuth()..signInAs('A');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('carcar/native'),
          (_) async => null,
        );
    await tester.pumpWidget(
      CarcarApp(
        preferences: await SharedPreferences.getInstance(),
        client: TestClient(auth),
        repositoryFactory: (client) =>
            SessionRepository(client.auth.currentUser!.id),
      ),
    );
    await tester.pumpAndSettle();
    auth.events.addError(const AuthException('temporary network error'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('A 전용 차량'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });
}
