import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app/theme.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/invite_links.dart';
import '../core/native_bridge.dart';
import '../core/device_notifications.dart';
import '../core/repository.dart';
import '../shared/components.dart';
import 'launcher_icon_setting.dart';
import 'profile_editor.dart';
import 'notification_settings.dart';
import 'widget_guide.dart';
import 'vehicle_registration.dart';

Future<bool> openCreateVehicle(
  BuildContext context,
  AppController controller,
) async =>
    await showSheetDialog<bool>(
      context,
      builder: (_) => VehicleRegistrationDialog(controller: controller),
    ) ??
    false;

Future<bool> openJoinVehicle(
  BuildContext context,
  AppController controller, {
  String? initialCode,
}) async {
  var joined = false;
  await showSheetDialog<void>(
    context,
    builder: (_) => _EntryDialog(
      title: '가족 차량에 참여',
      description: '가족에게 받은 초대 코드나 링크를 입력해 주세요. 참여 버튼을 눌러야 차량에 연결돼요.',
      fields: const ['초대 코드 또는 링크'],
      hints: const ['가족에게 받은 초대 붙여넣기'],
      initial: [initialCode ?? ''],
      maxLengths: const [2048],
      button: '가족 차량에 참여하기',
      submit: (values) async {
        final code = parseInvite(values[0]);
        if (code == null) throw AppException('올바른 초대 코드 또는 링크를 입력해 주세요.');
        await controller.join(code);
        joined = true;
      },
    ),
  );
  return joined;
}

