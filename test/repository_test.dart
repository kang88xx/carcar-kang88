import 'package:carcar/core/models.dart';
import 'package:carcar/core/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FailingPreferences implements SharedPreferences {
  FailingPreferences(this.backing);
  final SharedPreferences backing;
  bool failWrites = false;
  @override
  String? getString(String key) => backing.getString(key);
  @override
  Future<bool> setString(String key, String value) =>
      failWrites ? Future.value(false) : backing.setString(key, value);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late DemoParkingRepository repository;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'unrelated.preference': 'keep'});
    preferences = await SharedPreferences.getInstance();
    repository = DemoParkingRepository(preferences);
    await repository.initialize();
  });
  test('demo is explicitly local and seeds a valid latest pointer', () async {
    expect(repository.isDemo, isTrue);
    final vehicle = (await repository.vehicles()).single;
    final records = await repository.records(vehicle.id);
    expect(records.first.id, vehicle.latestId);
    expect(records, hasLength(5));
  });
  test('parking save persists across repository restart', () async {
    final vehicle = (await repository.vehicles()).single;
    final saved = await repository.save(
      vehicle.id,
      const ParkingDraft(floor: 'B4', zone: 'E', spot: '19', note: '출입구'),
      'first-key',
    );
    final reopened = DemoParkingRepository(preferences);
    await reopened.initialize();
    expect((await reopened.vehicles()).single.latestId, saved.id);
    final restored = (await reopened.records(vehicle.id)).first;
    expect(restored.id, saved.id);
    expect(restored.position, 'B4 · E구역 · 19번');
    expect(restored.note, '출입구');
  });
  test(
    'retrying identical idempotency key does not append another record',
    () async {
      final vehicle = (await repository.vehicles()).single;
      const draft = ParkingDraft(floor: 'B4', zone: 'E');
      final first = await repository.save(vehicle.id, draft, 'retry-key');
      final second = await repository.save(vehicle.id, draft, 'retry-key');
      expect(second.id, first.id);
      expect(await repository.records(vehicle.id), hasLength(6));
    },
  );
  test(
    'invalid input does not change stored records or latest pointer',
    () async {
      final vehicle = (await repository.vehicles()).single;
      await expectLater(
        repository.save(
          vehicle.id,
          const ParkingDraft(floor: 'B99', zone: 'E'),
          'invalid',
        ),
        throwsA(isA<AppException>()),
      );
      expect((await repository.vehicles()).single.latestId, vehicle.latestId);
      expect(await repository.records(vehicle.id), hasLength(5));
    },
  );
  test('records remain isolated between demo vehicles', () async {
    final original = (await repository.vehicles()).single;
    final secondId = await repository.createVehicle(
      '다른 집',
      '98나 7654',
      '두 번째 차',
      '나',
    );
    await repository.save(
      secondId,
      const ParkingDraft(floor: 'B1', zone: 'A'),
      'other',
    );
    expect(await repository.records(original.id), hasLength(5));
    expect(await repository.records(secondId), hasLength(1));
    expect((await repository.vehicles()).first.latestId, original.latestId);
  });
  test(
    'corrupted demo JSON recovers without touching other preferences',
    () async {
      await preferences.setString(DemoParkingRepository.storageKey, '{broken');
      final recovered = DemoParkingRepository(preferences);
      await recovered.initialize();
      expect(await recovered.vehicles(), hasLength(1));
      expect(preferences.getString('unrelated.preference'), 'keep');
    },
  );
  test('wrong-shaped demo JSON recovers safely', () async {
    await preferences.setString(
      DemoParkingRepository.storageKey,
      '{"vehicles": 5}',
    );
    final recovered = DemoParkingRepository(preferences);
    await recovered.initialize();
    expect(await recovered.vehicles(), hasLength(1));
  });
  test('demo cannot create real invitations or redeem codes', () async {
    await expectLater(
      repository.invite('demo-car'),
      throwsA(isA<AppException>()),
    );
    await expectLater(
      repository.join('a-real-looking-code'),
      throwsA(isA<AppException>()),
    );
  });
  test('allowed icon changes persist and unknown icons are rejected', () async {
    await repository.setIcon('demo-car', 'car_purple');
    final reopened = DemoParkingRepository(preferences);
    await reopened.initialize();
    expect((await reopened.vehicles()).single.icon, 'car_purple');
    await expectLater(
      repository.setIcon('demo-car', 'remote_image'),
      throwsA(isA<AppException>()),
    );
  });
  test(
    'failed disk save rolls back location and allows the same retry',
    () async {
      final disk = FailingPreferences(preferences);
      final local = DemoParkingRepository(disk);
      await local.initialize();
      final before = (await local.vehicles()).single;
      disk.failWrites = true;
      const draft = ParkingDraft(floor: 'B4', zone: 'D', spot: '99');
      await expectLater(
        local.save(before.id, draft, 'disk-retry'),
        throwsA(isA<AppException>()),
      );
      expect((await local.vehicles()).single.latestId, before.latestId);
      expect(await local.records(before.id), hasLength(5));
      disk.failWrites = false;
      final saved = await local.save(before.id, draft, 'disk-retry');
      expect((await local.vehicles()).single.latestId, saved.id);
      expect(await local.records(before.id), hasLength(6));
    },
  );
  test(
    'demo reset cannot resurrect records or cached idempotent saves',
    () async {
      const draft = ParkingDraft(floor: 'B2', zone: 'C', spot: '24');
      final old = await repository.save(
        'demo-car',
        draft,
        'reused-after-reset',
      );
      await repository.deleteAccount();
      expect(await repository.vehicles(), isEmpty);
      expect(await repository.records('demo-car'), isEmpty);
      final freshCar = await repository.createVehicle(
        '새 집',
        '22나 3333',
        '새 차',
        '나',
      );
      final fresh = await repository.save(
        freshCar,
        draft,
        'reused-after-reset',
      );
      expect(fresh.id, isNot(old.id));
      expect(fresh.vehicleId, freshCar);
      expect(await repository.records('demo-car'), isEmpty);
      final reopened = DemoParkingRepository(preferences);
      await reopened.initialize();
      expect((await reopened.vehicles()).single.id, freshCar);
      expect(await reopened.records('demo-car'), isEmpty);
      expect((await reopened.records(freshCar)).single.id, fresh.id);
    },
  );
  test('demo reset deletes only its own storage', () async {
    await repository.deleteAccount();
    expect(preferences.containsKey(DemoParkingRepository.storageKey), isFalse);
    expect(preferences.getString('unrelated.preference'), 'keep');
  });
}
