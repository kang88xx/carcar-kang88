import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart' show PlatformException;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'native_bridge.dart' show AppleCredential;
import 'account_deletion.dart';
export 'account_deletion.dart';

abstract class ParkingRepository {
  bool get isDemo;
  String get userId;

  /// Suggested display name from the sign-in account, or null.
  String? get accountName;
  Map<String, dynamic>? widgetSession(Vehicle vehicle);
  Future<List<Vehicle>> vehicles();
  Future<List<ParkingRecord>> records(String vehicleId);
  Future<List<FamilyMember>> members(String vehicleId);
  Future<String> profileName();
  Future<void> updateProfileName(String name);
  Future<String> createVehicle(
    String apartment,
    String plate,
    String name,
    String nickname,
  );
  Future<ParkingRecord> save(String vehicleId, ParkingDraft draft, String key);
  Future<Map<String, dynamic>> invite(String vehicleId);
  Future<String> join(String code);
  Future<void> setIcon(String vehicleId, String icon);
  Future<void> removeMember(String vehicleId, String userId);
  Future<void> leave(String vehicleId);
  Future<void> updateApartment(
    String vehicleId,
    String name,
    List<String> floors,
    List<String> zones,
  );
  Future<void> deleteAccount({
    Future<AppleCredential?> Function()? reauthenticateApple,
    Future<bool> Function(AppleDisconnectFailure failure)?
    confirmManualAppleDisconnect,
  });
  Future<void> signOut();
  void watch(void Function() onChange);
  Future<void> dispose();
}

class SupabaseParkingRepository implements ParkingRepository {
  SupabaseParkingRepository(this.client)
    : _userId = client.auth.currentUser!.id;
  final SupabaseClient client;
  final String _userId;
  RealtimeChannel? _channel;
  @override
  bool get isDemo => false;
  @override
  String get userId => _userId;
  @override
  String? get accountName {
    final user = client.auth.currentUser;
    if (user?.id != _userId) return null;
    return accountDisplayName(user) ??
        (_appleNameUser == _userId ? _appleName : null);
  }

  @override
  Map<String, dynamic>? widgetSession(Vehicle vehicle) {
    final session = client.auth.currentSession;
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    if (session == null ||
        session.user.id != _userId ||
        session.expiresAt == null ||
        session.isExpired ||
        url.isEmpty ||
        key.isEmpty) {
      return null;
    }
    return {
      'url': url,
      'publishableKey': key,
      'accessToken': session.accessToken,
      'expiresAt': session.expiresAt,
      'userId': _userId,
      'vehicleId': vehicle.id,
      'floors': vehicle.floors,
      'zones': vehicle.zones,
    };
  }

