import 'package:flutter/material.dart';

const defaultFloors = [
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
];
const defaultZones = [
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
];
const vehicleColors = <String, Color>{
  'car_blue': Color(0xFF577AA4),
  'car_black': Color(0xFF343B39),
  'car_white': Color(0xFFB3BBB5),
  'car_gold': Color(0xFFC8A35B),
  'car_mint': Color(0xFF669E84),
  'car_purple': Color(0xFF9985B4),
  'car_red': Color(0xFFC77669),
  'car_gray': Color(0xFF8C9297),
};

class Vehicle {
  const Vehicle({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.plate,
    required this.apartment,
    this.icon = 'car_mint',
    this.floors = defaultFloors,
    this.zones = defaultZones,
    this.latestId,
  });
  final String id, ownerId, name, plate, apartment, icon;
  final List<String> floors, zones;
  final String? latestId;
  factory Vehicle.fromJson(Map<String, dynamic> json) {
    final apartment = json['apartments'] as Map<String, dynamic>? ?? {};
    return Vehicle(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['nickname'] as String,
      plate: json['plate_number'] as String,
      apartment: apartment['name'] as String? ?? '',
      icon: json['icon_id'] as String? ?? 'car_mint',
      latestId: json['latest_parking_record_id'] as String?,
      floors: List<String>.from(
        apartment['allowed_floors'] as List? ?? defaultFloors,
      ),
      zones: List<String>.from(
        apartment['allowed_zones'] as List? ?? defaultZones,
      ),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'owner_id': ownerId,
    'nickname': name,
    'plate_number': plate,
    'icon_id': icon,
    'latest_parking_record_id': latestId,
    'apartments': {
      'name': apartment,
      'allowed_floors': floors,
      'allowed_zones': zones,
    },
  };
  Vehicle copyWith({
    String? icon,
    String? latestId,
    String? apartment,
    List<String>? floors,
    List<String>? zones,
  }) => Vehicle(
    id: id,
    ownerId: ownerId,
    name: name,
    plate: plate,
    apartment: apartment ?? this.apartment,
    icon: icon ?? this.icon,
    latestId: latestId ?? this.latestId,
    floors: floors ?? this.floors,
    zones: zones ?? this.zones,
  );
}

class ParkingRecord {
  const ParkingRecord({
    required this.id,
    required this.vehicleId,
    required this.floor,
    required this.zone,
    required this.spot,
    required this.note,
    required this.createdBy,
    required this.createdAt,
  });
  final String id, vehicleId, floor, zone, spot, note, createdBy;
  final DateTime createdAt;
  String get position =>
      '$floor · ${zoneLabel(zone)}${spot.isEmpty ? '' : ' · ${spotLabel(spot)}'}';
  factory ParkingRecord.fromJson(Map<String, dynamic> json) => ParkingRecord(
    id: json['id'] as String,
    vehicleId: json['vehicle_id'] as String,
    floor: json['floor'] as String,
    zone: json['zone'] as String,
    spot: json['spot'] as String? ?? '',
    note: json['note'] as String? ?? '',
    createdBy: json['created_by'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'vehicle_id': vehicleId,
    'floor': floor,
    'zone': zone,
    'spot': spot,
    'note': note,
    'created_by': createdBy,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}

class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.name,
    required this.owner,
  });
  final String id, name;
  final bool owner;
  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
    id: json['user_id'] as String,
    name: (json['nickname'] as String?)?.trim().isNotEmpty == true
        ? json['nickname'] as String
        : '가족',
    owner: json['role'] == 'owner',
  );
}

class ParkingDraft {
  const ParkingDraft({
    required this.floor,
    required this.zone,
    this.spot = '',
    this.note = '',
  });
  final String floor, zone, spot, note;
  String get fingerprint => '$floor\u0000$zone\u0000$spot\u0000$note';
  String? validate(Vehicle vehicle) {
    if (!vehicle.floors.contains(floor)) return '층수를 선택해 주세요.';
    if (!vehicle.zones.contains(zone)) return '구역을 선택해 주세요.';
    if (spot.runes.length > 20) return '주차 번호는 20자까지 입력할 수 있어요.';
    if (note.runes.length > 500) return '메모는 500자까지 입력할 수 있어요.';
    return null;
  }
}

class OcrSuggestion {
  const OcrSuggestion({
    this.floor,
    this.zone,
    this.spot,
    required this.rawText,
  });
  final String? floor, zone, spot;
  final String rawText;
  bool get found => floor != null || zone != null || spot != null;
}

OcrSuggestion parseParkingText(
  String text, {
  List<String> floors = defaultFloors,
  List<String> zones = defaultZones,
}) {
  final normalized = text
      .toUpperCase()
      .replaceAll('Ｂ', 'B')
      .replaceAll('－', '-');
  final floorCandidates = <String>{};
  for (final match in RegExp(
    r'(?:지하\s*|\bB\s*-?\s*)(\d{1,2})(?:\s*층|\b)',
  ).allMatches(normalized)) {
    final value = 'B${int.parse(match.group(1)!)}';
    if (floors.contains(value)) floorCandidates.add(value);
  }
  final floor = floorCandidates.length == 1 ? floorCandidates.single : null;
  final withoutFloor = normalized.replaceAll(
    RegExp(r'(?:지하\s*|\bB\s*-?\s*)\d{1,2}(?:\s*층|\b)'),
    ' ',
  );
  final zoneCandidates = <String>{};
  final spots = <String>{};
  for (final match in RegExp(
    r'\b([A-Z])\s*[-:]?\s*(\d{1,4})\b',
  ).allMatches(withoutFloor)) {
    if (zones.contains(match.group(1))) {
      zoneCandidates.add(match.group(1)!);
      spots.add(match.group(2)!);
    }
  }
  for (final zone in zones) {
    if (RegExp(
      '(?:^|\\s)${RegExp.escape(zone)}(?:\\s*구역|\\s*ZONE|\\s|\$)',
    ).hasMatch(withoutFloor)) {
      zoneCandidates.add(zone);
    }
  }
  final explicitSpot = RegExp(
    r'(?:번호\s*|NO\.?\s*)(\d{1,4})\b',
  ).firstMatch(withoutFloor);
  if (explicitSpot != null) spots.add(explicitSpot.group(1)!);
  return OcrSuggestion(
    floor: floor,
    zone: zoneCandidates.length == 1 ? zoneCandidates.single : null,
    spot: spots.length == 1 && zoneCandidates.length <= 1 ? spots.single : null,
    rawText: text,
  );
}

/// Same rule as the native widgets: a value that already ends in its unit
/// keeps it, so '24번' never becomes '24번번'.
String zoneLabel(String zone, {String gap = ''}) =>
    zone.endsWith('구역') ? zone : '$zone$gap구역';
String spotLabel(String spot) => spot.endsWith('번') ? spot : '$spot번';

/// [now] is only passed by tests; the day words follow the device calendar.
String formatDate(DateTime date, {bool full = false, DateTime? now}) {
  final d = date.toLocal();
  final time =
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (full) return '${d.year}. ${d.month}. ${d.day}. $time';
  final today = (now ?? DateTime.now()).toLocal();
  // Calendar days, not 24-hour spans: 23:59 yesterday is '어제' at 00:01.
  final days = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
  if (days == 0) return '오늘 $time';
  if (days == 1) return '어제 $time';
  return '${d.year == today.year ? '' : '${d.year}년 '}${d.month}월 ${d.day}일 $time';
}
