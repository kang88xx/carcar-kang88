import 'dart:async';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/native_bridge.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/features/management.dart';
import 'package:carcar/shared/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeletionRepository implements ParkingRepository {
  DeletionRepository(this.userId);
  @override
  final String userId;
  @override
  bool get isDemo => false;
  int requests = 0, deletions = 0;
  bool needsApple = false;
  AppleDisconnectFailure? failure;
  Completer<void>? pending;

  @override
  Future<void> deleteAccount({
    Future<AppleCredential?> Function()? reauthenticateApple,
    Future<bool> Function(AppleDisconnectFailure failure)?
    confirmManualAppleDisconnect,
  }) async {
    requests++;
    if (needsApple) {
      if (await reauthenticateApple?.call() == null) {
        throw const AccountDeletionCancelled();
      }
    }
    if (failure != null &&
        await confirmManualAppleDisconnect?.call(failure!) != true) {
      throw const AccountDeletionCancelled();
    }
    await pending?.future;
    deletions++;
  }

  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DeletionHarness {
  DeletionHarness(this.preferences, AppController controller)
    : controller = ValueNotifier(controller);
  final SharedPreferences preferences;
  final ValueNotifier<AppController> controller;
  final completed = <AppController>[];
  int logouts = 0;

  Widget build() => MaterialApp(
    home: ValueListenableBuilder<AppController>(
      valueListenable: controller,
      builder: (_, current, _) => Scaffold(
        body: SingleChildScrollView(
          child: SettingsScreen(
            controller: current,
            preferences: preferences,
            onLogout: () async => logouts++,
            onAccountDeleted: (deleted) async => completed.add(deleted),
          ),
        ),
      ),
    ),
  );
}

Finder deleteRow() => find.byWidgetPredicate(
  (widget) => widget is ActionRow && widget.title == '계정 삭제',
);

Future<void> openDelete(WidgetTester tester) async {
  await tester.ensureVisible(deleteRow());
  await tester.tap(deleteRow());
  await tester.pumpAndSettle();
}

Future<void> confirmDelete(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, '계정 삭제'));
  await tester.pumpAndSettle();
}

