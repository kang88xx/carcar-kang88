import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../core/models.dart';
import '../core/native_bridge.dart';
import '../shared/components.dart';

const _iconLabels = {
  'primary': '기본',
  'car_blue': '블루',
  'car_black': '블랙',
  'car_white': '화이트',
  'car_gold': '골드',
  'car_mint': '민트',
  'car_purple': '퍼플',
  'car_red': '레드',
  'car_gray': '그레이',
};

/// Local launcher preference. Selecting a shared vehicle never applies it.
class LauncherIconSetting extends StatefulWidget {
  const LauncherIconSetting({super.key, this.vehicleIconId});
  final String? vehicleIconId;

  @override
  State<LauncherIconSetting> createState() => _LauncherIconSettingState();
}

class _LauncherIconSettingState extends State<LauncherIconSetting> {
  LauncherIconState? _state;
  bool _busy = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final state = await NativeBridge.launcherIconState();
      if (mounted) {
        setState(() {
          _state = state;
          _loadFailed = false;
        });
      }
    } on Object {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose() async {
    var selected = _state?.iconId ?? 'primary';
    final current = selected;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('홈 화면 앱 아이콘'),
          scrollable: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('이 기기의 아이콘만 바뀌어요. 가족의 앱과 차량 색상은 그대로예요.'),
              if (_iconLabels.containsKey(widget.vehicleIconId)) ...[
                const SizedBox(height: 10),
                Text(
                  '우리 차 색상 · ${_iconLabels[widget.vehicleIconId]}',
                  style: const TextStyle(color: Palette.muted, fontSize: 13),
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _iconLabels.entries.map((entry) {
                  final color = vehicleColors[entry.key] ?? Palette.green;
                  return ChoiceChip(
                    label: Text(entry.value),
                    avatar: CircleAvatar(backgroundColor: color),
                    selected: selected == entry.key,
                    onSelected: (_) => update(() => selected = entry.key),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: selected == current
                  ? null
                  : () => Navigator.pop(context, selected),
              child: Text(selected == 'primary' ? '기본으로 복원' : '이 기기에 적용'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    setState(() => _busy = true);
    try {
      final state = await NativeBridge.setLauncherIcon(
        choice == 'primary' ? null : choice,
      );
      if (mounted) {
        setState(() => _state = state);
        showMessage(context, '이 기기의 앱 아이콘을 바꿨어요.');
      }
    } on Object {
      if (mounted) {
        showMessage(context, '아이콘을 바꾸지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = _state?.supported ?? false;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.apps_rounded, color: Palette.green),
      title: const Text('앱 아이콘'),
      subtitle: Text(
        _busy
            ? '아이콘을 확인하고 있어요.'
            : _loadFailed
            ? '아이콘 정보를 읽지 못했어요. 눌러서 다시 확인해 주세요.'
            : supported
            ? '${_iconLabels[_state?.iconId ?? 'primary']} · 이 기기에만 적용돼요.'
            : '이 기기에서는 앱 아이콘 변경을 지원하지 않아요.',
      ),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : _loadFailed
          ? const Icon(Icons.refresh_rounded)
          : supported
          ? const Icon(Icons.chevron_right_rounded)
          : null,
      onTap: _busy
          ? null
          : _loadFailed
          ? _load
          : supported
          ? _choose
          : null,
    );
  }
}
