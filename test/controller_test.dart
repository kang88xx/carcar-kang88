import 'dart:async';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/models.dart';
import 'package:carcar/core/repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ControlledRepository implements ParkingRepository {
  @override
  bool get isDemo => false;
  @override
  String get userId => 'owner';
  List<Vehicle> available = [
    const Vehicle(
      id: 'car',
      ownerId: 'owner',
      name: '가족 차',
      plate: '12가 3456',
      apartment: '집',
      latestId: 'old',
    ),
  ];
  List<ParkingRecord> history = [
    ParkingRecord(
      id: 'old',
      vehicleId: 'car',
      floor: 'B1',
      zone: 'A',
      spot: '1',
      note: '',
      createdBy: 'owner',
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  ];
  Object? fetchError;
  Completer<ParkingRecord>? pendingSave;
  final keys = <String>[];
  int saveCalls = 0;
  @override
  Future<List<Vehicle>> vehicles() async {
    if (fetchError != null) throw fetchError!;
    return List.of(available);
  }

  @override
  Future<List<ParkingRecord>> records(String vehicleId) async =>
      history.where((record) => record.vehicleId == vehicleId).toList();
  @override
  Future<List<FamilyMember>> members(String vehicleId) async => [
    const FamilyMember(id: 'owner', name: '나', owner: true),
  ];
  @override
  Future<ParkingRecord> save(
    String vehicleId,
    ParkingDraft draft,
    String key,
  ) async {
    saveCalls++;
    keys.add(key);
    final saved = await pendingSave!.future;
    history = [saved, ...history];
    available = available
        .map(
          (vehicle) => vehicle.id == vehicleId
              ? vehicle.copyWith(latestId: saved.id)
              : vehicle,
        )
        .toList();
    return saved;
  }

  @override
  void watch(void Function() onChange) {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> signOut() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('carcar/native');
  const draft = ParkingDraft(floor: 'B2', zone: 'C', spot: '24');
  late ControlledRepository repository;
  late AppController controller;
  late List<String> nativeCalls;
  bool rejectSnapshot = false;
  ParkingRecord savedRecord() => ParkingRecord(
    id: 'new',
    vehicleId: 'car',
    floor: 'B2',
    zone: 'C',
    spot: '24',
    note: '',
    createdBy: 'owner',
    createdAt: DateTime.utc(2026, 11, 2),
  );
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    nativeCalls = [];
    rejectSnapshot = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call.method);
          if (rejectSnapshot && call.method == 'updateSnapshot') {
            throw PlatformException(code: 'widget_unavailable');
          }
          return null;
        });
    repository = ControlledRepository();
    controller = AppController(repository);
    await controller.initialize();
    nativeCalls.clear();
  });
  tearDown(() {
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'pending server response keeps the confirmed previous location',
    () async {
      repository.pendingSave = Completer<ParkingRecord>();
      final request = controller.save(draft);
      expect(controller.saving, isTrue);
      expect(controller.latest?.id, 'old');
      expect(nativeCalls, isEmpty);
      repository.pendingSave!.complete(savedRecord());
      final saved = await request;
      expect(saved.id, 'new');
      expect(controller.latest?.id, 'new');
      expect(controller.saving, isFalse);
    },
  );
  test(
    'network failure preserves last confirmed location and ends busy state',
    () async {
      repository.pendingSave = Completer<ParkingRecord>();
      final request = controller.save(draft);
      final expectation = expectLater(request, throwsA(isA<StateError>()));
      repository.pendingSave!.completeError(StateError('offline'));
      await expectation;
      expect(controller.latest?.id, 'old');
      expect(controller.records, hasLength(1));
      expect(controller.saving, isFalse);
      expect(nativeCalls, isEmpty);
    },
  );
  test(
    'retrying a failed unchanged draft reuses its idempotency key',
    () async {
      repository.pendingSave = Completer<ParkingRecord>();
      final failure = expectLater(
        controller.save(draft),
        throwsA(isA<StateError>()),
      );
      repository.pendingSave!.completeError(StateError('timeout after commit'));
      await failure;
      repository.pendingSave = Completer<ParkingRecord>();
      final retry = controller.save(draft);
      repository.pendingSave!.complete(savedRecord());
      await retry;
      expect(repository.keys, hasLength(2));
      expect(repository.keys[1], repository.keys[0]);
    },
  );
  test(
    'editing a failed draft starts a distinct idempotent operation',
    () async {
      repository.pendingSave = Completer<ParkingRecord>();
      final failure = expectLater(
        controller.save(draft),
        throwsA(isA<StateError>()),
      );
      repository.pendingSave!.completeError(StateError('offline'));
      await failure;
      repository.pendingSave = Completer<ParkingRecord>();
      final retry = controller.save(const ParkingDraft(floor: 'B3', zone: 'D'));
      repository.pendingSave!.complete(savedRecord());
      await retry;
      expect(repository.keys[1], isNot(repository.keys[0]));
    },
  );
  test('double submission issues only one server request', () async {
    repository.pendingSave = Completer<ParkingRecord>();
    final request = controller.save(draft);
    await expectLater(controller.save(draft), throwsA(isA<AppException>()));
    expect(repository.saveCalls, 1);
    repository.pendingSave!.complete(savedRecord());
    await request;
  });
  test('invalid draft is rejected before contacting the server', () async {
    await expectLater(
      controller.save(const ParkingDraft(floor: 'B99', zone: 'C')),
      throwsA(isA<AppException>()),
    );
    expect(repository.saveCalls, 0);
    expect(controller.latest?.id, 'old');
  });
  test(
    'confirmed permission revocation clears protected state and snapshot',
    () async {
      repository.fetchError = const PostgrestException(
        message: 'permission denied',
        code: '42501',
      );
      await controller.refresh();
      expect(controller.vehicle, isNull);
      expect(controller.records, isEmpty);
      expect(controller.members, isEmpty);
      expect(controller.error, contains('권한'));
      expect(nativeCalls, contains('clearSnapshot'));
    },
  );
  test(
    'save-time membership revocation clears protected data and widget',
    () async {
      repository.pendingSave = Completer<ParkingRecord>();
      final request = controller.save(draft);
      final rejection = expectLater(
        request,
        throwsA(isA<PostgrestException>()),
      );
      repository.pendingSave!.completeError(
        const PostgrestException(message: 'not_member', code: '42501'),
      );
      await rejection;
      expect(controller.vehicles, isEmpty);
      expect(controller.vehicle, isNull);
      expect(controller.records, isEmpty);
      expect(controller.members, isEmpty);
      expect(controller.saving, isFalse);
      expect(controller.error, contains('권한'));
      expect(nativeCalls, contains('clearSnapshot'));
    },
  );
  test('RLS returning no accessible vehicles clears old location', () async {
    repository.available = [];
    await controller.refresh();
    expect(controller.vehicle, isNull);
    expect(controller.latest, isNull);
    expect(nativeCalls, contains('clearSnapshot'));
  });
  test(
    'transient refresh failure preserves data and reports stale connection',
    () async {
      repository.fetchError = StateError('network disconnected');
      await controller.refresh();
      expect(controller.latest?.id, 'old');
      expect(controller.error, isNotNull);
      expect(controller.loading, isFalse);
    },
  );
  test(
    'native widget failure must not turn a confirmed server save into failure',
    () async {
      rejectSnapshot = true;
      repository.pendingSave = Completer<ParkingRecord>();
      final request = controller.save(draft);
      repository.pendingSave!.complete(savedRecord());
      final result = await request;
      expect(result.id, 'new');
      expect(controller.latest?.id, 'new');
      expect(repository.saveCalls, 1);
      expect(controller.widgetWarning, isNotNull);
    },
  );
}
