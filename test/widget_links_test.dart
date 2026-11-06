import 'dart:async';
import 'package:carcar/core/models.dart';
import 'package:carcar/core/widget_links.dart';
import 'package:carcar/features/auth_screen.dart';
import 'package:carcar/features/parking_form.dart';
import 'package:carcar/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_test.dart' show TestAuth, TestClient, SessionRepository;
import 'widget_access_test.dart' show WidgetRepository;

class DelayedVehicleRepository extends SessionRepository {
  DelayedVehicleRepository(super.userId);
  final ready = Completer<void>();

  @override
  Future<List<Vehicle>> vehicles() async {
    await ready.future;
    return super.vehicles();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const parkingUrl = 'carcar://parking';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('carcar/native'),
          (_) async => null,
        );
  });

  Future<void> start(
    WidgetTester tester, {
    required TestAuth auth,
    Stream<Uri> links = const Stream<Uri>.empty(),
    Future<Uri?> Function()? initialLink,
    SessionRepository Function(String userId)? repository,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      CarcarApp(
        preferences: await SharedPreferences.getInstance(),
        client: TestClient(auth),
        incomingLinks: links,
        initialLink: initialLink ?? () async => null,
        repositoryFactory: (client) =>
            (repository ?? SessionRepository.new)(client.auth.currentUser!.id),
      ),
    );
  }

  test('widget URLs only navigate to the two explicit app destinations', () {
    expect(parseWidgetLink(Uri.parse(parkingUrl)), WidgetDestination.parking);
    expect(
      parseWidgetLink(Uri.parse('carcar://parking/')),
      WidgetDestination.parking,
    );
    expect(parseWidgetLink(Uri.parse('carcar://home')), WidgetDestination.home);
    for (final value in [
      'https://parking',
      'com.kang88.carcar://login-callback',
      'carcar://save',
      'carcar://parking/other',
      'carcar://user@parking',
      'carcar://parking:80',
      'carcar://parking?vehicle=other',
      'carcar://parking#save',
    ]) {
      expect(parseWidgetLink(Uri.parse(value)), isNull, reason: value);
    }
  });

  testWidgets('cold parking link waits for the authenticated vehicle to load', (
    tester,
  ) async {
    final auth = TestAuth()..signInAs('A');
    final repository = DelayedVehicleRepository('A');
    await start(
      tester,
      auth: auth,
      initialLink: () async => Uri.parse(parkingUrl),
      repository: (_) => repository,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ParkingForm), findsNothing);
    repository.ready.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ParkingForm), findsOneWidget);
    expect(
      tester
          .widget<ParkingForm>(find.byType(ParkingForm))
          .controller
          .repository
          .userId,
      'A',
    );
    expect(find.text('어디에 주차했나요?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });

  testWidgets(
    'warm parking links open one form and preserve an existing draft',
    (tester) async {
      final auth = TestAuth()..signInAs('A');
      final links = StreamController<Uri>.broadcast();
      await start(tester, auth: auth, links: links.stream);
      await tester.pumpAndSettle();
      await tester.tap(find.text('설정'));
      await tester.pumpAndSettle();
      links.add(Uri.parse(parkingUrl));
      await tester.pumpAndSettle();
      expect(find.byType(ParkingForm), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, '주차 번호 (선택)'),
        '73',
      );
      links.add(Uri.parse(parkingUrl));
      links.add(Uri.parse(parkingUrl));
      await tester.pumpAndSettle();
      expect(find.byType(ParkingForm), findsOneWidget);
      expect(find.text('73'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await links.close();
      auth.dispose();
    },
  );

  testWidgets('home link selects home without saving or opening the form', (
    tester,
  ) async {
    final auth = TestAuth()..signInAs('A');
    final links = StreamController<Uri>.broadcast();
    await start(tester, auth: auth, links: links.stream);
    await tester.pumpAndSettle();
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    links.add(Uri.parse('carcar://home'));
    await tester.pumpAndSettle();
    expect(find.text('마지막 주차 위치'), findsOneWidget);
    expect(find.byType(ParkingForm), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await links.close();
    auth.dispose();
  });

  testWidgets('signed-out parking link waits for explicit login', (
    tester,
  ) async {
    final auth = TestAuth();
    await start(
      tester,
      auth: auth,
      initialLink: () async => Uri.parse(parkingUrl),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byType(ParkingForm), findsNothing);
    auth.signInAs('A');
    await tester.pumpAndSettle();
    expect(find.byType(ParkingForm), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });

  testWidgets(
    'pending link without a vehicle does not cross an account change',
    (tester) async {
      final auth = TestAuth()..signInAs('A');
      await start(
        tester,
        auth: auth,
        initialLink: () async => Uri.parse(parkingUrl),
        repository: (id) => SessionRepository(id, empty: id == 'A'),
      );
      await tester.pumpAndSettle();
      expect(find.text('새 차량 등록'), findsOneWidget);
      expect(find.byType(ParkingForm), findsNothing);
      auth.signInAs('B');
      await tester.pumpAndSettle();
      expect(find.text('B 전용 차량'), findsOneWidget);
      expect(find.byType(ParkingForm), findsNothing);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    },
  );

  testWidgets('logout closes linked form and does not replay it after login', (
    tester,
  ) async {
    final auth = TestAuth()..signInAs('A');
    await start(
      tester,
      auth: auth,
      initialLink: () async => Uri.parse(parkingUrl),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ParkingForm), findsOneWidget);
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byType(ParkingForm), findsNothing);
    auth.signInAs('B');
    await tester.pumpAndSettle();
    expect(find.byType(ParkingForm), findsNothing);
    expect(find.text('B 전용 차량'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });

  testWidgets('late initial link is ignored after the original session ends', (
    tester,
  ) async {
    final auth = TestAuth()..signInAs('A');
    final initial = Completer<Uri?>();
    await start(tester, auth: auth, initialLink: () => initial.future);
    await tester.pumpAndSettle();
    await auth.signOut();
    await tester.pumpAndSettle();
    auth.signInAs('B');
    await tester.pumpAndSettle();
    initial.complete(Uri.parse(parkingUrl));
    await tester.pumpAndSettle();
    expect(find.text('B 전용 차량'), findsOneWidget);
    expect(find.byType(ParkingForm), findsNothing);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });

  testWidgets('native demo receives widget links without a Supabase client', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const messages = MethodChannel('com.llfbandit.app_links/messages');
    const events = MethodChannel('com.llfbandit.app_links/events');
    messenger.setMockMethodCallHandler(messages, (_) async => parkingUrl);
    messenger.setMockMethodCallHandler(events, (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(messages, null);
      messenger.setMockMethodCallHandler(events, null);
    });
    await tester.pumpWidget(
      CarcarApp(preferences: await SharedPreferences.getInstance()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ParkingForm), findsNothing);
    await tester.ensureVisible(find.text('체험 시작하기'));
    await tester.tap(find.text('체험 시작하기'));
    await tester.pumpAndSettle();
    expect(find.byType(ParkingForm), findsOneWidget);
    expect(
      tester.widget<ParkingForm>(find.byType(ParkingForm)).controller.isDemo,
      isTrue,
    );
    expect(find.text('체험 기록 저장'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'existing direct-save permission can be revoked but not re-enabled',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'carcar.widget.quick_save.owner': true,
      });
      final preferences = await SharedPreferences.getInstance();
      final auth = TestAuth()..signInAs('owner');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('carcar/native'), (
            call,
          ) async {
            calls.add(call.method);
            if (call.method == 'launcherIconState') return {'supported': false};
            return null;
          });
      await tester.pumpWidget(
        CarcarApp(
          preferences: preferences,
          client: TestClient(auth),
          incomingLinks: const Stream<Uri>.empty(),
          initialLink: () async => null,
          repositoryFactory: (_) => WidgetRepository(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('설정'));
      await tester.pumpAndSettle();
      final legacy = find.widgetWithText(SwitchListTile, '이전 위젯의 저장 권한');
      await tester.scrollUntilVisible(
        legacy,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(legacy).value, isTrue);
      calls.clear();
      await tester.tap(legacy);
      await tester.pumpAndSettle();
      expect(calls, contains('clearWidgetSession'));
      expect(preferences.getBool('carcar.widget.quick_save.owner'), isFalse);
      expect(legacy, findsNothing);
      expect(find.text('위젯에서 바로 기록'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    },
  );
}
