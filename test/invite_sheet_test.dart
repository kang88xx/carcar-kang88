import 'dart:async';
import 'package:carcar/app/theme.dart';
import 'package:carcar/core/app_controller.dart';
import 'package:carcar/core/invite_links.dart';
import 'package:carcar/core/models.dart';
import 'package:carcar/core/repository.dart';
import 'package:carcar/features/management.dart';
import 'package:carcar/shared/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final code = 'ab' * 24;

class OwnerRepository implements ParkingRepository {
  int invites = 0;
  @override
  bool get isDemo => false;
  @override
  String get userId => 'owner';
  @override
  Future<List<Vehicle>> vehicles() async => const [
    Vehicle(
      id: 'car',
      ownerId: 'owner',
      name: '우리 차',
      plate: '12가 3456',
      apartment: '집',
    ),
  ];
  @override
  Future<List<ParkingRecord>> records(String vehicleId) async => [];
  @override
  Future<List<FamilyMember>> members(String vehicleId) async => const [
    FamilyMember(id: 'owner', name: '엄마', owner: true),
  ];
  @override
  Future<Map<String, dynamic>> invite(String vehicleId) async {
    invites++;
    return {'code': code, 'expires_at': '2026-11-12T03:00:00Z'};
  }

  @override
  void watch(void Function() onChange) {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A second member whose removal waits for the server.
class RemovingRepository extends OwnerRepository {
  final removal = Completer<void>();
  @override
  Future<List<FamilyMember>> members(String vehicleId) async => const [
    FamilyMember(id: 'owner', name: '엄마', owner: true),
    FamilyMember(id: 'son', name: '아들', owner: false),
  ];
  @override
  Future<void> removeMember(String vehicleId, String userId) => removal.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('carcar/native');
  late OwnerRepository repository;
  late List<String> shared;
  String? clipboard;
  // What the platform share sheet answers: shown, not shown, or an error.
  Object? shareResult;

  setUp(() {
    repository = OwnerRepository();
    shared = [];
    clipboard = null;
    shareResult = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method != 'shareText') return null;
      shared.add((call.arguments as Map)['text'] as String);
      if (shareResult is Exception) throw shareResult! as Exception;
      return shareResult;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  // The invite button behind the sheet keeps its progress ring while the sheet
  // is open, so frames are advanced by time instead of waiting for stillness.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  // A phone, where the sheet covers the place a snackbar would appear.
  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController(repository);
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: FamilyScreen(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('가족 초대하기'));
    await settle(tester);
    expect(find.byType(Dialog), findsOneWidget);
  }

  Finder inSheet(Finder finder) =>
      find.descendant(of: find.byType(Dialog), matching: finder);
  Finder button<T extends ButtonStyleButton>(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is T),
  );

  void sheetTest(String description, WidgetTesterCallback body) => testWidgets(
    description,
    body,
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  sheetTest('sharing the link leads and the raw code is not on screen', (
    tester,
  ) async {
    await openSheet(tester);
    expect(button<FilledButton>('초대 링크 공유'), findsOneWidget);
    expect(button<OutlinedButton>('코드 복사'), findsOneWidget);
    expect(find.textContaining(code), findsNothing);
    expect(find.text('초대 코드'), findsNothing);
    expect(
      inSheet(find.text('한 사람만, 24시간 안에 쓸 수 있어요. 가족마다 새로 보내 주세요.')),
      findsOneWidget,
    );
    expect(inSheet(find.textContaining('만료: ')), findsOneWidget);

    await tester.tap(find.text('초대 링크 공유'));
    await settle(tester);
    final message = shared.single;
    expect(message, contains(inviteLink(code)));
    expect(message, contains('한 사람만, 24시간 안에 쓸 수 있어요.'));
    // The code travels inside the link only, not as a second raw line.
    expect(message, isNot(contains('초대 코드')));
    expect(code.allMatches(message), hasLength(1));
    expect(inSheet(find.byType(StatusNotice)), findsNothing);
    expect(clipboard, isNull);
  });

  sheetTest('copying the code is confirmed on the button inside the sheet', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.tap(find.text('코드 복사'));
    await tester.pump();
    expect(clipboard, code);
    expect(inSheet(find.text('복사했어요')), findsOneWidget);
    expect(inSheet(find.byIcon(Icons.check_rounded)), findsOneWidget);
    expect(find.text('코드 복사'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(inSheet(find.text('코드 복사')), findsOneWidget);
    expect(find.text('복사했어요'), findsNothing);
  });

  sheetTest('a share sheet that did not open reports the copy in the sheet', (
    tester,
  ) async {
    shareResult = false;
    await openSheet(tester);
    await tester.tap(find.text('초대 링크 공유'));
    await settle(tester);
    expect(clipboard, shared.single);
    expect(inSheet(find.text('초대 링크를 복사했어요. 가족에게 보내 주세요.')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  sheetTest('a share failure is shown in the sheet, not behind it', (
    tester,
  ) async {
    shareResult = PlatformException(code: 'share_failed');
    await openSheet(tester);
    await tester.tap(find.text('초대 링크 공유'));
    await settle(tester);
    final notice = tester.widget<StatusNotice>(
      inSheet(find.byType(StatusNotice)),
    );
    expect(notice.error, isTrue);
    expect(clipboard, isNull);
    expect(find.byType(SnackBar), findsNothing);
  });

  sheetTest('only inviting spins the invite button', (tester) async {
    await openSheet(tester);
    // Inviting: the ring is on the invite button behind the sheet.
    expect(
      find.descendant(
        of: find.byType(BusyButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();

    final removing = RemovingRepository();
    final controller = AppController(removing);
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: FamilyScreen(
              key: const ValueKey('removing'),
              controller: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('아들 구성원 제거'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('공유 해제'));
    await settle(tester);
    // Removing: the invite button waits, without claiming the progress.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('가족 초대하기'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(button<FilledButton>('가족 초대하기')).onPressed,
      isNull,
    );
    removing.removal.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(button<FilledButton>('가족 초대하기')).onPressed,
      isNotNull,
    );
    expect(removing.invites, 0);
  });

  sheetTest('one tap outside keeps the sheet; the close button ends it', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.tapAt(const Offset(12, 12));
    await settle(tester);
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.byTooltip('닫기'));
    await settle(tester);
    expect(find.byType(Dialog), findsNothing);
    expect(repository.invites, 1);
  });
}
