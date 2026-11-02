import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../core/app_controller.dart';
import '../core/native_bridge.dart';
import '../shared/components.dart';

/// Shows the automatic floor icon; it is never a shared vehicle color selector.
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
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Palette.green,
                  borderRadius: BorderRadius.circular(19),
                ),
                alignment: Alignment.center,
                child: Text(
                  supportedFloor ? floor! : 'P',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '주차 위치를 저장하면 앱 아이콘도 해당 층으로 바뀌어요. 지상 F1~F5, 지하 B1~B6을 표시해요.',
            ),
            const SizedBox(height: 12),
            const Text(
              '다른 가족이 남긴 위치는 앱을 다시 열 때 맞춰요. 지원 범위 밖의 층이나 기록이 없으면 기본 아이콘을 사용해요.',
            ),
            const SizedBox(height: 12),
            const Text(
              'iPhone에서는 아이콘 변경 안내가 표시될 수 있어요. 홈 화면에 반영되는 시점은 기기에 따라 다를 수 있어요.',
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

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.controller.syncFloorIcon();
    if (!mounted) return;
    setState(() => _busy = false);
    showMessage(
      context,
      widget.controller.iconWarning ?? '현재 주차 층수로 앱 아이콘을 확인했어요.',
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.apps_rounded, color: Palette.green),
        title: const Text('주차 층수 앱 아이콘'),
        subtitle: Text(
          widget.controller.iconWarning ?? '저장한 층수에 맞춰 자동으로 바뀌어요.',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: _details,
      ),
      if (widget.controller.iconWarning != null)
        TextButton.icon(
          onPressed: _busy ? null : _retry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('아이콘 다시 맞추기'),
        ),
    ],
  );
}
