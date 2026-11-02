import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../app/theme.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/native_bridge.dart';
import '../core/repository.dart';
import '../shared/components.dart';

Future<void> openParkingForm(
  BuildContext context,
  AppController controller, {
  bool camera = false,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        ParkingForm(controller: controller, startWithCamera: camera),
  );
}

class ParkingForm extends StatefulWidget {
  const ParkingForm({
    super.key,
    required this.controller,
    this.startWithCamera = false,
  });
  final AppController controller;
  final bool startWithCamera;
  @override
  State<ParkingForm> createState() => _ParkingFormState();
}

class _ParkingFormState extends State<ParkingForm> {
  String? _floor, _zone, _error, _ocrNotice;
  final _spot = TextEditingController(), _note = TextEditingController();
  bool _busy = false, _scanning = false, _dirty = false;
  late final String _vehicleId;
  @override
  void initState() {
    super.initState();
    _vehicleId = widget.controller.vehicle!.id;
    if (widget.startWithCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
    }
  }

  @override
  void dispose() {
    _spot.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _capture({bool gallery = false}) async {
    if (!NativeBridge.supportsOcr) {
      setState(
        () => _ocrNotice =
            '사진 인식은 Android·iPhone 앱에서 사용할 수 있어요. 아래에서 직접 선택해 주세요.',
      );
      return;
    }
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final photo = await ImagePicker().pickImage(
        source: gallery ? ImageSource.gallery : ImageSource.camera,
        maxWidth: 2200,
        imageQuality: 90,
      );
      if (photo == null) return;
      final text = await NativeBridge.recognizeText(
        photo.path,
      ).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      final suggestion = parseParkingText(
        text,
        floors: widget.controller.vehicle!.floors,
        zones: widget.controller.vehicle!.zones,
      );
      setState(() {
        _floor = suggestion.floor ?? _floor;
        _zone = suggestion.zone ?? _zone;
        if (suggestion.spot != null) _spot.text = suggestion.spot!;
        _dirty = true;
        _ocrNotice = suggestion.found
            ? '사진에서 읽은 내용이에요. 실제 위치와 맞는지 확인하고 수정해 주세요.'
            : '표지판을 정확하게 읽지 못했어요. 직접 선택하거나 더 가까이서 촬영해 주세요.';
      });
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () => _error =
              e.code.contains('denied') || e.code.contains('permission')
              ? '카메라·사진 접근이 허용되지 않았어요. 기기 설정에서 허용하거나 직접 입력해 주세요.'
              : '사진을 읽지 못했어요. 다시 촬영하거나 직접 입력해 주세요.',
        );
      }
    } on Object {
      if (mounted) setState(() => _error = '사진을 읽지 못했어요. 직접 선택해서 기록할 수 있어요.');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _close() async {
    if (_busy || _scanning) return;
    if (_dirty &&
        !await confirmAction(
          context,
          title: '기록을 그만둘까요?',
          message: '입력한 내용은 저장되지 않아요.',
          action: '나가기',
        )) {
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    if (widget.controller.vehicle?.id != _vehicleId) {
      setState(() => _error = '선택된 차량이 변경되었어요. 창을 닫고 다시 기록해 주세요.');
      return;
    }
    final draft = ParkingDraft(
      floor: _floor ?? '',
      zone: _zone ?? '',
      spot: _spot.text.trim(),
      note: _note.text.trim(),
    );
    final validation = draft.validate(widget.controller.vehicle!);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final record = await widget.controller.save(draft);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(
        context,
        widget.controller.isDemo
            ? '체험 기록을 이 기기에 저장했어요.'
            : '${record.position}에 주차 기록을 저장했어요.',
      );
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.controller.vehicle;
    return PopScope(
      canPop: !_busy && !_scanning && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '어디에 주차했나요?',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: _busy || _scanning ? null : _close,
                      tooltip: '기록 창 닫기',
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Text(
                  vehicle?.name ?? '주차 기록',
                  style: const TextStyle(color: Palette.muted),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _busy || _scanning ? null : _capture,
                  icon: _scanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_camera_outlined),
                  label: Text(
                    _scanning ? '사진에서 글자를 읽고 있어요' : '표지판 촬영으로 빠르게 입력',
                  ),
                ),
                if (NativeBridge.supportsOcr)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy || _scanning
                          ? null
                          : () => _capture(gallery: true),
                      child: const Text('앨범에서 선택'),
                    ),
                  ),
                const SizedBox(height: 20),
                if (_ocrNotice != null) StatusNotice(_ocrNotice!),
                _choices(
                  '층수',
                  vehicle?.floors ?? [],
                  _floor,
                  (value) => setState(() {
                    _floor = value;
                    _error = null;
                    _dirty = true;
                  }),
                ),
                const SizedBox(height: 24),
                _choices(
                  '구역',
                  vehicle?.zones ?? [],
                  _zone,
                  (value) => setState(() {
                    _zone = value;
                    _error = null;
                    _dirty = true;
                  }),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _spot,
                  maxLength: 20,
                  enabled: !_busy && !_scanning,
                  decoration: const InputDecoration(
                    labelText: '주차 번호 (선택)',
                    hintText: '예: 24',
                  ),
                  onChanged: (_) => setState(() {
                    _dirty = true;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _note,
                  maxLength: 500,
                  enabled: !_busy && !_scanning,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '가족에게 남길 메모 (선택)',
                    hintText: '예: 엘리베이터 입구 옆',
                  ),
                  onChanged: (_) => setState(() {
                    _dirty = true;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Palette.soft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _floor != null && _zone != null
                        ? '$_floor · $_zone구역${_spot.text.trim().isEmpty ? '' : ' · ${_spot.text.trim()}번'}'
                        : '층수와 구역을 선택해 주세요.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (_error != null) StatusNotice(_error!, error: true),
                BusyButton(
                  label: widget.controller.isDemo
                      ? '이 위치로 체험 기록 저장'
                      : '이 위치로 주차 기록 저장',
                  busy: _busy,
                  onPressed: _scanning ? null : _save,
                  icon: Icons.check_rounded,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.controller.isDemo
                      ? '체험 데이터는 이 기기에만 저장돼요.'
                      : '저장이 완료되면 가족과 같은 위치를 확인할 수 있어요.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _choices(
    String label,
    List<String> options,
    String? selected,
    ValueChanged<String> changed,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: options
            .map(
              (value) => ChoiceChip(
                label: Text(
                  value,
                  style: TextStyle(
                    color: selected == value ? Colors.white : Palette.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                selected: selected == value,
                onSelected: _busy || _scanning ? null : (_) => changed(value),
              ),
            )
            .toList(),
      ),
    ],
  );
}
