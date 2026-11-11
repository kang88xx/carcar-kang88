import 'package:carcar/app/theme.dart';
import 'package:carcar/features/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignedOutAuth implements GoTrueClient {
  @override
  User? get currentUser => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SignedOutClient implements SupabaseClient {
  @override
  final GoTrueClient auth = SignedOutAuth();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf'));
    await font.load();
  });

  // Safe areas of the real devices with these screen sizes: a Dynamic Island
  // iPhone (393×852) and a home-button iPhone (375×667).
  for (final (size, top, bottom) in const [
    (Size(393, 852), 59.0, 34.0),
    (Size(375, 667), 20.0, 0.0),
  ]) {
    testWidgets(
      'every sign-in action fits ${size.width.toInt()}x${size.height.toInt()} '
      'without scrolling',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = FakeViewPadding(top: top, bottom: bottom);
        tester.view.viewPadding = FakeViewPadding(top: top, bottom: bottom);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: AuthScreen(client: SignedOutClient(), onDemo: () async {}),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in ['Apple로 계속하기', 'Google로 계속하기', '가입 없이 먼저 둘러보기']) {
          final action = find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          );
          final bounds = tester.getRect(action);
          expect(bounds.top, greaterThanOrEqualTo(top), reason: label);
          expect(
            bounds.bottom,
            lessThanOrEqualTo(size.height - bottom),
            reason: label,
          );
          expect(bounds.left, greaterThanOrEqualTo(0), reason: label);
          expect(bounds.right, lessThanOrEqualTo(size.width), reason: label);
          expect(find.text(label).hitTestable(), findsOneWidget);
        }
        expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable))
              .position
              .maxScrollExtent,
          0,
        );
        // The one example of what gets remembered stays.
        expect(find.text('B2'), findsOneWidget);
        expect(find.text('C 구역 · 24번'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets(
    'sign-in labels stay on one line inside their buttons at 320px with 1.3x text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: AuthScreen(client: SignedOutClient(), onDemo: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['Apple로 계속하기', 'Google로 계속하기']) {
        final text = find.text(label);
        await tester.ensureVisible(text);
        final lines = tester
            .renderObject<RenderParagraph>(text)
            .getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: label.length),
            )
            .map((box) => box.top)
            .toSet();
        expect(lines, hasLength(1), reason: label);
        final bounds = tester.getRect(text);
        final action = tester.getRect(
          find.ancestor(
            of: text,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );
        expect(bounds.left, greaterThanOrEqualTo(action.left), reason: label);
        expect(bounds.right, lessThanOrEqualTo(action.right), reason: label);
        expect(action.height, 56, reason: label);
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
