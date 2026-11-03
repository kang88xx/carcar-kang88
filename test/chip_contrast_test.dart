import 'package:carcar/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'selected choice labels render with readable contrast and retain typography',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Column(
              children: [
                ChoiceChip(
                  label: const Text('2시간'),
                  selected: true,
                  onSelected: (_) {},
                ),
                ChoiceChip(
                  label: const Text('4시간'),
                  selected: false,
                  onSelected: (_) {},
                ),
                const ChoiceChip(label: Text('사용 불가'), selected: false),
              ],
            ),
          ),
        ),
      );
      final selected = tester
          .renderObject<RenderParagraph>(find.text('2시간'))
          .text
          .style!;
      final unselected = tester
          .renderObject<RenderParagraph>(find.text('4시간'))
          .text
          .style!;
      final foreground = selected.color!.computeLuminance();
      final background = buildTheme().chipTheme.color!.resolve({
        WidgetState.selected,
      })!.computeLuminance();
      final ratio =
          (foreground > background ? foreground + .05 : background + .05) /
          (foreground > background ? background + .05 : foreground + .05);
      expect(ratio, greaterThanOrEqualTo(4.5));
      expect(selected.fontWeight, unselected.fontWeight);
      expect(selected.fontSize, unselected.fontSize);
      expect(unselected.color, isNot(Colors.white));
      final disabled = tester.widget<RawChip>(
        find.descendant(
          of: find.widgetWithText(ChoiceChip, '사용 불가'),
          matching: find.byType(RawChip),
        ),
      );
      expect(disabled.isEnabled, isFalse);
      expect(disabled.onSelected, isNull);
    },
  );
}
