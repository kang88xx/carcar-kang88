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
  });
}
