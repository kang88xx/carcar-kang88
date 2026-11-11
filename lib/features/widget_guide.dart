import 'package:flutter/material.dart';
import '../app/theme.dart';

Future<void> showWidgetGuide(BuildContext context) {
  final platform = Theme.of(context).platform;
  final ios = platform == TargetPlatform.iOS;
  final android = platform == TargetPlatform.android;
  return showDialog<void>(
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
            const Text('정사각형 위젯에서 마지막 주차 위치를 확인하고, 주차 기록을 누르면 앱의 입력 화면이 열려요.'),
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
            if (android)
              const Text(
                'Android 위젯의 실제 크기와 모양은 홈 화면 앱에 따라 달라질 수 있어요.',
                style: TextStyle(fontSize: 12, color: Palette.muted),
              ),
            const SizedBox(height: 20),
            const Text(
              '다른 가족의 새 기록은 앱을 열면 위젯에 보여요.',
              style: TextStyle(fontSize: 12, height: 1.6, color: Palette.muted),
            ),
          ],
        ),
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
