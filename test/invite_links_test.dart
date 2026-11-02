import 'package:carcar/core/invite_links.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RejectingInvitePreferences implements SharedPreferences {
  RejectingInvitePreferences(this.backing);
  final SharedPreferences backing;
  @override
  String? getString(String key) => backing.getString(key);
  @override
  Future<bool> setString(String key, String value) async => false;
  @override
  Future<bool> remove(String key) async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const code = '0123456789abcdef0123456789abcdef0123456789abcdef';
  test('invitation round trips without putting the token in server query', () {
    final link = inviteLink(code);
    expect(Uri.parse(link).query, isEmpty);
    expect(parseInvite(link), code);
    expect(parseInvite(' $code '), code);
    expect(parseInvite(code.toUpperCase()), code);
    expect(parseInvite('com.kang88.carcar://invite?invite_code=$code'), code);
  });
  test('OAuth callbacks and lookalike links never become invitations', () {
    for (final value in [
      'com.kang88.carcar://login-callback?code=$code',
      'com.kang88.carcar://invite?code=$code',
      'https://evil.example/invite/#invite_code=$code',
      'https://kang88xx.github.io.evil.example/carcar-kang88/invite/#invite_code=$code',
      'https://user@kang88xx.github.io/carcar-kang88/invite/#invite_code=$code',
      'https://kang88xx.github.io:8443/carcar-kang88/invite/#invite_code=$code',
      'https://kang88xx.github.io/carcar-kang88/invite/?invite_code=$code',
      'com.kang88.carcar://invite?invite_code=%XX',
      '123456',
    ]) {
      expect(parseInvite(value), isNull, reason: value);
    }
    expect(
      isAuthCallback(Uri.parse('com.kang88.carcar://login-callback?code=test')),
      isTrue,
    );
    expect(
      isAuthCallback(Uri.parse('com.kang88.carcar://invite?code=test')),
      isFalse,
    );
    expect(
      isAuthCallback(Uri.parse('https://login-callback?code=test')),
      isFalse,
    );
  });
  test(
    'pending invitation survives app restart and ignores OAuth redirect',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = PendingInvite(prefs);
      expect(await first.receive(Uri.parse(inviteLink(code))), isTrue);
      final restarted = PendingInvite(prefs);
      expect(restarted.code, code);
      expect(
        await restarted.receive(
          Uri.parse('com.kang88.carcar://login-callback?code=oauth'),
        ),
        isFalse,
      );
      expect(restarted.code, code);
      await restarted.clear();
      expect(PendingInvite(prefs).code, isNull);
    },
  );
  test('expired or corrupted local invitations are not offered', () async {
    SharedPreferences.setMockInitialValues({
      'carcar.pending_invite.v1': '1:$code',
    });
    final prefs = await SharedPreferences.getInstance();
    expect(PendingInvite(prefs).code, isNull);
    await prefs.setString('carcar.pending_invite.v1', 'invalid');
    expect(PendingInvite(prefs).code, isNull);
  });
  test(
    'failed invitation disk write is reported and retained in current session',
    () async {
      SharedPreferences.setMockInitialValues({});
      final pending = PendingInvite(
        RejectingInvitePreferences(await SharedPreferences.getInstance()),
      );
      await expectLater(
        pending.receive(Uri.parse(inviteLink(code))),
        throwsStateError,
      );
      expect(pending.code, code);
    },
  );
  test(
    'failed invitation removal is reported without reopening in current session',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await PendingInvite(prefs).receive(Uri.parse(inviteLink(code)));
      final pending = PendingInvite(RejectingInvitePreferences(prefs));
      await expectLater(pending.clear(), throwsStateError);
      expect(pending.code, isNull);
      expect(PendingInvite(prefs).code, code);
    },
  );
}
