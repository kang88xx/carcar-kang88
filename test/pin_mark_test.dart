import 'package:carcar/shared/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('brand pin shows the car by default and the parked floor', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Brand(),
              Brand(floor: 'B2', large: true),
            ],
          ),
        ),
      ),
    );
    expect(find.text('차자리'), findsNWidgets(2));
    expect(find.bySemanticsLabel('차자리 마크'), findsOneWidget);
    expect(find.bySemanticsLabel('차자리 마크, 주차 층 B2'), findsOneWidget);
    final marks = tester.widgetList<PinMark>(find.byType(PinMark)).toList();
    expect(marks.map((m) => m.size), [36, 52]);
    expect(marks.map((m) => m.floor), [null, 'B2']);
  });
}
