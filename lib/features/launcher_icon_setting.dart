import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../core/app_controller.dart';
import '../core/native_bridge.dart';
import '../core/repository.dart';
import '../shared/components.dart';

/// The floor icon of this device: a switch on iPhone, automatic on Android.
/// It is never a shared vehicle color selector.
class LauncherIconSetting extends StatefulWidget {
  const LauncherIconSetting({super.key, required this.controller});
  final AppController controller;
  @override
  State<LauncherIconSetting> createState() => _LauncherIconSettingState();
}

class _LauncherIconSettingState extends State<LauncherIconSetting> {
  bool _busy = false;
  Future<void> _details() async {
    final floor = widget.controller.latest?.floor;
    final supportedFloor = NativeBridge.iconForFloor(floor) != null;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('주차 층수 앱 아이콘'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: PinMark(size: 76, floor: supportedFloor ? floor : null),
            ),
            const SizedBox(height: 20),
            const Text(
              '주차 위치를 저장하면 앱 홈 상단의 핀이 바로 해당 층으로 바뀌고, 앱 아이콘도 같은 층으로 맞춰요. 지상 F1~F5, 지하 B1~B6을 표시해요.',
            ),
            const SizedBox(height: 12),
            const Text(
              '다른 가족이 남긴 위치는 앱을 다시 열 때 맞춰요. 지원 범위 밖의 층이나 기록이 없으면 기본 아이콘을 사용해요.',
            ),
            const SizedBox(height: 12),
            const Text(
              '홈 화면에 반영되는 시점은 기기에 따라 다를 수 있어요.',
              style: TextStyle(fontSize: 12, height: 1.6, color: Palette.muted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.controller.setFloorIconEnabled(enabled);
    } on Object catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.controller.syncFloorIcon();
    if (!mounted) return;
    setState(() => _busy = false);
    showMessage(context, widget.controller.iconWarning ?? '앱 아이콘을 확인했어요.');
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (NativeBridge.floorIconIsOptIn)
        SwitchRow(
          icon: Icons.apps_rounded,
          title: '주차 층수 앱 아이콘',
          subtitle:
              widget.controller.iconWarning ??
              '켜면 층이 바뀔 때마다 iPhone이 확인 창을 띄워요.',
          value: widget.controller.floorIconEnabled,
          onChanged: _busy ? null : _toggle,
        )
      else
        ActionRow(
          icon: Icons.apps_rounded,
          title: '주차 층수 앱 아이콘',
          subtitle: widget.controller.iconWarning ?? '저장한 층수에 맞춰 자동으로 바뀌어요.',
          onTap: _details,
        ),
      if (widget.controller.iconWarning != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('아이콘 다시 맞추기'),
            ),
          ),
        ),
    ],
  );
}
