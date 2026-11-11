import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../core/device_notifications.dart';
import '../core/repository.dart';
import '../shared/components.dart';

class NotificationSettings extends StatelessWidget {
  const NotificationSettings({super.key, this.controller, this.isDemo = false});
  final DeviceNotificationController? controller;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null || isDemo || !c.supported) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GroupLabel('알림'),
          Surface(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SwitchRow(
              icon: Icons.notifications_outlined,
              title: '가족 주차 알림',
              subtitle: isDemo
                  ? '실제 계정으로 로그인한 휴대폰에서 설정할 수 있어요.'
                  : 'Android·iPhone 앱에서 설정할 수 있어요.',
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
            const GroupLabel('알림'),
            Surface(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 10, 18, 4),
                    child: Text(
                      '이 기기의 현재 계정에만 적용돼요.',
                      style: TextStyle(fontSize: 12.5, color: Palette.muted),
                    ),
                  ),
                  // Loading and saving both lock the switches below.
                  if (c.busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: LinearProgressIndicator(),
                    ),
                  if (c.error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                      child: StatusNotice(
                        c.error!,
                        error: true,
                        onRetry: c.busy ? null : c.refresh,
                      ),
                    ),
                  if (c.warning != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                      child: StatusNotice(c.warning!),
                    ),
                  SwitchRow(
                    icon: Icons.notifications_outlined,
                    title: '가족 주차 알림',
                    subtitle: !c.deliveryAvailable
                        ? '가족 알림 서비스가 준비 중이에요. 준비되면 이 기기에서 켤 수 있어요.'
                        : settings.pushEnabled
                        ? c.canReceive
                              ? '가족이 주차하면 이 기기로 알려드려요.'
                              : '서버에 설정했지만 기기의 알림 수신을 확인하지 못했어요.'
                        : '허용하면 기기의 알림 권한을 확인해요.',
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
                  const RowDivider(),
                  SwitchRow(
                    icon: Icons.person_outline_rounded,
                    title: '내가 남긴 기록도 알림 받기',
                    subtitle: '끄면 다른 가족의 기록만 알려드려요.',
                    value: settings.notifyOwn,
                    onChanged: enabled && settings.pushEnabled
                        ? (value) => _save(
                            context,
                            c,
                            settings.copyWith(notifyOwn: value),
                          )
                        : null,
                  ),
                  const RowDivider(),
                  SwitchRow(
                    icon: Icons.bedtime_outlined,
                    title: '알림 쉬는 시간',
                    subtitle: settings.quietEnabled
                        ? '${settings.quietStart} ~ ${settings.quietEnd} · ${settings.timezone}'
                        : '설정한 시간에는 가족 알림을 보내지 않아요.',
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: enabled
                              ? () => _quietHours(context, c)
                              : null,
                          child: const Text('시간·시간대 바꾸기'),
                        ),
                      ),
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
    DeviceNotificationSettings next,
  ) async {
    try {
      await c.save(next);
    } on Object catch (failure) {
      if (context.mounted && c.error == null) {
        showMessage(context, friendlyError(failure));
      }
    }
  }

  Future<void> _quietHours(
    BuildContext context,
    DeviceNotificationController c,
  ) => showSheetDialog<void>(
    context,
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
    child: SheetDialog(
      title: '알림 쉬는 시간',
      subtitle: '종료 시간이 시작 시간보다 이르면 다음 날까지 쉬어요. 시간대는 자동으로 바뀌지 않아요.',
      onClose: _busy ? null : () => Navigator.of(context).pop(),
      maxWidth: 440,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
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
            const SizedBox(height: 20),
            BusyButton(label: '시간 저장', onPressed: _save, busy: _busy),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
          ],
        ),
      ),
    ),
  );

  String? _validateTime(String? value) =>
      value != null &&
          RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value.trim())
      ? null
      : '24시간 형식으로 입력해 주세요. 예: 22:00';
}