  @override
  Future<List<Vehicle>> vehicles() async =>
      (await client
              .from('vehicles')
              .select('*,apartments(*)')
              .order('created_at'))
          .map(Vehicle.fromJson)
          .toList();
  @override
  Future<List<ParkingRecord>> records(String vehicleId) async =>
      (await client
              .from('parking_records')
              .select()
              .eq('vehicle_id', vehicleId)
              .order('created_at', ascending: false)
              .order('id', ascending: false)
              .limit(200))
          .map(ParkingRecord.fromJson)
          .toList();
  @override
  Future<List<FamilyMember>> members(String vehicleId) async =>
      (await client.rpc(
                'list_vehicle_members',
                params: {'p_vehicle_id': vehicleId},
              )
              as List)
          .map(
            (e) => FamilyMember.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();

  void _requireSameUser() {
    if (client.auth.currentUser?.id != _userId) {
      throw const AppException('로그인 상태가 변경되었어요. 다시 로그인해 주세요.');
    }
  }

  @override
  Future<String> profileName() async {
    _requireSameUser();
    final profile = await client
        .from('profiles')
        .select('nickname')
        .eq('id', _userId)
        .maybeSingle();
    return profile?['nickname'] as String? ?? '';
  }

  @override
  Future<void> updateProfileName(String name) async {
    final nickname = validatedProfileName(name);
    _requireSameUser();
    final updated = await client
        .from('profiles')
        .update({'nickname': nickname})
        .eq('id', _userId)
        .select('nickname')
        .maybeSingle();
    if (updated != null) return;
    // New accounts may not have created or joined a vehicle yet. Do not upsert
    // id: the database intentionally grants UPDATE only on nickname.
    _requireSameUser();
    await client.from('profiles').insert({'id': _userId, 'nickname': nickname});
  }

  @override
  Future<String> createVehicle(
    String apartment,
    String plate,
    String name,
    String nickname,
  ) async {
    _requireSameUser();
    return await client.rpc(
          'create_vehicle_with_membership',
          params: {
            'p_apartment_name': apartment,
            'p_plate_number': plate,
            'p_nickname': name,
            'p_profile_nickname': nickname,
          },
        )
        as String;
  }

  @override
  Future<ParkingRecord> save(
    String vehicleId,
    ParkingDraft draft,
    String key,
  ) async => ParkingRecord.fromJson(
    Map<String, dynamic>.from(
      await client.rpc(
            'create_parking_record_and_set_latest',
            params: {
              'p_vehicle_id': vehicleId,
              'p_floor': draft.floor,
              'p_zone': draft.zone,
              'p_spot': draft.spot.trim(),
              'p_note': draft.note.trim(),
              'p_idempotency_key': key,
            },
          )
          as Map,
    ),
  );
  @override
  Future<Map<String, dynamic>> invite(String vehicleId) async {
    final result = Map<String, dynamic>.from(
      await client.rpc(
            'create_invite_securely',
            params: {'p_vehicle_id': vehicleId},
          )
          as Map,
    );
    if (result['ok'] == false) {
      throw const AppException('초대를 너무 자주 만들었어요. 잠시 후 다시 시도해 주세요.');
    }
    return result;
  }

  @override
  Future<String> join(String code) async {
    _requireSameUser();
    final result = Map<String, dynamic>.from(
      await client.rpc(
            'redeem_invite_securely',
            params: {'p_code': code.trim()},
          )
          as Map,
    );
    if (result['ok'] != true) {
      throw result['error'] == 'rate_limited'
          ? const AppException('시도가 많아 잠시 제한되었어요. 10분 뒤 다시 시도해 주세요.')
          : result['error'] == 'already_has_vehicle'
          ? const AppException('이미 연결된 차량이 있어요. 한 계정에는 차량 한 대만 등록할 수 있어요.')
          : const InvalidInviteException();
    }
    return result['vehicle_id'] as String;
  }

  @override
  Future<void> setIcon(String vehicleId, String icon) async {
    await client.rpc(
      'set_vehicle_icon',
      params: {'p_vehicle_id': vehicleId, 'p_icon_id': icon},
    );
  }

  @override
  Future<void> removeMember(String vehicleId, String userId) async {
    await client.rpc(
      'remove_member',
      params: {'p_vehicle_id': vehicleId, 'p_user_id': userId},
    );
  }

  @override
  Future<void> leave(String vehicleId) async {
    await client.rpc('leave_vehicle', params: {'p_vehicle_id': vehicleId});
  }

  @override
  Future<void> updateApartment(
    String vehicleId,
    String name,
    List<String> floors,
    List<String> zones,
  ) async {
    await client.rpc(
      'update_apartment',
      params: {
        'p_vehicle_id': vehicleId,
        'p_name': name,
        'p_allowed_floors': floors,
        'p_allowed_zones': zones,
      },
    );
  }

  @override
  Future<void> deleteAccount({
    Future<AppleCredential?> Function()? reauthenticateApple,
    Future<bool> Function(AppleDisconnectFailure failure)?
    confirmManualAppleDisconnect,
  }) async {
    _requireSameUser();
    final session = client.auth.currentSession;
    if (session == null || session.accessToken.isEmpty || session.isExpired) {
      throw const AppleDisconnectFailure('session_invalid');
    }
    final bearer = 'Bearer ${session.accessToken}';
    var invalidated = false;
    final subscription = client.auth.onAuthStateChange.listen(
      (state) {
        if (state.session?.user.id != _userId ||
            state.event == AuthChangeEvent.signedOut ||
            (state.event == AuthChangeEvent.signedIn &&
                !identical(state.session, session))) {
          invalidated = true;
        }
      },
      onError: (Object _) {
        invalidated = true;
      },
    );
    void requireCurrent() {
      if (invalidated || client.auth.currentUser?.id != _userId) {
        throw const AppleDisconnectFailure('session_invalid');
      }
    }

    try {
      final user = (await client.auth.getUser(session.accessToken)).user;
      requireCurrent();
      if (user == null || user.id != _userId) {
        throw const AppleDisconnectFailure('session_invalid');
      }
      final identities = user.identities;
      if (identities == null) {
        throw const AppleDisconnectFailure('apple_verification_failed');
      }
      final usesApple = identities.any((i) => i.provider == 'apple');
      if (usesApple) {
        AppleDisconnectFailure? failure;
        if (reauthenticateApple == null) {
          failure = const AppleDisconnectFailure('apple_unavailable');
        } else {
          AppleCredential? credential;
          try {
            credential = await reauthenticateApple();
          } on PlatformException catch (error) {
            requireCurrent();
            if (!const {
              'apple_sign_in_unavailable',
              'apple_sign_in_failed',
              'unsupported',
            }.contains(error.code)) {
              rethrow;
            }
            failure = const AppleDisconnectFailure('apple_unavailable');
          }
          requireCurrent();
          if (failure == null && credential == null) {
            throw const AccountDeletionCancelled();
          }
          if (credential != null) {
            try {
              final response = await client.functions.invoke(
                'apple-disconnect',
                headers: {'Authorization': bearer},
                body: {
                  'authorizationCode': credential.authorizationCode,
                  'rawNonce': credential.rawNonce,
                },
              );
              if (response.data is! Map || response.data['ok'] != true) {
                failure = const AppleDisconnectFailure(
                  'apple_verification_failed',
                );
              }
            } on FunctionException catch (error) {
              final details = error.details;
              failure = AppleDisconnectFailure(
                error.status == 401
                    ? 'session_invalid'
                    : details is Map && details['error'] is String
                    ? details['error'] as String
                    : 'apple_unavailable',
              );
            } on Object {
              failure = const AppleDisconnectFailure('apple_unavailable');
            }
            requireCurrent();
          }
        }
        if (failure != null) {
          if (!failure.allowsManualDisconnect ||
              confirmManualAppleDisconnect == null) {
            throw failure;
          }
          final confirmed = await confirmManualAppleDisconnect(failure);
          requireCurrent();
          if (!confirmed) throw const AccountDeletionCancelled();
        }
      }
      requireCurrent();
      // A request already in flight may finish after switching accounts, but its
      // bearer must always belong to the account that requested deletion.
      await client.rpc('delete_my_account').setHeader('Authorization', bearer);
      if (!invalidated && client.auth.currentUser?.id == _userId) {
        try {
          // GoTrue removes this session synchronously before its first await.
          await client.auth.signOut(scope: SignOutScope.local);
        } on Object {
          // The server confirmed deletion. Network cleanup cannot undo it.
        }
      }
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<void> signOut() {
    _requireSameUser();
    return client.auth.signOut();
  }

  @override
  void watch(void Function() onChange) {
    _channel = client
        .channel('parking-${const Uuid().v4()}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vehicles',
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vehicle_members',
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'parking_records',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  @override
  Future<void> dispose() async {
    if (_channel != null) await client.removeChannel(_channel!);
  }
}

class DemoParkingRepository implements ParkingRepository {
  DemoParkingRepository(this.preferences);
  final SharedPreferences preferences;
  static const storageKey = 'carcar.demo.v1';
  @override
  bool get isDemo => true;
  @override
  String get userId => 'demo-me';
  @override
  String? get accountName => null;
  @override
  Map<String, dynamic>? widgetSession(Vehicle vehicle) => null;
  late List<Vehicle> _vehicles;
  late List<ParkingRecord> _records;
  final Map<String, ParkingRecord> _saved = {};
  String _profileName = '나';
  Future<void> initialize() async {
    var loaded = false;
    var migrateOptions = false;
    try {
      final stored = preferences.getString(storageKey);
      if (stored != null) {
        final data = jsonDecode(stored) as Map<String, dynamic>;
        migrateOptions = (data['parkingOptionsVersion'] as int? ?? 0) < 1;
        final savedName = data['profileName'];
        _profileName = savedName is String && savedName.trim().isNotEmpty
            ? validatedProfileName(savedName)
            : '나';
        _vehicles = (data['vehicles'] as List).map((e) {
          final vehicle = Vehicle.fromJson(Map<String, dynamic>.from(e as Map));
          if (!migrateOptions) return vehicle;
          // Only migrate known demo defaults once; preserve later custom settings.
          final legacyFloors =
              listEquals(vehicle.floors, const [
                'F5',
                'F4',
                'F3',
                'F2',
                'F1',
                'B1',
                'B2',
                'B3',
                'B4',
                'B5',
                'B6',
              ]) ||
              listEquals(vehicle.floors, const ['B1', 'B2', 'B3', 'B4']);
          final legacyZones = listEquals(vehicle.zones, const [
            'A',
            'B',
            'C',
            'D',
            'E',
          ]);
          return vehicle.copyWith(
            floors: legacyFloors ? defaultFloors : vehicle.floors,
            zones: legacyZones ? defaultZones : vehicle.zones,
          );
        }).toList();
        _records = (data['records'] as List)
            .map(
              (e) =>
                  ParkingRecord.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
        loaded = true;
      }
    } on Object {
      /* A corrupted demo must never prevent opening the real app. */
    }
    if (loaded) {
      // A write failure must not be mistaken for corrupt data and reset history.
      if (migrateOptions) await _persist();
      return;
    }
    final now = DateTime.now();
    _profileName = '나';
    _records = List.generate(
      5,
      (i) => ParkingRecord(
        id: 'demo-record-$i',
        vehicleId: 'demo-car',
        floor: ['B2', 'B1', 'B3', 'B2', 'B1'][i],
        zone: ['C', 'A', 'D', 'B', 'A'][i],
        spot: ['24', '12', '08', '32', '15'][i],
        note: i == 0 ? '엘리베이터 입구 가까이에 있어요.' : '',
        createdBy: i % 2 == 0 ? userId : 'demo-family',
        createdAt: now.subtract(Duration(hours: i * 23 + 1)),
      ),
    );
    _vehicles = [
      Vehicle(
        id: 'demo-car',
        ownerId: userId,
        name: '우리 가족 차',
        plate: '123가 4567',
        apartment: '우리집 아파트',
        latestId: _records.first.id,
      ),
    ];
    await _persist();
  }

  Future<void> _persist() async {
    final ok = await preferences.setString(
      storageKey,
      jsonEncode({
        'parkingOptionsVersion': 1,
        'profileName': _profileName,
        'vehicles': _vehicles.map((v) => v.toJson()).toList(),
        'records': _records.map((r) => r.toJson()).toList(),
      }),
    );
    if (!ok) throw const AppException('기기에 저장하지 못했어요. 저장 공간을 확인해 주세요.');
  }

  @override
  Future<List<Vehicle>> vehicles() async => List.of(_vehicles);
  @override
  Future<List<ParkingRecord>> records(String vehicleId) async =>
      _records.where((r) => r.vehicleId == vehicleId).toList();
  @override
  Future<List<FamilyMember>> members(String vehicleId) async => [
    FamilyMember(id: userId, name: _profileName, owner: true),
    const FamilyMember(id: 'demo-family', name: '가족 · 예시', owner: false),
  ];
  @override
  Future<String> profileName() async => _profileName;
  @override
  Future<void> updateProfileName(String name) async {
    final nickname = validatedProfileName(name);
    final previous = _profileName;
    _profileName = nickname;
    try {
      await _persist();
    } on Object {
      _profileName = previous;
      rethrow;
    }
  }

  @override
  Future<String> createVehicle(
    String apartment,
    String plate,
    String name,
    String nickname,
  ) async {
    if (_vehicles.isNotEmpty) {
      throw const AppException('계정마다 차량 한 대만 등록하거나 참여할 수 있어요.');
    }
    final id = const Uuid().v4();
    _vehicles.add(
      Vehicle(
        id: id,
        ownerId: userId,
        name: name,
        plate: plate,
        apartment: apartment,
      ),
    );
    await _persist();
    return id;
  }

  @override
  Future<ParkingRecord> save(
    String vehicleId,
    ParkingDraft draft,
    String key,
  ) async {
    if (_saved.containsKey(key)) return _saved[key]!;
    final vehicle = _vehicles.firstWhere((v) => v.id == vehicleId);
    final error = draft.validate(vehicle);
    if (error != null) throw AppException(error);
    final record = ParkingRecord(
      id: const Uuid().v4(),
      vehicleId: vehicleId,
      floor: draft.floor,
      zone: draft.zone,
      spot: draft.spot.trim(),
      note: draft.note.trim(),
      createdBy: userId,
      createdAt: DateTime.now(),
    );
    final previousVehicles = List<Vehicle>.of(_vehicles);
    _records.insert(0, record);
    _vehicles = _vehicles
        .map((v) => v.id == vehicleId ? v.copyWith(latestId: record.id) : v)
        .toList();
    try {
      await _persist();
    } on Object {
      _records.remove(record);
      _vehicles = previousVehicles;
      rethrow;
    }
    _saved[key] = record;
    return record;
  }

  @override
  Future<Map<String, dynamic>> invite(String vehicleId) async =>
      throw const AppException('가족 초대는 실제 계정으로 로그인한 후 사용할 수 있어요.');
  @override
  Future<String> join(String code) async =>
      throw const AppException('가족 참여는 실제 계정으로 로그인해 주세요.');
  @override
  Future<void> setIcon(String vehicleId, String icon) async {
    if (!vehicleColors.containsKey(icon)) {
      throw const AppException('지원하지 않는 아이콘이에요.');
    }
    _vehicles = _vehicles
        .map((v) => v.id == vehicleId ? v.copyWith(icon: icon) : v)
        .toList();
    await _persist();
  }

  @override
  Future<void> removeMember(String vehicleId, String userId) async =>
      throw const AppException('체험용 가족은 변경할 수 없어요.');
  @override
  Future<void> leave(String vehicleId) async =>
      throw const AppException('체험을 마치려면 설정에서 체험 종료를 눌러 주세요.');
  @override
  Future<void> updateApartment(
    String vehicleId,
    String name,
    List<String> floors,
    List<String> zones,
  ) async {
    _vehicles = _vehicles
        .map(
          (v) => v.id == vehicleId
              ? v.copyWith(apartment: name, floors: floors, zones: zones)
              : v,
        )
        .toList();
    await _persist();
  }

  @override
  Future<void> deleteAccount({
    Future<AppleCredential?> Function()? reauthenticateApple,
    Future<bool> Function(AppleDisconnectFailure failure)?
    confirmManualAppleDisconnect,
  }) async {
    final removed = await preferences.remove(storageKey);
    if (!removed) {
      throw const AppException('체험 데이터를 지우지 못했어요. 다시 시도해 주세요.');
    }
    _vehicles.clear();
    _records.clear();
    _saved.clear();
    _profileName = '나';
  }

  @override
  Future<void> signOut() async {}
  @override
  void watch(void Function() onChange) {}
  @override
  Future<void> dispose() async {}
}

class AppException implements Exception {
  const AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The server refused the invitation itself: already used, expired or unknown.
/// Retrying the same invitation cannot succeed.
class InvalidInviteException extends AppException {
  const InvalidInviteException()
    : super('이미 사용했거나 24시간이 지난 초대예요. 가족에게 새 초대를 받아 주세요.');
}

String validatedProfileName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed.runes.length > 40) {
    throw const AppException('가족에게 표시할 이름을 1~40자로 입력해 주세요.');
  }
  return trimmed;
}

/// The name the sign-in provider stored for this account (Google does, Apple
/// does not), cut to the profile name limit. Only ever a suggestion the user
/// can edit; null when there is none.
String? accountDisplayName(User? user) {
  for (final key in const ['full_name', 'name']) {
    final value = user?.userMetadata?[key];
    if (value is String && value.trim().isNotEmpty) {
      return String.fromCharCodes(value.trim().runes.take(40)).trim();
    }
  }
  return null;
}

// Apple shares the name only at the first authorization. It lives in memory
// for this app run and this account only; never persist or log it.
String? _appleNameUser, _appleName;
void rememberAppleName(String userId, String? fullName) {
  final name = fullName?.trim() ?? '';
  if (name.isEmpty) return;
  _appleNameUser = userId;
  _appleName = String.fromCharCodes(name.runes.take(40)).trim();
}

/// The server rejected the plate itself (wrong format or already registered),
/// so the message belongs next to the plate field.
bool isPlateError(Object error) =>
    error is PostgrestException &&
    (error.message.contains('plate_already_registered') ||
        error.message.contains('invalid_plate'));

String friendlyError(Object error) {
  if (error is AppException) return error.message;
  if (error is AppleDisconnectFailure) return error.message;
  if (error is AuthException) return '로그인을 완료하지 못했어요. 잠시 후 다시 시도해 주세요.';
  if (error is PostgrestException) {
    if (error.message.contains('already_has_vehicle')) {
      return '이미 연결된 차량이 있어요. 계정마다 차량 한 대만 사용할 수 있어요.';
    }
    if (error.message.contains('plate_already_registered')) {
      return '이미 등록된 차량번호예요. 처음 등록한 가족에게 초대 링크나 코드를 받아 주세요.';
    }
    if (error.message.contains('invalid_plate')) {
      return '차량 번호를 확인해 주세요. 예: 123가 4567';
    }
    if (error.code == '42501' ||
        error.message.contains('not_member') ||
        error.message.contains('not_owner')) {
      return '이 차량에 접근할 권한이 없어요. 가족 초대를 확인해 주세요.';
    }
    if (error.code == '22023' || error.code == '23514') {
      return '입력한 내용이 허용된 형식인지 확인해 주세요.';
    }
  }
  return '연결이 불안정해요. 다시 시도해 주세요.';
}