class _EntryDialog extends StatefulWidget {
  const _EntryDialog({
    required this.title,
    required this.fields,
    required this.hints,
    required this.maxLengths,
    required this.button,
    required this.submit,
    this.description,
    this.initial,
  });
  final String title, button;
  final String? description;
  final List<String> fields, hints;
  final List<int> maxLengths;
  final List<String>? initial;
  final Future<void> Function(List<String>) submit;
  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  final _form = GlobalKey<FormState>();
  late final List<TextEditingController> _controllers;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.fields.length,
      (i) => TextEditingController(text: widget.initial?[i] ?? ''),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.submit(_controllers.map((c) => c.text.trim()).toList());
      if (mounted) Navigator.pop(context);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SheetDialog(
      title: widget.title,
      subtitle: widget.description,
      onClose: _busy ? null : () => Navigator.pop(context),
      maxWidth: 500,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) StatusNotice(_error!, error: true),
            ...List.generate(
              widget.fields.length,
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextFormField(
                  controller: _controllers[i],
                  enabled: !_busy,
                  maxLength: widget.maxLengths[i],
                  decoration: InputDecoration(
                    labelText: widget.fields[i],
                    hintText: widget.hints[i],
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '${widget.fields[i]}을(를) 입력해 주세요.'
                      : null,
                ),
              ),
            ),
            BusyButton(label: widget.button, onPressed: _submit, busy: _busy),
          ],
        ),
      ),
    ),
  );
}

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  bool _busy = false;
  AppController get c => widget.controller;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await c.refresh();
    } on Object catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite() async {
    await _run(() async {
      final invite = await c.repository.invite(c.vehicle!.id);
      if (!mounted) return;
      final code = invite['code'] as String;
      Future<void> share() async {
        try {
          final text =
              '차자리에서 우리 가족 차의 주차 위치를 함께 확인해요.\n${inviteLink(code)}\n\n초대 코드: $code\n24시간 동안 한 번 사용할 수 있어요.';
          final presented = await NativeBridge.shareText(text);
          if (!presented) {
            await Clipboard.setData(ClipboardData(text: text));
            if (mounted) showMessage(context, '초대 링크와 코드를 복사했어요. 가족에게 보내 주세요.');
          }
        } on Object catch (error) {
          if (mounted) showMessage(context, friendlyError(error));
        }
      }

      await showSheetDialog<void>(
        context,
        barrierDismissible: true,
        builder: (context) => SheetDialog(
          title: '가족을 초대하세요',
          subtitle: '24시간 동안 한 번만 사용할 수 있어요. 이 창을 닫으면 코드를 다시 볼 수 없어요.',
          onClose: () => Navigator.pop(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Surface(
                color: Palette.tint,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '초대 코드',
                      style: TextStyle(fontSize: 12.5, color: Palette.muted),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      code,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '만료: ${formatDate(DateTime.parse(invite['expires_at'] as String), full: true)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: share,
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('초대 링크 공유'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (context.mounted) {
                    showMessage(context, '초대 코드를 복사했어요. 믿을 수 있는 가족에게만 보내 주세요.');
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('코드 복사'),
              ),
            ],
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '초대한 가족만 우리 차의 위치를 볼 수 있어요.',
        style: TextStyle(color: Palette.muted),
      ),
      const SizedBox(height: 24),
      const GroupLabel('공유 중인 차량'),
      Surface(
        color: Palette.tint,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.directions_car_filled_outlined,
                size: 28,
                color: Palette.ink,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.vehicle!.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${c.vehicle!.plate} · ${c.vehicle!.apartment}',
                    style: TextStyle(
                      color: Palette.ink.withValues(alpha: .78),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      GroupLabel('함께하는 가족 ${c.members.length}명'),
      if (c.members.isEmpty)
        const StatusNotice('가족 목록을 불러오지 못했어요. 위로 당겨 새로고침해 주세요.')
      else
        Surface(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, member) in c.members.indexed) ...[
                if (i > 0) const RowDivider(),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 2,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: i.isEven
                        ? Palette.tint
                        : Palette.highlight,
                    child: Text(
                      member.name.characters.first,
                      style: const TextStyle(
                        color: Palette.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    '${member.name}${member.id == c.repository.userId && member.name != '나' ? ' (나)' : ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    member.owner ? '차량 소유자' : '가족 구성원',
                    style: const TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                  trailing: c.isOwner && !member.owner
                      ? IconButton(
                          tooltip: '${member.name} 구성원 제거',
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (await confirmAction(
                                    context,
                                    title: '가족 공유를 해제할까요?',
                                    message:
                                        '${member.name}님은 이 차량의 위치와 기록을 더 이상 볼 수 없어요.',
                                    action: '공유 해제',
                                  )) {
                                    await _run(
                                      () => c.repository.removeMember(
                                        c.vehicle!.id,
                                        member.id,
                                      ),
                                    );
                                  }
                                },
                          icon: const Icon(
                            Icons.person_remove_outlined,
                            size: 20,
                          ),
                        )
                      : null,
                ),
              ],
            ],
          ),
        ),
      const SizedBox(height: 16),
      if (c.isOwner)
        BusyButton(
          label: c.isDemo ? '가족 초대 안내' : '가족 초대 코드 만들기',
          icon: Icons.person_add_alt_1_outlined,
          onPressed: _invite,
          busy: _busy,
        )
      else
        OutlinedButton(
          onPressed: _busy
              ? null
              : () async {
                  if (await confirmAction(
                    context,
                    title: '가족 차량에서 나갈까요?',
                    message: '다시 참여하려면 새로운 초대가 필요해요.',
                    action: '나가기',
                  )) {
                    await _run(() => c.repository.leave(c.vehicle!.id));
                  }
                },
          child: const Text('이 차량에서 나가기'),
        ),
      const SizedBox(height: 20),
    ],
  );
}

Future<void> openFinding(
  BuildContext context,
  AppController c,
  SharedPreferences prefs, {
  DeviceNotificationController? notifications,
}) async {
  if (!NativeBridge.supportsFinding) {
    showMessage(context, '차량 찾기 표시는 Android·iPhone 앱에서 사용할 수 있어요.');
    return;
  }
  var duration = notifications?.initialized == true
      ? notifications!.settings.preferredLiveMinutes
      : prefs.getInt('carcar.finding.minutes') ?? 120;
  bool busy = false;
  String? error;
  await showSheetDialog<void>(
    context,
    barrierDismissible: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SheetDialog(
        title: '차량 찾기 표시',
        subtitle:
            '앱을 나가도 잠금 화면이나 알림에서 위치를 확인해요. 표시 여부와 종료 시점은 기기 설정과 OS에 따라 달라질 수 있어요.',
        onClose: busy ? null : () => Navigator.pop(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Surface(
              color: Palette.tint,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Text(
                c.latest?.position ?? '주차 위치 없음',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 18),
            Text('표시 시간', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [60, 120, 240, 480]
                  .map(
                    (m) => ChoiceChip(
                      label: Text('${m ~/ 60}시간'),
                      selected: duration == m,
                      onSelected: busy
                          ? null
                          : (_) => setState(() => duration = m),
                    ),
                  )
                  .toList(),
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              StatusNotice(error!, error: true),
            ],
            const SizedBox(height: 20),
            BusyButton(
              label: '표시 시작',
              busy: busy,
              onPressed: () async {
                setState(() => busy = true);
                try {
                  if (notifications != null && notifications.supported) {
                    if (!notifications.initialized) {
                      await notifications.refresh();
                    }
                    await notifications.save(
                      notifications.settings.copyWith(
                        liveEnabled: true,
                        preferredLiveMinutes: duration,
                      ),
                    );
                  }
                  final started = await NativeBridge.startFinding(
                    c.snapshot,
                    duration,
                  );
                  if (!context.mounted) return;
                  if (started) {
                    await prefs.setInt('carcar.finding.minutes', duration);
                    if (context.mounted) {
                      Navigator.pop(context);
                      showMessage(
                        context,
                        '차량 찾기 표시를 요청했어요. 잠금 화면 또는 알림을 확인해 주세요.',
                      );
                    }
                  } else {
                    setState(
                      () => error =
                          '표시 권한이 꺼져 있거나 지원하지 않는 기기예요. 기기 설정에서 허용해 주세요.',
                    );
                  }
                } on Object {
                  if (context.mounted) {
                    setState(() => error = '표시를 시작하지 못했어요. 기기 설정을 확인해 주세요.');
                  }
                } finally {
                  if (context.mounted) setState(() => busy = false);
                }
              },
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      try {
                        await NativeBridge.stopFinding();
                        if (notifications?.initialized == true) {
                          await notifications!.save(
                            notifications.settings.copyWith(liveEnabled: false),
                          );
                        }
                        if (context.mounted) {
                          Navigator.pop(context);
                          showMessage(context, '차량 찾기 표시를 종료했어요.');
                        }
                      } on Object {
                        if (context.mounted) {
                          setState(
                            () => error = '표시를 종료하지 못했어요. 기기의 알림을 확인해 주세요.',
                          );
                        }
                      }
                    },
              child: const Text('표시 종료'),
            ),
          ],
        ),
      ),
    ),
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.preferences,
    required this.onLogout,
    this.notifications,
    this.widgetSectionKey,
  });
  final AppController controller;
  final SharedPreferences preferences;
  final Future<void> Function() onLogout;
  final DeviceNotificationController? notifications;
  final Key? widgetSectionKey;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  AppController get c => widget.controller;
  Future<void> _apartment() async {
    final v = c.vehicle!;
    await showSheetDialog<void>(
      context,
      builder: (_) => _EntryDialog(
        title: '우리 주차장 설정',
        description: '층수와 구역은 쉼표로 구분해 주세요. 예: B1, B2, B3',
        fields: const ['아파트 이름', '사용하는 층수', '사용하는 구역'],
        hints: const ['우리집 아파트', 'B1, B2, B3, B4', 'A, B, C, D, E'],
        maxLengths: const [60, 200, 200],
        initial: [v.apartment, v.floors.join(', '), v.zones.join(', ')],
        button: '설정 저장',
        submit: (values) async {
          List<String> parse(String input) => input
              .split(',')
              .map((s) => s.trim().toUpperCase())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
          final floors = parse(values[1]), zones = parse(values[2]);
          if (floors.isEmpty ||
              zones.isEmpty ||
              floors.length > 20 ||
              zones.length > 30 ||
              [...floors, ...zones].any((s) => s.length > 20)) {
            throw const AppException(
              '층수는 1~20개, 구역은 1~30개로 입력해 주세요. 항목은 20자까지 가능해요.',
            );
          }
          await c.repository.updateApartment(v.id, values[0], floors, zones);
          await c.refresh();
        },
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await confirmAction(
      context,
      title: c.isDemo ? '체험 데이터를 지울까요?' : '계정을 삭제할까요?',
      message: c.isDemo
          ? '이 기기의 체험 기록을 지우고 처음 화면으로 돌아가요.'
          : '소유한 차량과 가족의 공유 기록도 함께 삭제됩니다. 다른 차량의 내가 작성한 기록은 익명 처리돼요. 이 작업은 되돌릴 수 없어요.',
      action: c.isDemo ? '체험 데이터 삭제' : '계정 삭제',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await c.repository.deleteAccount();
      await widget.onLogout();
    } on Object catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('필요한 기능만 편안하게 설정하세요.', style: TextStyle(color: Palette.muted)),
      const SizedBox(height: 24),
      if (c.vehicle != null) ...[
        const GroupLabel('우리 주차장'),
        Surface(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ActionRow(
                icon: Icons.apartment_outlined,
                title: c.vehicle!.apartment.isEmpty
                    ? '아파트 이름 미설정'
                    : c.vehicle!.apartment,
                subtitle:
                    '층수 ${c.vehicle!.floors.join(' · ')}\n구역 ${c.vehicle!.zones.join(' · ')}',
                onTap: c.isOwner ? _apartment : null,
              ),
              if (!c.isOwner)
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Text(
                    '차량 소유자가 주차장 설정을 변경할 수 있어요.',
                    style: TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
      ],
      const GroupLabel('이 기기에서 보기'),
      Surface(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (NativeBridge.supportsLauncherIcons) ...[
              LauncherIconSetting(controller: c),
              const RowDivider(),
            ],
            ActionRow(
              icon: Icons.near_me_outlined,
              title: '차량 찾기 표시',
              subtitle: '원할 때 시작하고, 필요 없을 때 종료해요.',
              onTap: c.latest == null
                  ? null
                  : () => openFinding(
                      context,
                      c,
                      widget.preferences,
                      notifications: widget.notifications,
                    ),
            ),
            const RowDivider(),
            KeyedSubtree(
              key: widget.widgetSectionKey,
              child: ActionRow(
                icon: Icons.widgets_outlined,
                title: '홈 화면 위젯',
                subtitle: '마지막으로 확인한 주차 위치를 보여줘요.',
                onTap: () =>
                    showWidgetGuide(context, showSettingsAction: false),
              ),
            ),
            const RowDivider(),
            SwitchRow(
              icon: Icons.touch_app_outlined,
              title: '위젯에서 바로 기록',
              subtitle: c.isDemo
                  ? '실제 계정에서 사용할 수 있어요.'
                  : '이 기기에서 허용해요. 로그인 만료 시 앱을 다시 열어 주세요.',
              value: c.widgetQuickSaveEnabled,
              onChanged:
                  _busy ||
                      c.isDemo ||
                      c.vehicle == null ||
                      !NativeBridge.supportsOcr
                  ? null
                  : (enabled) async {
                      setState(() => _busy = true);
                      try {
                        await c.setWidgetQuickSaveEnabled(enabled);
                        if (context.mounted) {
                          showMessage(
                            context,
                            enabled
                                ? '이 기기의 위젯에서 기록할 수 있어요.'
                                : '위젯 바로 기록을 해제했어요.',
                          );
                        }
                      } on Object catch (e) {
                        if (context.mounted) {
                          showMessage(context, friendlyError(e));
                        }
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      NotificationSettings(controller: widget.notifications, isDemo: c.isDemo),
      const SizedBox(height: 22),
      const GroupLabel('개인정보와 계정'),
      Surface(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ActionRow(
              icon: Icons.person_outline_rounded,
              title: '내 이름',
              subtitle: '가족과 주차 기록에 표시할 이름을 바꿔요.',
              onTap: _busy
                  ? null
                  : () async {
                      final changed = await openProfileEditor(
                        context,
                        c.repository,
                      );
                      if (changed && mounted) await c.refresh();
                    },
            ),
            const RowDivider(),
            ActionRow(
              icon: Icons.shield_outlined,
              title: '개인정보 처리 안내',
              subtitle: '사진은 기기에서만 읽고 업로드하지 않아요.',
              onTap: () => _info('개인정보 처리 안내', _privacy),
            ),
            const RowDivider(),
            ActionRow(
              icon: Icons.logout_rounded,
              title: c.isDemo ? '체험 종료' : '로그아웃',
              subtitle: '이 기기의 위젯과 차량 찾기 표시도 지워져요.',
              onTap: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await widget.onLogout();
                      } on Object catch (e) {
                        if (context.mounted) {
                          setState(() => _busy = false);
                          showMessage(context, friendlyError(e));
                        }
                      }
                    },
            ),
            const RowDivider(),
            ActionRow(
              icon: Icons.delete_outline_rounded,
              destructive: true,
              title: c.isDemo ? '체험 데이터 초기화' : '계정 삭제',
              subtitle: c.isDemo
                  ? '기기에 저장한 체험 기록을 지워요.'
                  : '내 계정과 소유한 차량 데이터를 삭제해요.',
              onTap: _busy ? null : _delete,
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      const Text(
        '차자리 1.0.0\n가족과 함께 기억하는 우리 차의 자리',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Palette.muted, height: 1.8),
      ),
    ],
  );
  void _info(String title, String text) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      scrollable: true,
      content: Text(text, style: const TextStyle(fontSize: 14, height: 1.8)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

const _privacy =
    '차자리는 가족이 함께 쓰는 차량의 마지막 주차 위치를 공유합니다.\n\n수집 항목: 로그인 이메일, 표시 이름, 차량 별명과 번호, 아파트 별명, 주차 층·구역·번호·메모, 기록 시각과 작성자. 가족 알림을 켜면 기기 알림 토큰, 기기별 알림 설정과 시간대를 추가로 저장합니다.\n\n이용 목적: 본인 인증, 초대한 가족 사이의 주차 위치 공유, 이력 표시. 차량번호만으로 다른 가족의 정보에 접근할 수 없습니다.\n\n사진: 글자 인식은 기기에서만 진행하며 원본 사진을 서버로 업로드하지 않습니다. 촬영 임시 파일은 앱/OS의 캐시 정리 정책을 따릅니다.\n\n보관: 주차 이력은 소유자가 계정을 삭제할 때까지 보관됩니다. 가족 탈퇴·제거 시 해당 차량에 대한 접근이 철회됩니다. 소유자 계정 삭제 시 소유 차량과 공유 이력이 삭제됩니다. 다른 차량에 남긴 기록은 작성자 식별을 제거해 보존합니다.\n\n체험 모드: 실제 서버와 분리되어 이 기기에만 저장됩니다. 설정에서 초기화할 수 있습니다.\n\n위젯 바로 기록: 허용한 기기에 한해 짧은 수명의 인증 정보를 기기 보안 저장소에 보관합니다. 로그인 갱신용 정보는 위젯과 공유하지 않습니다. 설정을 해제하면 위젯의 인증 정보를 삭제합니다.\n\n로그아웃 시 이 기기의 위젯 스냅샷·인증 정보와 찾기 표시를 지웁니다. 스크린샷이나 다른 기기에 이미 표시된 정보까지 원격으로 삭제할 수는 없습니다.\n\n가족 알림: 허용한 기기에만 발송합니다. 알림에는 상세 위치·차량번호·이름을 넣지 않습니다. 알림을 끄거나 온라인에서 로그아웃하면 서버의 기기 토큰을 삭제합니다. 오프라인에서는 서버 등록 해제가 완료되지 않을 수 있어 안내를 표시합니다. 이미 발송된 알림은 회수를 보장하지 않습니다. 발송 작업은 다음 처리 시 7일 이전 항목을 정리합니다.\n\n처리 서비스: Supabase가 인증과 데이터 저장을 처리하며 차자리 데이터베이스는 서울 리전을 사용합니다. 알림 전송에는 Apple APNs와 Google Firebase Cloud Messaging을 사용합니다.\n\n문의: TestFlight의 베타 피드백 보내기로 차자리 개발팀에 문의할 수 있습니다. 계정 삭제는 이 화면에서 직접 요청할 수 있습니다.';
