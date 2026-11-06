import 'dart:convert';
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
  test('upgrades only known demo defaults and preserves old history', () async {
    for (final floors in [
      ['F5', 'F4', 'F3', 'F2', 'F1', 'B1', 'B2', 'B3', 'B4', 'B5', 'B6'],
      ['B1', 'B2', 'B3', 'B4'],
      ['B6', 'F9'],
    ]) {
      final data =
          jsonDecode(preferences.getString(DemoParkingRepository.storageKey)!)
              as Map<String, dynamic>;
      data.remove('parkingOptionsVersion');
      final apartment =
          data['vehicles'][0]['apartments'] as Map<String, dynamic>;
      apartment['allowed_floors'] = floors;
      apartment['allowed_zones'] = floors.last == 'F9'
          ? ['Z', '바']
          : ['A', 'B', 'C', 'D', 'E'];
      data['records'][0]['floor'] = 'B6';
      data['records'][0]['note'] = '기존 가족 메모';
      await preferences.setString(
        DemoParkingRepository.storageKey,
        jsonEncode(data),
      );
      final reopened = DemoParkingRepository(preferences);
      await reopened.initialize();
      final vehicle = (await reopened.vehicles()).single;
      expect(vehicle.floors, floors.last == 'F9' ? floors : defaultFloors);
      expect(vehicle.zones, floors.last == 'F9' ? ['Z', '바'] : defaultZones);
      final records = await reopened.records(vehicle.id);
      expect(records, hasLength(5));
      expect(records.first.floor, 'B6');
      expect(records.first.note, '기존 가족 메모');
      expect(vehicle.latestId, records.first.id);
    }
  });
  test('demo upgrades floor and zone defaults independently', () async {
    for (final customFloors in [true, false]) {
      final data =
          jsonDecode(preferences.getString(DemoParkingRepository.storageKey)!)
              as Map<String, dynamic>;
      data.remove('parkingOptionsVersion');
      final apartment =
          data['vehicles'][0]['apartments'] as Map<String, dynamic>;
      apartment['allowed_floors'] = customFloors
          ? ['B6']
          : ['B1', 'B2', 'B3', 'B4'];
      apartment['allowed_zones'] = customFloors
          ? ['A', 'B', 'C', 'D', 'E']
          : ['Z'];
      await preferences.setString(
        DemoParkingRepository.storageKey,
        jsonEncode(data),
      );
      final reopened = DemoParkingRepository(preferences);
      await reopened.initialize();
      final vehicle = (await reopened.vehicles()).single;
      expect(vehicle.floors, customFloors ? ['B6'] : defaultFloors);
      expect(vehicle.zones, customFloors ? defaultZones : ['Z']);
    }
  });
  test(
    'custom legacy-shaped options survive reopening after initialization',
    () async {
      final vehicle = (await repository.vehicles()).single;
      await repository.updateApartment(
        vehicle.id,
        '내 아파트',
        ['B1', 'B2', 'B3', 'B4'],
        ['A', 'B', 'C', 'D', 'E'],
      );
      final reopened = DemoParkingRepository(preferences);
      await reopened.initialize();
      final restored = (await reopened.vehicles()).single;
      expect(restored.floors, ['B1', 'B2', 'B3', 'B4']);
      expect(restored.zones, ['A', 'B', 'C', 'D', 'E']);
    },
  );
  test(
    'options migration persists once and later custom choices survive',
    () async {
      final data =
          jsonDecode(preferences.getString(DemoParkingRepository.storageKey)!)
              as Map<String, dynamic>;
      data.remove('parkingOptionsVersion');
      data['vehicles'][0]['apartments']['allowed_floors'] = [
        'B1',
        'B2',
        'B3',
        'B4',
      ];
      data['vehicles'][0]['apartments']['allowed_zones'] = [
        'A',
        'B',
        'C',
        'D',
        'E',
      ];
      await preferences.setString(
        DemoParkingRepository.storageKey,
        jsonEncode(data),
      );
      final migrated = DemoParkingRepository(preferences);
      await migrated.initialize();
      final stored =
          jsonDecode(preferences.getString(DemoParkingRepository.storageKey)!)
              as Map<String, dynamic>;
      expect(stored['parkingOptionsVersion'], 1);
      expect(
        stored['vehicles'][0]['apartments']['allowed_floors'],
        defaultFloors,
      );
      final vehicle = (await migrated.vehicles()).single;
      await migrated.updateApartment(
        vehicle.id,
        '내 아파트',
        ['B1', 'B2', 'B3', 'B4'],
        ['A', 'B', 'C', 'D', 'E'],
      );
      final reopened = DemoParkingRepository(preferences);
      await reopened.initialize();
      expect((await reopened.vehicles()).single.floors, [
        'B1',
        'B2',
        'B3',
        'B4',
      ]);
      expect((await reopened.vehicles()).single.zones, [
        'A',
        'B',
        'C',
        'D',
        'E',
      ]);
    },
  );
  test('failed options migration never resets existing records', () async {
    final data =
        jsonDecode(preferences.getString(DemoParkingRepository.storageKey)!)
            as Map<String, dynamic>;
    data.remove('parkingOptionsVersion');
    data['records'][0]['note'] = '보존할 메모';
    final original = jsonEncode(data);
    await preferences.setString(DemoParkingRepository.storageKey, original);
    final failing = FailingPreferences(preferences)..failWrites = true;
    await expectLater(
      DemoParkingRepository(failing).initialize(),
      throwsA(isA<AppException>()),
    );
    expect(preferences.getString(DemoParkingRepository.storageKey), original);
    failing.failWrites = false;
    final recovered = DemoParkingRepository(failing);
    await recovered.initialize();
    final vehicle = (await recovered.vehicles()).single;
    expect((await recovered.records(vehicle.id)).first.note, '보존할 메모');
  });
  test('new zones save and persist while B6 is rejected', () async {
    final vehicle = (await repository.vehicles()).single;
    for (final zone in ['F', '가', '바']) {
      await repository.save(
        vehicle.id,
        ParkingDraft(floor: 'F5', zone: zone),
        'zone-$zone',
      );
    }
    await expectLater(
      repository.save(
        vehicle.id,
        const ParkingDraft(floor: 'B6', zone: 'A'),
        'removed-floor',
      ),
      throwsA(isA<AppException>()),
    );
    final reopened = DemoParkingRepository(preferences);
    await reopened.initialize();
    expect((await reopened.records(vehicle.id)).take(3).map((r) => r.zone), [
      '바',
      '가',
      'F',
    ]);
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
  test('demo cannot register a second vehicle or disturb the first', () async {
    final original = (await repository.vehicles()).single;
    await expectLater(
      repository.createVehicle('다른 집', '98나7654', '두 번째 차', '나'),
      throwsA(isA<AppException>()),
    );
    expect((await repository.vehicles()).single.id, original.id);
    expect(await repository.records(original.id), hasLength(5));
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
