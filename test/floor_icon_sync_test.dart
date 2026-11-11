import 'dart:async';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/models.dart';
import 'package:carcar/core/repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Replaces the controller with one reading this device's stored choice.
  Future<void> device(Map<String, Object> stored) async {
    controller.dispose();
    SharedPreferences.setMockInitialValues(stored);
    controller = AppController(
      repository,
      preferences: await SharedPreferences.getInstance(),
    );
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    repository = FloorRepository();
    // The shared cases below run on an iPhone whose floor icon is switched on.
    SharedPreferences.setMockInitialValues({
      AppController.floorIconPreferenceKey: true,
    });
    controller = AppController(
      repository,
      preferences: await SharedPreferences.getInstance(),
    );
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
  test('iPhone is off by default and never changes a new user icon', () async {
    await device({});
    current = null;
    expect(controller.floorIconEnabled, isFalse);
    await controller.initialize();
    await drain();
    repository.pendingSave = Completer()..complete(floorRecord('B2'));
    await controller.save(const ParkingDraft(floor: 'B2', zone: 'A'));
    await drain();
    await controller.syncFloorIcon();
    expect(controller.latest!.floor, 'B2');
    expect(writes, isEmpty);
    expect(current, isNull);
    expect(controller.iconWarning, isNull);
  });
  test(
    'iPhone left off returns an applied floor icon to default once',
    () async {
      await device({});
      await controller.initialize();
      await drain();
      expect(writes, [null]);
      expect(current, isNull);
      repository.record = floorRecord('F3');
      await controller.refresh();
      await drain();
      expect(writes, [null]);
    },
  );
  test(
    'switching off restores the default icon and on applies the floor',
    () async {
      await controller.initialize();
      await drain();
      expect(writes, isEmpty);
      await controller.setFloorIconEnabled(false);
      expect(controller.floorIconEnabled, isFalse);
      expect(writes, [null]);
      expect(current, isNull);
      await controller.setFloorIconEnabled(true);
      expect(controller.floorIconEnabled, isTrue);
      expect(writes, [null, 'floor_b1']);
      expect(current, 'floor_b1');
      expect(
        (await SharedPreferences.getInstance()).getBool(
          AppController.floorIconPreferenceKey,
        ),
        isTrue,
      );
    },
  );
  test('a choice that cannot be stored changes nothing', () async {
    controller.dispose();
    controller = AppController(repository);
    await controller.initialize();
    await drain();
    writes.clear();
    current = null;
    await expectLater(
      controller.setFloorIconEnabled(true),
      throwsA(isA<AppException>()),
    );
    expect(controller.floorIconEnabled, isFalse);
    expect(writes, isEmpty);
  });
  test('Android stays automatic with no stored choice', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await device({});
    current = null;
    expect(controller.floorIconEnabled, isTrue);
    await controller.initialize();
    await drain();
    expect(writes, ['floor_b1']);
    repository.record = floorRecord('B2');
    await controller.refresh();
    await drain();
    expect(writes, ['floor_b1', 'floor_b2']);
    expect(current, 'floor_b2');
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
