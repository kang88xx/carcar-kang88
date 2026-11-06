import 'package:flutter/material.dart';
import '../app/theme.dart';

/// True means the user requested this app's widget settings, not OS installation.
Future<bool> showWidgetGuide(
  BuildContext context, {
  bool showSettingsAction = true,
}) async {
  final platform = Theme.of(context).platform;
  final ios = platform == TargetPlatform.iOS;
  final android = platform == TargetPlatform.android;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('홈 화면에 주차 위치 두기'),
          scrollable: true,
          content: SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '정사각형 위젯에서 마지막 주차 위치를 확인하고, 주차 기록을 누르면 앱의 입력 화면이 열려요.',
                ),
                const SizedBox(height: 20),
                if (!android) ...[
                  const Text(
                    'iPhone',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const _GuideStep('1', '홈 화면의 빈 곳을 길게 눌러요.'),
                  const _GuideStep('2', '편집 → 위젯 추가를 눌러요.'),
                  const _GuideStep('3', '차자리를 검색하고 소형 정사각형 위젯을 추가해요.'),
                  const Text(
                    'iOS 17 이상에서 사용할 수 있어요.',
                    style: TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                ],
                if (!ios) ...[
                  if (!android) const SizedBox(height: 20),
                  const Text(
                    'Android',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const _GuideStep('1', '홈 화면의 빈 곳을 길게 눌러요.'),
                  const _GuideStep('2', '위젯 목록에서 차자리를 찾아요.'),
                  const _GuideStep('3', '2×2 위젯을 길게 눌러 원하는 자리에 놓아요.'),
                ],
                const SizedBox(height: 20),
                const Text(
                  '별도의 위젯 저장 권한은 필요 없어요. 앱에서 층·구역·번호를 선택하고 저장을 눌러야 기록돼요. 로그인이나 차량 등록이 필요하면 먼저 해당 화면이 열려요.',
                ),
                const SizedBox(height: 12),
                const Text(
                  '위젯 상단은 주차 기록을 저장한 시각이에요. 화면을 갱신한 시각이 아니에요. 다른 가족의 새 기록은 앱을 열어 확인해 주세요. Android 위젯의 실제 크기와 모양은 홈 화면 앱에 따라 달라질 수 있어요.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: Palette.muted,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('닫기'),
            ),
            if (showSettingsAction)
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('위젯 설정으로 이동'),
              ),
          ],
        ),
      ) ??
      false;
}

class _GuideStep extends StatelessWidget {
  const _GuideStep(this.number, this.text);
  final String number, text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Palette.highlight,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