void main() {
  late DeletionRepository repository;
  late AppController controller;
  late DeletionHarness harness;
  const channel = MethodChannel('carcar/native');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = DeletionRepository('A');
    controller = AppController(repository);
    harness = DeletionHarness(
      await SharedPreferences.getInstance(),
      controller,
    );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    harness.controller.dispose();
  });

  testWidgets('confirmation cancel leaves account untouched', (tester) async {
    await tester.pumpWidget(harness.build());
    await openDelete(tester);
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();
    expect(repository.requests, 0);
    expect(harness.completed, isEmpty);
    expect(harness.logouts, 0);
    expect(tester.widget<ActionRow>(deleteRow()).onTap, isNotNull);
  });

  testWidgets('duplicate taps open one confirmation and complete once', (
    tester,
  ) async {
    await tester.pumpWidget(harness.build());
    final tap = tester.widget<ActionRow>(deleteRow()).onTap!;
    tap();
    tap();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await confirmDelete(tester);
    expect(repository.deletions, 1);
    expect(harness.completed, [controller]);
    expect(harness.logouts, 0);
  });

  testWidgets(
    'account switch during confirmation cannot delete either account',
    (tester) async {
      await tester.pumpWidget(harness.build());
      await openDelete(tester);
      final next = DeletionRepository('B');
      harness.controller.value = AppController(next);
      await tester.pump();
      await confirmDelete(tester);
      expect(repository.requests, 0);
      expect(next.requests, 0);
      expect(harness.completed, isEmpty);
      expect(harness.logouts, 0);
    },
  );

  testWidgets('disposed controller cannot delete after confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(harness.build());
    await openDelete(tester);
    controller.dispose();
    await confirmDelete(tester);
    expect(repository.requests, 0);
    expect(harness.completed, isEmpty);
  });

  testWidgets('old deletion completion does not log out new controller', (
    tester,
  ) async {
    repository.pending = Completer<void>();
    await tester.pumpWidget(harness.build());
    await openDelete(tester);
    await confirmDelete(tester);
    final next = DeletionRepository('B');
    harness.controller.value = AppController(next);
    await tester.pump();
    repository.pending!.complete();
    await tester.pumpAndSettle();
    expect(repository.deletions, 1);
    expect(next.requests, 0);
    expect(harness.completed, isEmpty);
    expect(harness.logouts, 0);
  });

  testWidgets('native Apple cancellation does not delete or log out', (
    tester,
  ) async {
    repository.needsApple = true;
    var reauthCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'signInWithApple') reauthCalls++;
          return null;
        });
    await tester.pumpWidget(harness.build());
    await openDelete(tester);
    await confirmDelete(tester);
    expect(reauthCalls, 1);
    expect(repository.deletions, 0);
    expect(harness.completed, isEmpty);
    expect(harness.logouts, 0);
    expect(find.text('Apple 연결을 직접 해제할까요?'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  for (final confirmed in [false, true]) {
    testWidgets(
      'manual Apple disconnect requires explicit choice: $confirmed',
      (tester) async {
        repository.failure = const AppleDisconnectFailure(
          'apple_not_configured',
        );
        await tester.pumpWidget(harness.build());
        await openDelete(tester);
        await confirmDelete(tester);
        expect(repository.deletions, 0);
        expect(find.text('Apple 연결을 직접 해제할까요?'), findsOneWidget);
        expect(
          find.textContaining('iPhone 설정 → Apple 계정 → Apple로 로그인'),
          findsOneWidget,
        );
        await tester.tap(
          confirmed
              ? find.widgetWithText(FilledButton, '연결은 직접 해제하고 계정 삭제')
              : find.widgetWithText(TextButton, '취소'),
        );
        await tester.pumpAndSettle();
        expect(repository.deletions, confirmed ? 1 : 0);
        expect(harness.completed.length, confirmed ? 1 : 0);
        expect(harness.logouts, 0);
      },
    );
  }

  testWidgets(
    'account switch while native Apple sheet is open stops deletion',
    (tester) async {
      repository.needsApple = true;
      final nativeResult = Completer<Map<String, Object>>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'signInWithApple') return nativeResult.future;
            return null;
          });
      await tester.pumpWidget(harness.build());
      await openDelete(tester);
      await confirmDelete(tester);
      harness.controller.value = AppController(DeletionRepository('B'));
      await tester.pump();
      nativeResult.complete({
        'identityToken': 'header.payload.signature',
        'authorizationCode': 'code',
        'userIdentifier': 'apple-user',
        'rawNonce': 'a' * 64,
      });
      await tester.pumpAndSettle();
      expect(repository.deletions, 0);
      expect(harness.completed, isEmpty);
      expect(harness.logouts, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('unmounted settings ignores pending deletion completion', (
    tester,
  ) async {
    repository.pending = Completer<void>();
    await tester.pumpWidget(harness.build());
    await openDelete(tester);
    await confirmDelete(tester);
    await tester.pumpWidget(const SizedBox());
    repository.pending!.complete();
    await tester.pumpAndSettle();
    expect(repository.deletions, 1);
    expect(harness.completed, isEmpty);
    expect(harness.logouts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('identity mismatch cannot use manual disconnect confirmation', (
    tester,
  ) async {
    repository.failure = const AppleDisconnectFailure(
      'apple_identity_mismatch',
    );
    await tester.pumpWidget(harness.build());
    await openDelete(tester);
    await confirmDelete(tester);
    expect(find.text('Apple 연결을 직접 해제할까요?'), findsNothing);
    expect(repository.deletions, 0);
    expect(harness.completed, isEmpty);
  });

  testWidgets('account switch during manual confirmation cancels deletion', (
    tester,
  ) async {
    repository.failure = const AppleDisconnectFailure('apple_unavailable');
    await tester.pumpWidget(harness.build());
    await openDelete(tester);
    await confirmDelete(tester);
    harness.controller.value = AppController(DeletionRepository('B'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '연결은 직접 해제하고 계정 삭제'));
    await tester.pumpAndSettle();
    expect(repository.deletions, 0);
    expect(harness.completed, isEmpty);
    expect(harness.logouts, 0);
  });
}
