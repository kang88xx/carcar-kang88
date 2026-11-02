import 'dart:async';
import 'package:carcar/core/models.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/main.dart';
import 'package:carcar/features/auth_screen.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
      expect(find.text('우리 차를 등록해 볼까요?'), findsOneWidget);
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
