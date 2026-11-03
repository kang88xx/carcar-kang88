import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../core/device_notifications.dart';
import '../core/native_bridge.dart';
import '../core/repository.dart';
import '../shared/components.dart';

class NotificationSettings extends StatelessWidget {
  const NotificationSettings({
    super.key,
    this.controller,
    this.isDemo = false,
    this.onLiveDisabled,
  });
  final DeviceNotificationController? controller;
  final bool isDemo;
  final Future<void> Function()? onLiveDisabled;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null || isDemo || !c.supported) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GroupLabel('알림과 차량 찾기'),
          Surface(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 4,
              ),
              title: const Text(
                '가족 주차 알림',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                isDemo
                    ? '실제 계정으로 로그인한 휴대폰에서 설정할 수 있어요.'
                    : 'Android·iPhone 앱에서 설정할 수 있어요.',
                style: const TextStyle(fontSize: 12.5, color: Palette.muted),
              ),
              value: false,
              onChanged: null,
            ),
          ),
        ],
      );
    }
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final settings = c.settings;
        final enabled = c.initialized && !c.busy;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const GroupLabel('알림과 차량 찾기 · 현재 계정의 이 기기에만 적용'),
            Surface(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.loading) const LinearProgressIndicator(),
                  if (c.error != null)
                    StatusNotice(
                      c.error!,
                      error: true,
                      onRetry: c.busy ? null : c.refresh,
                    ),
                  if (c.warning != null) StatusNotice(c.warning!),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('가족 주차 알림'),
                    subtitle: Text(
                      !c.deliveryAvailable
                          ? '가족 알림 서비스가 준비 중이에요. 준비되면 이 기기에서 켤 수 있어요.'
                          : settings.pushEnabled
                          ? c.canReceive
                                ? '가족이 주차하면 이 기기로 알려드려요.'
                                : '서버에 설정했지만 기기의 알림 수신을 확인하지 못했어요.'
                          : '허용하면 기기의 알림 권한을 확인해요.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Palette.muted,
                      ),
                    ),
                    value: settings.pushEnabled,
                    onChanged:
                        enabled && (c.deliveryAvailable || settings.pushEnabled)
                        ? (value) => _save(
                            context,
                            c,
                            settings.copyWith(pushEnabled: value),
                          )
                        : null,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('내가 남긴 기록도 알림 받기'),
                    subtitle: const Text(
                      '끄면 다른 가족의 기록만 알려드려요.',
                      style: TextStyle(fontSize: 12, color: Palette.muted),
                    ),
                    value: settings.notifyOwn,
                    onChanged: enabled && settings.pushEnabled
                        ? (value) => _save(
                            context,
                            c,
                            settings.copyWith(notifyOwn: value),
                          )
                        : null,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('알림 쉬는 시간'),
                    subtitle: Text(
                      settings.quietEnabled
                          ? '${settings.quietStart} ~ ${settings.quietEnd} · ${settings.timezone}'
                          : '설정한 시간에는 가족 알림을 보내지 않아요.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Palette.muted,
                      ),
                    ),
                    value: settings.quietEnabled,
                    onChanged: enabled
                        ? (value) async {
                            if (value) {
                              await _quietHours(context, c);
                            } else {
                              await _save(
                                context,
                                c,
                                settings.copyWith(clearQuietHours: true),
                              );
                            }
                          }
                        : null,
                  ),
                  if (settings.quietEnabled)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: enabled
                            ? () => _quietHours(context, c)
                            : null,
                        child: const Text('시간·시간대 바꾸기'),
                      ),
                    ),
                  const Divider(),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('차량 찾기 표시 사용'),
                    subtitle: const Text(
                      '직접 시작할 때 잠금 화면이나 알림에 위치를 표시해요. 가족 알림과는 별개예요.',
                      style: TextStyle(fontSize: 12, color: Palette.muted),
                    ),
                    value: settings.liveEnabled,
                    onChanged: enabled
                        ? (value) => _save(
                            context,
                            c,
                            settings.copyWith(liveEnabled: value),
                            stopFinding: !value,
                          )
                        : null,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '차량 찾기 기본 시간',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [60, 120, 240, 480]
                        .map(
                          (minutes) => ChoiceChip(
                            label: Text('${minutes ~/ 60}시간'),
                            selected: settings.preferredLiveMinutes == minutes,
                            onSelected: enabled
                                ? (_) => _save(
                                    context,
                                    c,
                                    settings.copyWith(
                                      preferredLiveMinutes: minutes,
                                    ),
                                  )
                                : null,
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '표시 여부와 종료 시점은 기기 설정과 OS 정책에 따라 달라질 수 있어요.',
                    style: TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _save(
    BuildContext context,
    DeviceNotificationController c,
    DeviceNotificationSettings next, {
    bool stopFinding = false,
  }) async {
    try {
      await c.save(next);
    } on Object catch (failure) {
      if (context.mounted && c.error == null) {
        showMessage(context, friendlyError(failure));
      }
      return;
    }
    if (stopFinding && context.mounted && !c.settings.liveEnabled) {
      try {
        await (onLiveDisabled ?? NativeBridge.stopFinding)().timeout(
          const Duration(seconds: 25),
        );
      } on Object {
        if (context.mounted) {
          showMessage(
            context,
            '설정은 껐지만 현재 차량 찾기 표시의 종료를 확인하지 못했어요. 잠금 화면이나 기기 알림에서 직접 종료해 주세요.',
          );
        }
      }
    }
  }

  Future<void> _quietHours(
    BuildContext context,
    DeviceNotificationController c,
  ) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _QuietHoursDialog(controller: c),
  );
}

class _QuietHoursDialog extends StatefulWidget {
  const _QuietHoursDialog({required this.controller});
  final DeviceNotificationController controller;
  @override
  State<_QuietHoursDialog> createState() => _QuietHoursDialogState();
}

class _QuietHoursDialogState extends State<_QuietHoursDialog> {
  final _form = GlobalKey<FormState>();
  late final _start = TextEditingController(
    text: widget.controller.settings.quietStart ?? '22:00',
  );
  late final _end = TextEditingController(
    text: widget.controller.settings.quietEnd ?? '07:00',
  );
  late final _timezone = TextEditingController(
    text: widget.controller.settings.timezone,
  );
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = widget.controller.settings.copyWith(
        quietStart: _start.text.trim(),
        quietEnd: _end.text.trim(),
        timezone: _timezone.text.trim(),
      );
      next.validate();
      await widget.controller.save(next);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (failure) {
      if (mounted) {
        setState(
          () => _error = widget.controller.error ?? friendlyError(failure),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    _timezone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('알림 쉬는 시간'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('종료 시간이 시작 시간보다 이르면 다음 날까지 쉬어요. 시간대는 자동으로 바뀌지 않아요.'),
                const SizedBox(height: 20),
                if (_error != null) StatusNotice(_error!, error: true),
                TextFormField(
                  controller: _start,
                  enabled: !_busy,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(
                    labelText: '시작 시간',
                    hintText: '22:00',
                  ),
                  validator: _validateTime,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _end,
                  enabled: !_busy,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(
                    labelText: '종료 시간',
                    hintText: '07:00',
                  ),
                  validator: _validateTime,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _timezone,
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '시간대',
                    helperText: '한국: Asia/Seoul · UTC: UTC',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '시간대를 입력해 주세요.'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? '저장 중…' : '시간 저장'),
        ),
      ],
    ),
  );

  String? _validateTime(String? value) =>
      value != null &&
          RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value.trim())
      ? null
      : '24시간 형식으로 입력해 주세요. 예: 22:00';
}
