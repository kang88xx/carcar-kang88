import 'dart:async';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/models.dart';
import 'package:carcar/core/repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FloorRepository implements ParkingRepository {
  ParkingRecord record = floorRecord('B1');
  Completer<ParkingRecord>? pendingSave;
  @override
  bool get isDemo => false;
  @override
  String get userId => 'owner';
  @override
  Future<List<Vehicle>> vehicles() async => [
    Vehicle(
      id: 'car',
      ownerId: 'owner',
      name: '차',
      plate: '12가3456',
      apartment: '집',
      latestId: record.id,
    ),
  ];
  @override
  Future<List<ParkingRecord>> records(String id) async => [record];
  @override
  Future<List<FamilyMember>> members(String id) async => [];
  @override
  Future<ParkingRecord> save(String id, ParkingDraft draft, String key) async =>
      record = await pendingSave!.future;
  @override
  void watch(void Function() onChange) {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ParkingRecord floorRecord(String floor) => ParkingRecord(
  id: 'record-$floor',
  vehicleId: 'car',
  floor: floor,
  zone: 'A',
  spot: '',
  note: '',
  createdBy: 'owner',
  createdAt: DateTime.utc(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('carcar/native');
  late FloorRepository repository;
  late AppController controller;
  late List<String?> writes;
  String? current;
  bool fail = false;
  Completer<void>? writeGate;
  Future<void> drain() async {
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    repository = FloorRepository();
    controller = AppController(repository);
    writes = [];
    current = 'floor_b1';
    fail = false;
    writeGate = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'launcherIconState') {
            return {'supported': true, 'iconId': current};
          }
          if (call.method == 'setLauncherIcon') {
            final target = (call.arguments as Map)['iconId'] as String?;
            writes.add(target);
            await writeGate?.future;
            if (fail) throw PlatformException(code: 'icon_change_failed');
            current = target;
            return {'supported': true, 'iconId': current};
          }
          return null;
        });
  });
  tearDown(() {
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('save changes icon only after server confirmation', () async {
    await controller.initialize();
    await drain();
    repository.pendingSave = Completer();
    final save = controller.save(const ParkingDraft(floor: 'B2', zone: 'A'));
    await drain();
    expect(writes, isEmpty);
    expect(controller.latest!.floor, 'B1');
    repository.pendingSave!.complete(floorRecord('B2'));
    await save;
    await drain();
    expect(writes, ['floor_b2']);
    expect(current, 'floor_b2');
  });
  test('failed save leaves confirmed icon unchanged', () async {
    await controller.initialize();
    await drain();
    repository.pendingSave = Completer();
    final save = controller.save(const ParkingDraft(floor: 'B2', zone: 'A'));
    final assertion = expectLater(save, throwsA(isA<AppException>()));
    repository.pendingSave!.completeError(const AppException('연결을 확인해 주세요.'));
    await assertion;
    await drain();
    expect(writes, isEmpty);
    expect(current, 'floor_b1');
  });
  test('same floor is a no-op and unknown/no record restores logo', () async {
    await controller.initialize();
    await drain();
    await controller.syncFloorIcon();
    expect(writes, isEmpty);
    repository.record = floorRecord('B7');
    await controller.refresh();
    await drain();
    expect(writes, [null]);
    current = 'floor_f1';
    controller.records = [];
    await controller.syncFloorIcon();
    expect(current, isNull);
    expect(writes, [null, null]);
  });
  test('background defers changes until foreground reconciliation', () async {
    await controller.initialize();
    await drain();
    controller.appActive = false;
    repository.record = floorRecord('F3');
    await controller.refresh();
    await drain();
    expect(writes, isEmpty);
    controller.appActive = true;
    await controller.syncFloorIcon();
    expect(writes, ['floor_f3']);
  });
  test('latest record wins when an older icon change is in flight', () async {
    await controller.initialize();
    await drain();
    writeGate = Completer();
    repository.record = floorRecord('B2');
    await controller.refresh();
    await drain();
    expect(writes, ['floor_b2']);
    repository.record = floorRecord('F5');
    await controller.refresh();
    await drain();
    writeGate!.complete();
    await drain();
    expect(writes, ['floor_b2', 'floor_f5']);
    expect(current, 'floor_f5');
  });
  test(
    'icon failure never turns confirmed parking save into failure',
    () async {
      await controller.initialize();
      await drain();
      fail = true;
      repository.pendingSave = Completer()..complete(floorRecord('B3'));
      final saved = await controller.save(
        const ParkingDraft(floor: 'B3', zone: 'A'),
      );
      await drain();
      expect(saved.floor, 'B3');
      expect(controller.latest!.floor, 'B3');
      expect(controller.iconWarning, isNotNull);
      expect(current, 'floor_b1');
    },
  );
}
