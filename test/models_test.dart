import 'package:carcar/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vehicle = Vehicle(
    id: 'car',
    ownerId: 'owner',
    name: '차',
    plate: '12가 3456',
    apartment: '집',
  );
  test('defaults expose five floors per level and both zone alphabets', () {
    expect(vehicle.floors, [
      'F1',
      'F2',
      'F3',
      'F4',
      'F5',
      'B1',
      'B2',
      'B3',
      'B4',
      'B5',
    ]);
    expect(vehicle.zones, [
      'A',
      'B',
      'C',
      'D',
      'E',
      'F',
      '가',
      '나',
      '다',
      '라',
      '마',
      '바',
    ]);
    for (final zone in ['F', '가', '바']) {
      expect(ParkingDraft(floor: 'F1', zone: zone).validate(vehicle), isNull);
    }
    expect(
      const ParkingDraft(floor: 'B6', zone: 'A').validate(vehicle),
      isNotNull,
    );
  });
  test('server configuration is preserved even when matching old defaults', () {
    final data = vehicle
        .copyWith(
          floors: ['B1', 'B2', 'B3', 'B4'],
          zones: ['A', 'B', 'C', 'D', 'E'],
        )
        .toJson();
    final restored = Vehicle.fromJson(data);
    expect(restored.floors, ['B1', 'B2', 'B3', 'B4']);
    expect(restored.zones, ['A', 'B', 'C', 'D', 'E']);
  });
  group('Parking OCR suggestions', () {
    test('extracts floor, zone and spot from an English sign', () {
      final result = parseParkingText('B2\nC24');
      expect(result.floor, 'B2');
      expect(result.zone, 'C');
      expect(result.spot, '24');
      expect(result.rawText, 'B2\nC24');
    });
    test('recognizes Korean floor and zone labels', () {
      final result = parseParkingText('지하 3층\nD구역\n번호 18');
      expect(result.floor, 'B3');
      expect(result.zone, 'D');
      expect(result.spot, '18');
    });
    test('normalizes lower case and separated floor numbers', () {
      final result = parseParkingText('b-2\na-007');
      expect(result.floor, 'B2');
      expect(result.zone, 'A');
      expect(result.spot, '007');
    });
    test('normalizes fullwidth B and minus sign', () {
      expect(parseParkingText('Ｂ－2\nC24').floor, 'B2');
    });
    test('does not turn a floor number into a parking spot', () {
      final result = parseParkingText('B2');
      expect(result.floor, 'B2');
      expect(result.zone, isNull);
      expect(result.spot, isNull);
    });
    test('does not suggest floors outside apartment configuration', () {
      final result = parseParkingText('B8 C24');
      expect(result.floor, isNull);
      expect(result.zone, 'C');
    });
    test('uses custom apartment floors and zones', () {
      final result = parseParkingText('B8 Z42', floors: ['B8'], zones: ['Z']);
      expect(result.floor, 'B8');
      expect(result.zone, 'Z');
      expect(result.spot, '42');
    });
    test('keeps conflicting floors unresolved', () {
      expect(parseParkingText('B2 B3 C24').floor, isNull);
    });
    test('repeated same floor is not considered a conflict', () {
      expect(parseParkingText('B2 지하2층 C24').floor, 'B2');
    });
    test('does not choose arbitrarily between conflicting zones', () {
      final result = parseParkingText('B2 C24 D25');
      expect(result.floor, 'B2');
      expect(result.zone, isNull);
      expect(result.spot, isNull);
    });
    test('does not choose arbitrarily between conflicting spots', () {
      final result = parseParkingText('B2 C24 C25');
      expect(result.zone, 'C');
      expect(result.spot, isNull);
    });
    test('empty or unrelated text gives no suggestion', () {
      expect(parseParkingText('').found, isFalse);
      expect(parseParkingText('엘리베이터 입구 안내').found, isFalse);
    });
  });
  group('Parking input validation', () {
    test('accepts optional empty spot and note', () {
      expect(
        const ParkingDraft(floor: 'B2', zone: 'C').validate(vehicle),
        isNull,
      );
    });
    test('requires allowed floor and zone', () {
      expect(
        const ParkingDraft(floor: 'B8', zone: 'C').validate(vehicle),
        isNotNull,
      );
      expect(
        const ParkingDraft(floor: 'B2', zone: 'Z').validate(vehicle),
        isNotNull,
      );
    });
    test('accepts length boundary and rejects excess', () {
      expect(
        ParkingDraft(
          floor: 'B2',
          zone: 'C',
          spot: '1' * 20,
          note: '가' * 500,
        ).validate(vehicle),
        isNull,
      );
      expect(
        ParkingDraft(floor: 'B2', zone: 'C', spot: '1' * 21).validate(vehicle),
        isNotNull,
      );
      expect(
        ParkingDraft(floor: 'B2', zone: 'C', note: '가' * 501).validate(vehicle),
        isNotNull,
      );
    });
    test('counts Unicode codepoints consistently with PostgreSQL length', () {
      expect(
        ParkingDraft(floor: 'B2', zone: 'C', spot: '🚗' * 20).validate(vehicle),
        isNull,
      );
      expect(
        ParkingDraft(floor: 'B2', zone: 'C', spot: '🚗' * 21).validate(vehicle),
        isNotNull,
      );
    });
    test('formats location without adding an absent spot', () {
      final record = ParkingRecord(
        id: 'record',
        vehicleId: 'car',
        floor: 'B2',
        zone: 'C',
        spot: '',
        note: '',
        createdBy: 'owner',
        createdAt: DateTime(2026),
      );
      expect(record.position, 'B2 · C구역');
    });
    test('deleted account author remains a readable historical record', () {
      final record = ParkingRecord.fromJson({
        'id': 'retained-record',
        'vehicle_id': 'car',
        'floor': 'B2',
        'zone': 'C',
        'spot': '24',
        'note': '보관된 가족 기록',
        'created_by': null,
        'created_at': '2026-11-02T01:30:00Z',
      });
      expect(record.createdBy, isEmpty);
      expect(record.position, 'B2 · C구역 · 24번');
      expect(record.note, '보관된 가족 기록');
    });
    test('preserves timestamp instant through JSON round trip', () {
      final record = ParkingRecord(
        id: 'record',
        vehicleId: 'car',
        floor: 'B2',
        zone: 'C',
        spot: '24',
        note: '입구',
        createdBy: 'owner',
        createdAt: DateTime.utc(2026, 11, 2, 1, 30),
      );
      final copy = ParkingRecord.fromJson(record.toJson());
      expect(copy.createdAt.isAtSameMomentAs(record.createdAt), isTrue);
      expect(copy.position, 'B2 · C구역 · 24번');
    });
    test('a typed unit is not repeated, like the home screen widgets', () {
      expect(zoneLabel('A'), 'A구역');
      expect(zoneLabel('A', gap: ' '), 'A 구역');
      expect(zoneLabel('A구역'), 'A구역');
      expect(zoneLabel('A구역', gap: ' '), 'A구역');
      expect(spotLabel('24'), '24번');
      expect(spotLabel('24번'), '24번');
      final record = ParkingRecord(
        id: 'record',
        vehicleId: 'car',
        floor: 'B2',
        zone: 'A구역',
        spot: '24번',
        note: '',
        createdBy: 'owner',
        createdAt: DateTime(2026),
      );
      expect(record.position, 'B2 · A구역 · 24번');
    });
  });

  group('Record time', () {
    final now = DateTime(2026, 11, 11, 16, 50);
    String at(DateTime date, [DateTime? when]) =>
        formatDate(date, now: when ?? now);
    test('today and yesterday are named, older days are spelled out', () {
      expect(at(DateTime(2026, 11, 11, 16, 41)), '오늘 16:41');
      expect(at(DateTime(2026, 11, 10, 19, 34)), '어제 19:34');
      expect(at(DateTime(2026, 11, 9, 5, 20)), '11월 9일 05:20');
      expect(at(DateTime(2026, 1, 3, 9, 5)), '1월 3일 09:05');
    });
    test('the day changes at midnight, not after 24 hours', () {
      final parked = DateTime(2026, 11, 10, 23, 59);
      expect(at(parked, DateTime(2026, 11, 10, 23, 59, 59)), '오늘 23:59');
      expect(at(parked, DateTime(2026, 11, 11, 0, 0)), '어제 23:59');
      expect(at(parked, DateTime(2026, 11, 11, 23, 59)), '어제 23:59');
      expect(at(parked, DateTime(2026, 11, 12, 0, 0)), '11월 10일 23:59');
      // Midnight itself belongs to the new day.
      expect(
        at(DateTime(2026, 11, 11), DateTime(2026, 11, 11, 0, 1)),
        '오늘 00:00',
      );
    });
    test('another year shows the year, except across a new year night', () {
      expect(at(DateTime(2025, 11, 11, 16, 41)), '2025년 11월 11일 16:41');
      expect(
        at(DateTime(2025, 12, 31, 23, 50), DateTime(2026, 1, 1, 0, 10)),
        '어제 23:50',
      );
      expect(
        at(DateTime(2025, 12, 30, 23, 50), DateTime(2026, 1, 1, 0, 10)),
        '2025년 12월 30일 23:50',
      );
    });
    test('a record ahead of the device clock is never called today', () {
      expect(at(DateTime(2026, 11, 12, 0, 5)), '11월 12일 00:05');
    });
    test('the full form keeps the year and ignores the day words', () {
      expect(
        formatDate(DateTime(2026, 11, 11, 16, 41), full: true, now: now),
        '2026. 11. 11. 16:41',
      );
    });
  });
}
