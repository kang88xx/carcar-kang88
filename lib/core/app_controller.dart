import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'repository.dart';
import 'native_bridge.dart';

class AppController extends ChangeNotifier {
  AppController(this.repository, {this.preferences});
  final ParkingRepository repository;
  final SharedPreferences? preferences;
  bool _changingWidgetPermission = false;
  String get _widgetPreferenceKey =>
      'carcar.widget.quick_save.${repository.userId}';
  bool get widgetQuickSaveEnabled =>
      !isDemo && (preferences?.getBool(_widgetPreferenceKey) ?? false);
  List<Vehicle> vehicles = [];
  List<ParkingRecord> records = [];
  List<FamilyMember> members = [];
  String? selectedId, error, widgetWarning;
  String? iconWarning;
  bool appActive = true;
  bool _syncingIcon = false, _iconPending = false;
  bool loading = true, saving = false;
  DateTime? lastSynced;
  bool _disposed = false;
  bool get isDisposed => _disposed;
  int _generation = 0;
  int _nativeGeneration = 0;
  Timer? _refreshTimer;
  String? _pendingFingerprint, _pendingKey;
  Vehicle? get vehicle => vehicles.where((v) => v.id == selectedId).firstOrNull;
  ParkingRecord? get latest =>
      records.where((r) => r.id == vehicle?.latestId).firstOrNull;
  bool get isDemo => repository.isDemo;
  bool get isOwner => vehicle?.ownerId == repository.userId;
  String author(String id) =>
      members.where((m) => m.id == id).firstOrNull?.name ?? '이전 구성원';
  Future<void> initialize() async {
    repository.watch(
      () => _refreshTimer ??= Timer(const Duration(milliseconds: 300), () {
        _refreshTimer = null;
        unawaited(refresh());
      }),
    );
    await refresh();
  }

