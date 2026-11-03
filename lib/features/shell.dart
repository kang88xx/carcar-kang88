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
  static const _bannerKey = 'carcar.home.widget_banner_hidden';
  int _tab = 0;
  String _search = '';
  final _scroll = ScrollController();
  final _widgetSettingsKey = GlobalKey();
  late bool _bannerHidden = widget.preferences.getBool(_bannerKey) ?? false;
  AppController get c => widget.controller;
  static const _labels = ['주차 위치', '주차 이력', '우리 가족', '설정'];
  static const _icons = [
    Icons.local_parking_rounded,
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

  Future<void> _hideBanner() async {
    setState(() => _bannerHidden = true);
    try {
      await widget.preferences.setBool(_bannerKey, true);
    } on Object {
      // The banner simply returns next launch if the preference fails.
    }
  }

  String? get _myName {
    final name = c.members
        .where((m) => m.id == c.repository.userId)
        .map((m) => m.name.trim())
        .firstOrNull;
    return name == null || name.isEmpty || name == '나' ? null : name;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= wideLayoutBreakpoint &&
            constraints.maxHeight >= 520;
        return Scaffold(
          bottomNavigationBar: wide ? null : _floatingBar(),
          body: SafeArea(
            bottom: false,
            child: Row(
              children: [
                if (wide) _sidebar(),
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
                                  wide ? 44 : 20,
                                  wide ? 38 : 12,
                                  wide ? 44 : 20,
                                  40,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _top(wide),
                                    const SizedBox(height: 22),
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

  Widget _floatingBar() => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      8,
      16,
      12 + MediaQuery.paddingOf(context).bottom,
    ),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
            color: Palette.ink.withValues(alpha: .12),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: headlineMaxTextScale,
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _navigate,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: List.generate(
              4,
              (i) => NavigationDestination(
                icon: Icon(_icons[i]),
                label: _labels[i],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _sidebar() => Container(
    width: 224,
    margin: const EdgeInsets.fromLTRB(16, 16, 0, 16),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(left: 12), child: Brand()),
        const SizedBox(height: 40),
        ...List.generate(
          4,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              shape: const StadiumBorder(),
              selected: _tab == i,
              selectedTileColor: Palette.lime,
              selectedColor: Palette.ink,
              leading: Icon(_icons[i]),
              title: Text(
                _labels[i],
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
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
            style: TextStyle(color: Palette.muted, fontSize: 12, height: 1.8),
          ),
        ),
      ],
    ),
  );

  Widget _top(bool wide) {
    final name = _myName;
    final headline = switch (_tab) {
      0 => greetingFor(DateTime.now(), name: name),
      1 => '쌓여 가는 주차 기록',
      2 => '우리 가족, 같은 자리',
      _ => '나에게 맞게 사용하기',
    };
    final title = MediaQuery.withClampedTextScaling(
      maxScaleFactor: headlineMaxTextScale,
      child: Text(
        headline,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontSize: wide
              ? 32
              : MediaQuery.sizeOf(context).width < 360
              ? 22
              : 27,
        ),
      ),
    );
    final controls = <Widget>[
      IconButton(
        tooltip: '최신 위치 새로고침',
        onPressed: c.loading ? null : c.refresh,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          fixedSize: const Size(42, 42),
        ),
        icon: const Icon(Icons.refresh_rounded, size: 21),
      ),
      const SizedBox(width: 8),
      IconButton(
        tooltip: '설정 열기',
        onPressed: () => _navigate(3),
        style: IconButton.styleFrom(
          backgroundColor: Palette.ink,
          fixedSize: const Size(42, 42),
        ),
        icon: Text(
          name == null ? '나' : name.characters.first,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    ];
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: title,
            ),
          ),
          const SizedBox(width: 12),
          ...controls,
        ],
      );
    }
    // Phones: controls sit in their own row so the greeting keeps the full
    // width and Korean words do not break syllable by syllable.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.end, children: controls),
        const SizedBox(height: 4),
        title,
      ],
    );
  }

  Widget _onboarding() => Surface(
    child: EmptyState(
      icon: Icons.directions_car_outlined,
      title: widget.pendingInvite != null ? '가족 초대를 받았어요' : '우리 가족의 차 한 대',
      description: '처음이라면 새 차량을 등록하고,\n가족이 먼저 등록했다면 초대코드로 참여해요.',
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          OutlinedButton(
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

  Widget _home() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionTitle('지금 우리 차'),
      _heroGroup(),
      const SizedBox(height: 16),
      BusyButton(
        label: '주차 위치 기록하기',
        icon: Icons.add_rounded,
        onPressed: () => openParkingForm(context, c),
      ),
      const SizedBox(height: 26),
      if (!_bannerHidden) ...[_widgetBanner(), const SizedBox(height: 26)],
      if (c.records.isNotEmpty) ...[
        SectionTitle(
          '최근 주차 기록',
          trailing: TextButton(
            onPressed: () => _navigate(1),
            child: const Text('전체 보기'),
          ),
        ),
        _recordList(c.records.take(3).toList()),
        const SizedBox(height: 14),
      ],
      _familyRow(),
    ],
  );

  Widget _heroGroup() => Surface(
    color: Palette.tint,
    padding: const EdgeInsets.all(10),
    radius: 28,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _locationCard(),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .42),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: QuickAction(
                  icon: Icons.photo_camera_outlined,
                  label: '사진 기록',
                  onTap: () => openParkingForm(context, c, camera: true),
                ),
              ),
              Expanded(
                child: QuickAction(
                  icon: Icons.near_me_outlined,
                  label: '차량 찾기',
                  onTap: c.latest == null
                      ? null
                      : () => openFinding(
                          context,
                          c,
                          widget.preferences,
                          notifications: widget.notifications,
                        ),
                ),
              ),
              Expanded(
                child: QuickAction(
                  icon: Icons.history_rounded,
                  label: '이력 보기',
                  onTap: () => _navigate(1),
                ),
              ),
              Expanded(
                child: QuickAction(
                  icon: Icons.widgets_outlined,
                  label: '위젯',
                  onTap: _widgetGuide,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _locationCard() {
    final r = c.latest;
    if (r == null) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(22),
        ),
        child: EmptyState(
          icon: Icons.local_parking_rounded,
          title: '아직 주차 기록이 없어요',
          description: '아래 버튼을 눌러 첫 위치를 남겨보세요.',
        ),
      );
    }
    return Semantics(
      label: '현재 주차 위치 ${r.position}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Palette.ink,
                      size: 17,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        '마지막 주차 위치',
                        style: TextStyle(
                          color: Palette.ink.withValues(alpha: .8),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .2,
                        ),
                      ),
                    ),
                  ],
                ),
                if (c.loading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                else
                  Text(
                    c.vehicle!.name,
                    style: TextStyle(
                      color: Palette.ink.withValues(alpha: .78),
                      fontSize: 12.5,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 22,
              runSpacing: 10,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          r.floor,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Palette.ink,
                            fontSize: 76,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            letterSpacing: -3.5,
                          ),
                        ),
                      ),
                    ),
                    if (floorDescription(r.floor) case final label?) ...[
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: Palette.ink.withValues(alpha: .78),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r.zone} 구역',
                        style: const TextStyle(
                          color: Palette.ink,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.spot.isEmpty ? '번호 미입력' : '${r.spot}번 자리',
                        style: TextStyle(
                          color: Palette.ink.withValues(alpha: .72),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .62),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: Palette.ink,
                    child: Text(
                      c.author(r.createdBy).characters.first,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c.author(r.createdBy)} 기록 · ${formatDate(r.createdAt)}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Palette.ink,
                          ),
                        ),
                        if (r.note.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              r.note,
                              style: const TextStyle(
                                color: Palette.ink,
                                fontSize: 13,
                                height: 1.55,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _widgetBanner() => Surface(
    padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.widgets_outlined, color: Palette.ink, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '홈 화면 위젯으로 주차 위치를 보고, 층을 눌러 바로 기록해요.',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: _hideBanner,
              tooltip: '위젯 안내 닫기',
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 38),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: _widgetGuide,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
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
  );

  Widget _familyRow() => Surface(
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: () => _navigate(2),
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
        child: Row(
          children: [
            SizedBox(
              height: 32,
              width: 32.0 + 20.0 * (c.members.take(3).length - 1).clamp(0, 2),
              child: Stack(
                children: [
                  for (final (i, m) in c.members.take(3).indexed)
                    Positioned(
                      left: i * 20,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: i.isEven ? Palette.tint : Palette.lime,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          m.name.characters.first,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Palette.ink,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                c.isDemo
                    ? '가족과 함께 사용하는 모습을 둘러보세요'
                    : c.members.length <= 1
                    ? '가족을 초대해 함께 확인해 보세요'
                    : '${c.members.length}명이 함께 위치를 확인하고 있어요',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Palette.muted,
              size: 22,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _recordList(List<ParkingRecord> records) => Surface(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    child: Column(
      children: [
        for (final (i, r) in records.indexed)
          _recordRow(r, last: i == records.length - 1),
      ],
    ),
  );

  Widget _recordRow(ParkingRecord r, {bool last = false}) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Palette.canvas,
                shape: BoxShape.circle,
              ),
              child: Text(
                r.floor,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: -.5,
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${c.author(r.createdBy)} · ${formatDate(r.createdAt)}',
                    style: const TextStyle(color: Palette.muted, fontSize: 12),
                  ),
                  if (_tab == 1 && r.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        r.note,
                        style: const TextStyle(
                          fontSize: 12.5,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: const ShapeDecoration(
                  color: Palette.lime,
                  shape: StadiumBorder(),
                ),
                child: const Text(
                  '최근',
                  style: TextStyle(
                    color: Palette.ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
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
        Text(
          '${c.vehicle!.name}의 최근 200개 기록을 확인해요.',
          style: const TextStyle(color: Palette.muted),
        ),
        const SizedBox(height: 18),
        TextField(
          decoration: const InputDecoration(
            fillColor: Colors.white,
            hintText: '층수, 구역, 번호 또는 메모 검색',
            prefixIcon: Icon(Icons.search_rounded, color: Palette.muted),
          ),
          onChanged: (value) => setState(() => _search = value),
        ),
        const SizedBox(height: 20),
        if (results.isEmpty)
          Surface(
            child: EmptyState(
              icon: Icons.history_rounded,
              title: _search.isEmpty ? '아직 기록이 없어요' : '검색한 기록이 없어요',
              description: _search.isEmpty
                  ? '주차 위치를 기록하면 이곳에 차례로 쌓여요.'
                  : '다른 층수나 구역으로 검색해 보세요.',
            ),
          )
        else
          _recordList(results),
      ],
    );
  }
}
