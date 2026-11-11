import 'package:carcar/core/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'account_deletion_test.dart' show Harness;

/// The app forgets a received invitation only for [InvalidInviteException],
/// so the server's refusal reasons must keep mapping to the right type.
void main() {
  const path = '/rest/v1/rpc/redeem_invite_securely';
  final code = 'a' * 48;

  Future<Harness> answering(Map<String, Object?> answer) async {
    final h = await Harness.create(apple: false);
    addTearDown(h.close);
    h.answers[path] = answer;
    return h;
  }

  test(
    'an accepted invitation returns the vehicle the server joined',
    () async {
      final h = await answering({'ok': true, 'vehicle_id': 'family-car'});
      expect(await h.repository.join(' $code '), 'family-car');
      expect(h.requests.single.path, path);
      expect(h.requests.single.body, {'p_code': code});
    },
  );
  test(
    'a used, expired or unknown invitation is an invalid invitation',
    () async {
      final h = await answering({'ok': false, 'error': 'invalid_invite'});
      await expectLater(
        h.repository.join(code),
        throwsA(
          isA<InvalidInviteException>().having(
            (e) => e.message,
            'message',
            '이미 사용했거나 24시간이 지난 초대예요. 가족에게 새 초대를 받아 주세요.',
          ),
        ),
      );
    },
  );
  for (final (error, hint) in const [
    ('rate_limited', '10분 뒤'),
    ('already_has_vehicle', '이미 연결된 차량'),
  ]) {
    test(
      '$error keeps the invitation: it is not an invalid invitation',
      () async {
        final h = await answering({'ok': false, 'error': error});
        await expectLater(
          h.repository.join(code),
          throwsA(
            isA<AppException>()
                .having((e) => e, 'type', isNot(isA<InvalidInviteException>()))
                .having((e) => e.message, 'message', contains(hint)),
          ),
        );
      },
    );
  }
}
