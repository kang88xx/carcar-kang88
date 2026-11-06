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
  await showSheetDialog<void>(
    context,
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
  final _spot = TextEditingController();
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
        floors: widget.controller.vehicle!.floors
            .where((floor) => floor != 'B6')
            .toList(),
        zones: widget.controller.vehicle!.zones,
      );
      setState(() {
        _floor = suggestion.floor ?? _floor;
        _zone = suggestion.zone ?? _zone;
        if (suggestion.spot != null) _spot.text = suggestion.spot!;
        _dirty = _dirty || suggestion.found;
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
    final locked = _busy || _scanning;
    return PopScope(
      canPop: !_busy && !_scanning && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: SheetDialog(
        title: '어디에 주차했나요?',
        subtitle: vehicle?.name ?? '주차 기록',
        closeTooltip: '기록 창 닫기',
        onClose: locked ? null : _close,
        footer: _confirmation(),
        horizontalPadding: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: locked ? null : _capture,
                    icon: _scanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_outlined, size: 20),
                    label: Text(_scanning ? '글자를 읽고 있어요' : '표지판 촬영'),
                  ),
                ),
                if (NativeBridge.supportsOcr) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '앨범에서 선택',
                    onPressed: locked ? null : () => _capture(gallery: true),
                    style: IconButton.styleFrom(
                      backgroundColor: Palette.soft,
                      fixedSize: const Size(52, 52),
                    ),
                    icon: const Icon(Icons.photo_library_outlined, size: 22),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            if (_ocrNotice != null) StatusNotice(_ocrNotice!),
            _floorChoices(vehicle?.floors ?? []),
            const SizedBox(height: 16),
            _zoneChoices(vehicle?.zones ?? []),
            const SizedBox(height: 16),
            TextField(
              controller: _spot,
              maxLength: 20,
              enabled: !locked,
              decoration: const InputDecoration(
                labelText: '주차 번호 (선택)',
                hintText: '예: 24',
              ),
              onChanged: (_) => setState(() {
                _dirty = true;
                _error = null;
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _confirmation() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_error != null) StatusNotice(_error!, error: true),
      BusyButton(
        label: widget.controller.isDemo ? '체험 기록 저장' : '주차 기록 저장',
        busy: _busy,
        onPressed: _scanning ? null : _save,
        icon: Icons.check_rounded,
      ),
      const SizedBox(height: 8),
      Text(
        widget.controller.isDemo ? '이 기기에만 저장돼요.' : '저장 후 가족과 위치를 공유해요.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  void _selectFloor(String value) => setState(() {
    _floor = value;
    _error = null;
    _dirty = true;
  });

  void _selectZone(String value) => setState(() {
    _zone = value;
    _error = null;
    _dirty = true;
  });

  Widget _floorChoices(List<String> options) {
    final ground = options
        .where((value) => RegExp(r'^F[1-9]\d*$').hasMatch(value))
        .toList();
    final basement = options
        .where(
          (value) => value != 'B6' && RegExp(r'^B[1-9]\d*$').hasMatch(value),
        )
        .toList();
    final other = options
        .where(
          (value) =>
              value != 'B6' &&
              !ground.contains(value) &&
              !basement.contains(value),
        )
        .toList();
    final groups = <(String, List<String>, int)>[
      if (ground.isNotEmpty) ('지상', ground, 5),
      if (basement.isNotEmpty) ('지하', basement, 5),
      if (other.isNotEmpty) ('기타 층', other, 1),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < groups.length; index++) ...[
          if (index > 0) const SizedBox(height: 16),
          Text(
            groups[index].$1,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          _choiceRows(groups[index].$2, groups[index].$3, _floor, _selectFloor),
        ],
      ],
    );
  }

  Widget _zoneChoices(List<String> options) {
    final latin = options
        .where((value) => RegExp(r'^[A-Z]$').hasMatch(value))
        .toList();
    final korean = options
        .where((value) => RegExp(r'^[가-힣]$').hasMatch(value))
        .toList();
    final other = options
        .where((value) => !latin.contains(value) && !korean.contains(value))
        .toList();
    final groups = [
      if (latin.isNotEmpty) (latin, 6),
      if (korean.isNotEmpty) (korean, 6),
      if (other.isNotEmpty) (other, 1),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '구역',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < groups.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          _choiceRows(groups[index].$1, groups[index].$2, _zone, _selectZone),
        ],
      ],
    );
  }

  Widget _choiceRows(
    List<String> options,
    int columns,
    String? selected,
    ValueChanged<String> changed,
  ) {
    // Default short labels use fixed rows. Preserve custom apartment labels
    // with a full-width choice instead of wrapping their text across lines.
    final count = options.any((value) => value.runes.length > 3) ? 1 : columns;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 4.0;
        final width = (constraints.maxWidth - gap * (count - 1)) / count;
        return Column(
          children: [
            for (var offset = 0; offset < options.length; offset += count) ...[
              if (offset > 0) const SizedBox(height: 8),
              Row(
                children: [
                  for (
                    var index = offset;
                    index < options.length && index < offset + count;
                    index++
                  ) ...[
                    if (index > offset) const SizedBox(width: gap),
                    SizedBox(
                      width: width,
                      height: 48,
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: headlineMaxTextScale,
                        child: ChoiceChip(
                          label: SizedBox(
                            width: double.infinity,
                            child: Text(
                              options[index],
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 15, height: 1.2),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          labelPadding: EdgeInsets.zero,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          selected: selected == options[index],
                          onSelected: _busy || _scanning
                              ? null
                              : (_) => changed(options[index]),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
