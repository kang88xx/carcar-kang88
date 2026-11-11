import 'dart:async';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/models.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/main.dart' show serverRequestOptions;
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
  Completer<List<Vehicle>>? pendingFetch;
  Completer<List<ParkingRecord>>? pendingRecords;
  Completer<ParkingRecord>? pendingSave;
  final keys = <String>[];
  int saveCalls = 0;
  @override
  Future<List<Vehicle>> vehicles() async {
    if (fetchError != null) throw fetchError!;
    if (pendingFetch != null) return pendingFetch!.future;
    return List.of(available);
  }

  @override
  Future<List<ParkingRecord>> records(String vehicleId) async {
    if (pendingRecords != null) return pendingRecords!.future;
    return history.where((record) => record.vehicleId == vehicleId).toList();
  }

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

/// Mirrors create_parking_record_and_set_latest: a known idempotency key
/// returns the stored record and inserts nothing.
class KeyedRepository extends ControlledRepository {
  final stored = <String, ParkingRecord>{};
  Completer<void>? stall;

  ParkingRecord insert(String floor, String zone, String by) {
    final record = ParkingRecord(
      id: 'r${history.length}',
      vehicleId: 'car',
      floor: floor,
      zone: zone,
      spot: '',
      note: '',
      createdBy: by,
      createdAt: DateTime.utc(2026, 11, 10, 20 + history.length),
    );
    history = [record, ...history];
    available = [available.single.copyWith(latestId: record.id)];
    return record;
  }

  @override
  Future<ParkingRecord> save(
    String vehicleId,
    ParkingDraft draft,
    String key,
  ) async {
    keys.add(key);
    final wait = stall;
    stall = null;
    if (wait != null) await wait.future;
    return stored[key] ??= insert(draft.floor, draft.zone, userId);
  }
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
      // Nothing was typed on home, so the copy must not mention kept input.
      expect(controller.error, '연결이 불안정해요. 다시 시도해 주세요.');
      expect(controller.loading, isFalse);
    },
  );
  test('production timeouts are 12s for loads and 15s for saves', () {
    expect(controller.loadTimeout, const Duration(seconds: 12));
    expect(controller.saveTimeout, const Duration(seconds: 15));
    // The stalled request itself is ended when the save gives up.
    expect(serverRequestOptions.requestTimeout, controller.saveTimeout);
    expect(AppController.retryWindow, const Duration(minutes: 2));
  });
  test(
    'stalled save times out without success and retry reuses its key',
    () async {
      final stalled = AppController(
        repository,
        saveTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(stalled.dispose);
      await stalled.initialize();
      nativeCalls.clear();
      // Never completed: the server neither confirms nor rejects.
      repository.pendingSave = Completer<ParkingRecord>();
      await expectLater(stalled.save(draft), throwsA(isA<TimeoutException>()));
      expect(stalled.saving, isFalse);
      expect(stalled.latest?.id, 'old');
      expect(stalled.records, hasLength(1));
      expect(nativeCalls, isEmpty);
      repository.pendingSave = Completer<ParkingRecord>()
        ..complete(savedRecord());
      final saved = await stalled.save(draft);
      expect(saved.id, 'new');
      expect(stalled.latest?.id, 'new');
      expect(repository.keys, hasLength(2));
      expect(repository.keys[1], repository.keys[0]);
    },
  );
  test('stalled first load ends the spinner with nothing confirmed', () async {
    repository.pendingFetch = Completer<List<Vehicle>>();
    final stalled = AppController(
      repository,
      loadTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(stalled.dispose);
    await stalled.initialize();
    expect(stalled.loading, isFalse);
    expect(stalled.vehicle, isNull);
    expect(stalled.lastSynced, isNull);
    expect(stalled.error, '연결이 불안정해요. 다시 시도해 주세요.');
  });
  test('stalled refresh keeps the last confirmed location', () async {
    final stalled = AppController(
      repository,
      loadTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(stalled.dispose);
    await stalled.initialize();
    final synced = stalled.lastSynced;
    repository.pendingRecords = Completer<List<ParkingRecord>>();
    await stalled.refresh();
    expect(stalled.loading, isFalse);
    expect(stalled.latest?.id, 'old');
    expect(stalled.lastSynced, synced);
    expect(stalled.error, isNotNull);
  });
  group('a timed-out save that reached the server late', () {
    const usual = ParkingDraft(floor: 'B2', zone: 'A');
    late KeyedRepository server;
    late AppController timedOut;
    late DateTime now;
    setUp(() async {
      server = KeyedRepository();
      now = DateTime.utc(2026, 11, 10, 20);
      timedOut = AppController(
        server,
        saveTimeout: const Duration(milliseconds: 20),
        now: () => now,
      );
      await timedOut.initialize();
      final stall = server.stall = Completer<void>();
      await expectLater(timedOut.save(usual), throwsA(isA<TimeoutException>()));
      // The app has reported a failure; the request arrives afterwards.
      stall.complete();
      await Future<void>.delayed(Duration.zero);
      expect(server.history.map((record) => record.id), ['r1', 'old']);
    });
    tearDown(() => timedOut.dispose());
    test('is returned to a prompt retry instead of a duplicate', () async {
      now = now.add(AppController.retryWindow);
      final saved = await timedOut.save(usual);
      expect(saved.id, 'r1');
      expect(server.keys[1], server.keys[0]);
      expect(server.history, hasLength(2));
      expect(timedOut.latest?.id, 'r1');
    });
    test('does not swallow the next parking at the same place', () async {
      // Later a family member parks elsewhere, then I park where I always do.
      server.insert('B1', 'C', 'family');
      await timedOut.refresh();
      expect(timedOut.latest?.floor, 'B1');
      now = now.add(
        AppController.retryWindow + const Duration(milliseconds: 1),
      );
      final saved = await timedOut.save(usual);
      expect(server.keys[1], isNot(server.keys[0]));
      expect(saved.id, 'r3');
      expect(server.history.map((record) => record.id), [
        'r3',
        'r2',
        'r1',
        'old',
      ]);
      expect(timedOut.latest?.id, 'r3');
      expect(timedOut.latest?.floor, 'B2');
    });
  });
  test('generic failure copy does not claim that input was kept', () {
    expect(friendlyError(StateError('offline')), '연결이 불안정해요. 다시 시도해 주세요.');
  });
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