  Future<void> refresh({String? select}) async {
    final generation = ++_generation;
    loading = true;
    _notify();
    try {
      final fetched = await repository.vehicles();
      if (_disposed || generation != _generation) return;
      final wanted = select ?? selectedId;
      final selected =
          fetched.where((v) => v.id == wanted).firstOrNull ??
          fetched.firstOrNull;
      List<ParkingRecord> newRecords = [];
      List<FamilyMember> newMembers = [];
      if (selected != null) {
        // Membership is checked by both queries, including after a revoked invitation.
        final results = await Future.wait([
          repository.records(selected.id),
          repository.members(selected.id),
        ]);
        newRecords = results[0] as List<ParkingRecord>;
        newMembers = results[1] as List<FamilyMember>;
      }
      if (_disposed || generation != _generation) return;
      vehicles = fetched;
      selectedId = selected?.id;
      records = newRecords;
      members = newMembers;
      error = null;
      lastSynced = DateTime.now();
      await _syncSnapshot();
    } on Object catch (e) {
      if (_disposed || generation != _generation) return;
      error = friendlyError(e);
      // Never keep protected content visible after a confirmed authorization failure.
      if (error!.contains('권한')) {
        vehicles = [];
        records = [];
        members = [];
        selectedId = null;
        await _syncSnapshot();
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> selectVehicle(String id) async {
    if (id == selectedId) return;
    selectedId = id;
    records = [];
    members = [];
    _pendingKey = null;
    _pendingFingerprint = null;
    await _syncSnapshot();
    await refresh(select: id);
  }

  Future<ParkingRecord> save(ParkingDraft draft) async {
    if (saving) throw const AppException('이미 저장하고 있어요. 잠시만 기다려 주세요.');
    final current = vehicle;
    if (current == null) throw const AppException('먼저 차량을 등록해 주세요.');
    final validation = draft.validate(current);
    if (validation != null) throw AppException(validation);
    final fingerprint = '${current.id}\u0000${draft.fingerprint}';
    if (_pendingFingerprint != fingerprint) {
      _pendingFingerprint = fingerprint;
      _pendingKey = const Uuid().v4();
    }
    saving = true;
    _notify();
    try {
      final record = await repository.save(current.id, draft, _pendingKey!);
      if (_disposed) return record;
      _pendingFingerprint = null;
      _pendingKey = null;
      if (selectedId == current.id) {
        records = [record, ...records.where((r) => r.id != record.id)];
        vehicles = vehicles
            .map(
              (v) => v.id == current.id ? v.copyWith(latestId: record.id) : v,
            )
            .toList();
        error = null;
        lastSynced = DateTime.now();
        await _syncSnapshot();
      }
      unawaited(refresh());
      return record;
    } on Object catch (failure) {
      if (friendlyError(failure).contains('권한')) {
        vehicles = [];
        records = [];
        members = [];
        selectedId = null;
        error = friendlyError(failure);
        await _syncSnapshot();
      }
      rethrow;
    } finally {
      saving = false;
      _notify();
    }
  }

  Future<void> createVehicle(
    String apartment,
    String plate,
    String name,
    String nickname,
  ) async {
    if (_disposed) throw const AppException('로그인 상태가 바뀌었어요. 다시 시도해 주세요.');
    final id = await repository.createVehicle(
      apartment.trim(),
      plate.trim(),
      name.trim(),
      nickname.trim(),
    );
    await refresh(select: id);
  }

  Future<void> join(String code) async {
    if (_disposed) throw const AppException('로그인 상태가 바뀌었어요. 다시 시도해 주세요.');
    final id = await repository.join(code);
    await refresh(select: id);
  }

  Map<String, dynamic> get snapshot => {
    'userId': repository.userId,
    'vehicleId': vehicle?.id ?? '',
    'vehicleName': vehicle?.name ?? '',
    'floor': latest?.floor ?? '',
    'zone': latest?.zone ?? '',
    'spot': latest?.spot ?? '',
    'updatedAt': latest?.createdAt.toUtc().toIso8601String() ?? '',
    'isDemo': isDemo,
  };
  Future<void> _syncSnapshot() async {
    if (_disposed) return;
    final generation = ++_nativeGeneration;
    final current = vehicle;
    final currentSnapshot = snapshot;
    try {
      if (current == null) {
        await NativeBridge.clearSnapshot();
      } else {
        if (widgetQuickSaveEnabled) {
          final context = repository.widgetSession(current);
          if (context != null) {
            await NativeBridge.updateWidgetSession(context);
          } else {
            await NativeBridge.clearWidgetSession();
          }
        } else {
          await NativeBridge.clearWidgetSession();
        }
        if (_disposed || generation != _nativeGeneration) return;
        await NativeBridge.updateSnapshot(currentSnapshot);
      }
      if (!_disposed && generation == _nativeGeneration) widgetWarning = null;
    } on Object {
      if (!_disposed && generation == _nativeGeneration) {
        widgetWarning = '위젯을 갱신하지 못했어요. 현재 위치는 앱에서 확인해 주세요.';
      }
    }
    unawaited(syncFloorIcon());
  }

  /// The confirmed record is authoritative. Icon failure never rolls back a save.
  Future<void> syncFloorIcon() async {
    if (_disposed || !appActive || !NativeBridge.supportsLauncherIcons) return;
    _iconPending = true;
    if (_syncingIcon) return;
    _syncingIcon = true;
    try {
      while (_iconPending && !_disposed && appActive) {
        _iconPending = false;
        final target = NativeBridge.iconForFloor(latest?.floor);
        try {
          await NativeBridge.syncLauncherIcon(
            target,
            isCurrent: () =>
                !_disposed &&
                appActive &&
                target == NativeBridge.iconForFloor(latest?.floor),
          );
          if (_disposed) break;
          iconWarning = null;
          if (target != NativeBridge.iconForFloor(latest?.floor)) {
            _iconPending = true;
          }
        } on Object {
          if (!_disposed) {
            iconWarning = '주차 기록은 저장되어 있어요. 앱 아이콘은 설정에서 다시 맞출 수 있어요.';
          }
        }
      }
    } finally {
      _syncingIcon = false;
      _notify();
    }
  }

  Future<void> setWidgetQuickSaveEnabled(bool enabled) async {
    if (_disposed) throw const AppException('로그인 상태가 바뀌었어요. 다시 시도해 주세요.');
    if (_changingWidgetPermission) return;
    if (preferences == null || !NativeBridge.supportsOcr) {
      throw const AppException('위젯 바로 기록은 휴대폰 앱에서 설정해 주세요.');
    }
    if (enabled && (isDemo || vehicle == null)) {
      throw const AppException('실제 계정으로 로그인하고 차량을 선택해 주세요.');
    }
    _changingWidgetPermission = true;
    _nativeGeneration++;
    try {
      if (enabled) {
        final context = repository.widgetSession(vehicle!);
        if (context == null) {
          throw const AppException('로그인을 갱신한 뒤 다시 허용해 주세요.');
        }
        await NativeBridge.updateWidgetSession(context);
      } else {
        await NativeBridge.clearWidgetSession();
      }
      if (_disposed) throw const AppException('로그인 상태가 바뀌었어요. 다시 시도해 주세요.');
      if (!await preferences!.setBool(_widgetPreferenceKey, enabled)) {
        await NativeBridge.clearWidgetSession();
        throw const AppException('기기 설정을 저장하지 못했어요. 다시 시도해 주세요.');
      }
      widgetWarning = null;
      await _syncSnapshot();
    } finally {
      _changingWidgetPermission = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _nativeGeneration++;
    _refreshTimer?.cancel();
    unawaited(repository.dispose());
    super.dispose();
  }
}
