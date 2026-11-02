import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app/theme.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/device_notifications.dart';
import '../shared/components.dart';
import 'parking_form.dart';
import 'management.dart';
import 'widget_guide.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    required this.preferences,
    required this.onLogout,
    this.notifications,
    this.pendingInvite,
    this.inviteNotice,
    this.onClearInvite,
  });
  final AppController controller;
  final SharedPreferences preferences;
  final Future<void> Function() onLogout;
  final DeviceNotificationController? notifications;
  final String? pendingInvite, inviteNotice;
  final Future<void> Function()? onClearInvite;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
  String _search = '';
  final _scroll = ScrollController();
  final _widgetSettingsKey = GlobalKey();
  AppController get c => widget.controller;
  static const _labels = ['주차 위치', '주차 이력', '우리 가족', '설정'];
  static const _icons = [
    Icons.local_parking_outlined,
    Icons.history_rounded,
    Icons.people_outline_rounded,
    Icons.tune_rounded,
  ];
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _navigate(int index) {
    setState(() => _tab = index);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _openWidgetSettings() {
    _navigate(3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _widgetSettingsKey.currentContext;
      if (mounted && _tab == 3 && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 220),
          alignment: .12,
        );
      }
    });
  }

  Future<void> _widgetGuide() async {
    if (await showWidgetGuide(context) && mounted) _openWidgetSettings();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Scaffold(
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: _navigate,
                  destinations: List.generate(
                    4,
                    (i) => NavigationDestination(
                      icon: Icon(_icons[i]),
                      label: _labels[i],
                    ),
                  ),
                ),
          body: SafeArea(
            child: Row(
              children: [
                if (wide)
                  Container(
                    width: 214,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(right: BorderSide(color: Palette.line)),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 32,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: Brand(),
                        ),
                        const SizedBox(height: 48),
                        ...List.generate(
                          4,
                          (i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              selected: _tab == i,
                              selectedTileColor: Palette.soft,
                              selectedColor: Palette.green,
                              leading: Icon(_icons[i]),
                              title: Text(
                                _labels[i],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              onTap: () => _navigate(i),
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            '가족과 함께 기억하는\n우리 차의 자리',
                            style: TextStyle(
                              color: Palette.muted,
                              fontSize: 12,
                              height: 1.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: c.refresh,
                    child: CustomScrollView(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1056),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  wide ? 44 : 22,
                                  wide ? 38 : 22,
                                  wide ? 44 : 22,
                                  40,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _top(wide),
                                    const SizedBox(height: 24),
                                    if (widget.inviteNotice != null)
                                      StatusNotice(
                                        widget.inviteNotice!,
                                        error: true,
                                      ),
                                    if (widget.pendingInvite != null &&
                                        c.vehicle != null)
                                      StatusNotice(
                                        '가족 초대를 받았지만 이미 연결된 차량이 있어요. 계정마다 차량 한 대만 사용할 수 있어요.',
                                      ),
                                    if (widget.pendingInvite != null &&
                                        c.vehicle != null)
                                      TextButton(
                                        onPressed: widget.onClearInvite,
                                        child: const Text('받은 초대 닫기'),
                                      ),
                                    if (c.isDemo)
                                      const StatusNotice(
                                        '체험 중 · 기록은 이 기기에만 저장돼요.',
                                      ),
                                    if (c.error != null)
                                      StatusNotice(
                                        c.error!,
                                        error: true,
                                        onRetry: c.refresh,
                                      ),
                                    if (c.widgetWarning != null)
                                      StatusNotice(c.widgetWarning!),
                                    if (c.loading && c.vehicles.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.all(60),
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      )
                                    else if (c.vehicle == null && _tab != 3)
                                      _onboarding()
                                    else
                                      switch (_tab) {
                                        0 => _home(),
                                        1 => _history(),
                                        2 => FamilyScreen(controller: c),
                                        _ => SettingsScreen(
                                          widgetSectionKey: _widgetSettingsKey,
                                          controller: c,
                                          preferences: widget.preferences,
                                          onLogout: widget.onLogout,
                                          notifications: widget.notifications,
                                        ),
                                      },
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  Widget _top(bool wide) => Row(
    children: [
      if (!wide)
        const Brand()
      else
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _tab == 0 ? '주차 위치' : _labels[_tab],
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (_tab == 0)
                const Text(
                  '오늘도 편안하게, 우리 차의 자리.',
                  style: TextStyle(color: Palette.muted, fontSize: 13),
                ),
            ],
          ),
        ),
      if (!wide) const Spacer(),
      IconButton(
        tooltip: '최신 위치 새로고침',
        onPressed: c.loading ? null : c.refresh,
        icon: const Icon(Icons.refresh_rounded, color: Palette.muted),
      ),
      const SizedBox(width: 4),
      Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: Palette.soft,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Text(
          '나',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
  Widget _onboarding() => Surface(
    child: EmptyState(
      icon: Icons.directions_car_outlined,
      title: widget.pendingInvite != null ? '가족 초대를 받았어요' : '우리 가족의 차 한 대',
      description: '처음이라면 새 차량을 등록하고,\n가족이 먼저 등록했다면 초대코드로 참여해요.',
      action: Column(
        children: [
          FilledButton.icon(
            onPressed: () async {
              if (await openCreateVehicle(context, c)) {
                await widget.onClearInvite?.call();
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('새 차량 등록'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () async {
              if (await openJoinVehicle(
                context,
                c,
                initialCode: widget.pendingInvite,
              )) {
                await widget.onClearInvite?.call();
              }
            },
            child: const Text('기존 차량 참여 · 초대코드 입력'),
          ),
          TextButton(onPressed: widget.onLogout, child: const Text('로그아웃')),
        ],
      ),
    ),
  );
  Widget _vehicleHeader() => Row(
    children: [
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Palette.green.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Icon(
          Icons.directions_car_filled_outlined,
          size: 30,
          color: Palette.green,
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.vehicle!.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 3),
            Text(
              '${c.vehicle!.plate} · ${c.vehicle!.apartment}',
              style: const TextStyle(fontSize: 12, color: Palette.muted),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _home() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _vehicleHeader(),
      const SizedBox(height: 24),
      _locationCard(),
      const SizedBox(height: 18),
      BusyButton(
        label: '주차 위치 기록하기',
        icon: Icons.add_rounded,
        onPressed: () => openParkingForm(context, c),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => openParkingForm(context, c, camera: true),
              icon: const Icon(Icons.photo_camera_outlined, size: 19),
              label: const Text('사진 입력'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: c.latest == null
                  ? null
                  : () => openFinding(
                      context,
                      c,
                      widget.preferences,
                      notifications: widget.notifications,
                    ),
              icon: const Icon(Icons.near_me_outlined, size: 19),
              label: const Text('차량 찾기'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      Material(
        color: Palette.soft,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              onTap: _widgetGuide,
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              leading: const Icon(Icons.widgets_outlined, color: Palette.green),
              title: const Text(
                '주차 위치, 홈 화면에서 바로',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                '차곡 위젯을 추가하는 방법을 확인해 보세요.',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _widgetGuide,
                    child: const Text('추가 방법 보기'),
                  ),
                  TextButton(
                    onPressed: _openWidgetSettings,
                    child: const Text('위젯 설정'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      SectionTitle(
        '최근 주차 기록',
        trailing: TextButton(
          onPressed: () => _navigate(1),
          child: const Text('전체 보기'),
        ),
      ),
      if (c.records.isEmpty)
        const Surface(
          child: Text(
            '첫 주차 기록을 남기면 이곳에서 확인할 수 있어요.',
            style: TextStyle(color: Palette.muted),
          ),
        )
      else
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Column(
            children: c.records
                .take(3)
                .map((r) => _recordRow(r, last: r == c.records.take(3).last))
                .toList(),
          ),
        ),
      const SizedBox(height: 26),
      InkWell(
        onTap: () => _navigate(2),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ...c.members
                  .take(3)
                  .map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: Palette.soft,
                        child: Text(
                          m.name.characters.first,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Palette.green,
                          ),
                        ),
                      ),
                    ),
                  ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.isDemo
                      ? '가족과 함께 사용하는 모습을 둘러보세요'
                      : '${c.members.length}명이 함께 위치를 확인하고 있어요',
                  style: const TextStyle(color: Palette.muted, fontSize: 12),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Palette.muted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    ],
  );
  Widget _locationCard() {
    final r = c.latest;
    if (r == null) {
      return Surface(
        child: EmptyState(
          icon: Icons.local_parking_rounded,
          title: '아직 주차 기록이 없어요',
          description: '아래 버튼을 눌러 첫 위치를 남겨보세요.',
        ),
      );
    }
    return Semantics(
      label: '현재 주차 위치 ${r.position}',
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Palette.green,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: Palette.lime,
                  size: 18,
                ),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    '마지막 주차 위치',
                    style: TextStyle(
                      color: Palette.lime,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (c.loading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Palette.lime,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 24,
              runSpacing: 16,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.floor,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 72,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                        letterSpacing: -3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      r.floor.startsWith('B')
                          ? '지하 ${r.floor.substring(1)}층'
                          : r.floor,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .68),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                Container(
                  height: 60,
                  width: 1,
                  color: Colors.white.withValues(alpha: .18),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.zone} 구역',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 29,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      r.spot.isEmpty ? '번호 미입력' : '${r.spot}번 자리',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .78),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (r.note.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: .65),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      r.note,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.7,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Divider(color: Colors.white.withValues(alpha: .17)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  '${c.author(r.createdBy)} 기록',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Text(
                  '· ${formatDate(r.createdAt)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .65),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _recordRow(ParkingRecord r, {bool last = false}) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 17),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Palette.soft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                r.floor,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r.zone}구역${r.spot.isEmpty ? '' : ' · ${r.spot}번'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${c.author(r.createdBy)} · ${formatDate(r.createdAt)}',
                    style: const TextStyle(color: Palette.muted, fontSize: 11),
                  ),
                  if (_tab == 1 && r.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(
                        r.note,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Palette.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (r.id == c.latest?.id)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Palette.soft,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Text(
                  '최근',
                  style: TextStyle(
                    color: Palette.green,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
      if (!last) const Divider(),
    ],
  );
  Widget _history() {
    final results = c.records
        .where(
          (r) =>
              '${r.floor} ${r.zone} ${r.spot} ${r.note} ${c.author(r.createdBy)}'
                  .toLowerCase()
                  .contains(_search.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('차곡차곡 쌓인 기록', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          '${c.vehicle!.name}의 최근 200개 기록을 확인해요.',
          style: const TextStyle(color: Palette.muted),
        ),
        const SizedBox(height: 24),
        TextField(
          decoration: const InputDecoration(
            hintText: '층수, 구역, 번호 또는 메모 검색',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: (value) => setState(() => _search = value),
        ),
        const SizedBox(height: 24),
        if (results.isEmpty)
          EmptyState(
            icon: Icons.history_rounded,
            title: _search.isEmpty ? '아직 기록이 없어요' : '검색한 기록이 없어요',
            description: _search.isEmpty
                ? '주차 위치를 기록하면 이곳에 차곡차곡 쌓여요.'
                : '다른 층수나 구역으로 검색해 보세요.',
          )
        else
          Surface(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Column(
              children: results
                  .map((r) => _recordRow(r, last: r == results.last))
                  .toList(),
            ),
          ),
      ],
    );
  }
}
