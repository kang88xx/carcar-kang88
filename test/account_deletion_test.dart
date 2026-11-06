import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:carcar/core/native_bridge.dart';
import 'package:carcar/core/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Session sessionFor(String id, {bool expired = false}) => Session(
  accessToken:
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': id, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + (expired ? -60 : 3600)}))).replaceAll('=', '')}.c2ln',
  refreshToken: 'refresh-$id',
  tokenType: 'bearer',
  user: User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);
final credential = AppleCredential(
  identityToken: 'unused',
  authorizationCode: 'single-use',
  userIdentifier: 'apple-A',
  rawNonce: 'a' * 64,
);

class Harness {
  Harness(this.server, this.client);
  final HttpServer server;
  final SupabaseClient client;
  final requests = <({String path, String? bearer, dynamic body})>[];
  bool apple = true;
  bool omitIdentities = false;
  String? failure;
  bool malformedSuccess = false;
  int logoutStatus = 200;
  String? gatePath;
  final entered = Completer<void>();
  final release = Completer<void>();
  late SupabaseParkingRepository repository;

  static Future<Harness> create({bool apple = true}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final h = Harness(server, client)..apple = apple;
    server.listen(h.handle);
    await h.switchTo('A');
    h.repository = SupabaseParkingRepository(client);
    return h;
  }

  Future<void> switchTo(String id) => client.auth
      .recoverSession(jsonEncode(sessionFor(id).toJson()))
      .then((_) {});
  Future<void> handle(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    requests.add((
      path: request.uri.path,
      bearer: request.headers.value('authorization'),
      body: raw.isEmpty ? null : jsonDecode(raw),
    ));
    if (request.uri.path == gatePath) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path == '/auth/v1/user') {
      final user = sessionFor('A').user.toJson();
      user['identities'] = [
        if (apple)
          {
            'id': 'apple-A',
            'identity_id': 'identity-id',
            'user_id': 'A',
            'provider': 'apple',
            'identity_data': {'sub': 'apple-A'},
            'created_at': '2026-01-01T00:00:00Z',
            'last_sign_in_at': '2026-01-01T00:00:00Z',
          },
      ];
      if (omitIdentities) user.remove('identities');
      request.response.write(jsonEncode(user));
    } else if (request.uri.path == '/functions/v1/apple-disconnect') {
      request.response.statusCode = failure == null ? 200 : 409;
      request.response.write(
        jsonEncode(
          failure == null ? {'ok': !malformedSuccess} : {'error': failure},
        ),
      );
    } else if (request.uri.path == '/auth/v1/token') {
      request.response.write(jsonEncode(sessionFor('A').toJson()));
    } else if (request.uri.path == '/auth/v1/logout') {
      request.response.statusCode = logoutStatus;
      request.response.write(jsonEncode({'message': 'cleanup failed'}));
    } else {
      request.response.write('null');
    }
    await request.response.close();
  }

  bool get deleted =>
      requests.any((r) => r.path == '/rest/v1/rpc/delete_my_account');
  Future<void> close() async {
    if (!release.isCompleted) release.complete();
    await client.dispose();
    await server.close(force: true);
  }
}

void main() {
  test(
    'Apple reauthentication pins original bearer, sends only ephemeral code and nonce',
    () async {
      final h = await Harness.create();
      addTearDown(h.close);
      final bearer = 'Bearer ${h.client.auth.currentSession!.accessToken}';
      await h.repository.deleteAccount(
        reauthenticateApple: () async => credential,
      );
      expect(h.requests.map((r) => r.path), [
        '/auth/v1/user',
        '/functions/v1/apple-disconnect',
        '/rest/v1/rpc/delete_my_account',
        '/auth/v1/logout',
      ]);
      expect(h.requests.every((r) => r.bearer == bearer), isTrue);
      expect(h.requests[1].body, {
        'authorizationCode': 'single-use',
        'rawNonce': 'a' * 64,
      });
      expect(h.client.auth.currentUser, isNull);
    },
  );
  test('non Apple account deletes without native authentication', () async {
    final h = await Harness.create(apple: false);
    addTearDown(h.close);
    await h.repository.deleteAccount(
      reauthenticateApple: () async => throw StateError('not used'),
    );
    expect(h.deleted, isTrue);
    expect(h.requests.any((r) => r.path.contains('apple-disconnect')), isFalse);
  });
  test('native cancellation never deletes or offers manual fallback', () async {
    final h = await Harness.create();
    addTearDown(h.close);
    await expectLater(
      h.repository.deleteAccount(
        reauthenticateApple: () async => null,
        confirmManualAppleDisconnect: (_) async =>
            throw StateError('not offered'),
      ),
      throwsA(isA<AccountDeletionCancelled>()),
    );
    expect(h.deleted, isFalse);
  });
  for (final code in [
    'apple_sign_in_unavailable',
    'apple_sign_in_failed',
    'unsupported',
  ]) {
    for (final confirmed in [false, true]) {
      test(
        'native $code offers explicit fallback confirmed=$confirmed',
        () async {
          final h = await Harness.create();
          addTearDown(h.close);
          final operation = h.repository.deleteAccount(
            reauthenticateApple: () async =>
                throw PlatformException(code: code),
            confirmManualAppleDisconnect: (failure) async {
              expect(failure.code, 'apple_unavailable');
              return confirmed;
            },
          );
          if (confirmed) {
            await operation;
          } else {
            await expectLater(
              operation,
              throwsA(isA<AccountDeletionCancelled>()),
            );
          }
          expect(h.deleted, confirmed);
          expect(
            h.requests.any((r) => r.path.contains('apple-disconnect')),
            isFalse,
          );
        },
      );
    }
  }
  for (final code in [
    'apple_credential_invalid',
    'apple_sign_in_busy',
    'unknown',
  ]) {
    test('native $code fails closed without manual fallback', () async {
      final h = await Harness.create();
      addTearDown(h.close);
      await expectLater(
        h.repository.deleteAccount(
          reauthenticateApple: () async => throw PlatformException(code: code),
          confirmManualAppleDisconnect: (_) async =>
              throw StateError('not offered'),
        ),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
      );
      expect(h.deleted, isFalse);
    });
  }
  test('account change during native failure cannot offer fallback', () async {
    final h = await Harness.create();
    addTearDown(h.close);
    await expectLater(
      h.repository.deleteAccount(
        reauthenticateApple: () async {
          await h.switchTo('B');
          throw PlatformException(code: 'apple_sign_in_unavailable');
        },
        confirmManualAppleDisconnect: (_) async =>
            throw StateError('not offered'),
      ),
      throwsA(
        isA<AppleDisconnectFailure>().having(
          (e) => e.code,
          'code',
          'session_invalid',
        ),
      ),
    );
    expect(h.deleted, isFalse);
    expect(h.client.auth.currentUser?.id, 'B');
  });
  test('UI cancellation exception cannot offer native fallback', () async {
    final h = await Harness.create();
    addTearDown(h.close);
    await expectLater(
      h.repository.deleteAccount(
        reauthenticateApple: () async => throw const AccountDeletionCancelled(),
        confirmManualAppleDisconnect: (_) async =>
            throw StateError('not offered'),
      ),
      throwsA(isA<AccountDeletionCancelled>()),
    );
    expect(h.deleted, isFalse);
  });
  for (final code in [
    'apple_identity_mismatch',
    'apple_verification_failed',
    'session_invalid',
    'invalid_request',
  ]) {
    test('$code cannot bypass Apple verification via fallback', () async {
      final h = await Harness.create();
      addTearDown(h.close);
      h.failure = code;
      await expectLater(
        h.repository.deleteAccount(
          reauthenticateApple: () async => credential,
          confirmManualAppleDisconnect: (_) async =>
              throw StateError('not offered'),
        ),
        throwsA(
          isA<AppleDisconnectFailure>().having((e) => e.code, 'code', code),
        ),
      );
      expect(h.deleted, isFalse);
    });
  }
  for (final code in [
    'apple_not_configured',
    'apple_unavailable',
    'apple_reauthentication_required',
  ]) {
    for (final confirmed in [false, true]) {
      test('$code manual fallback confirmation=$confirmed', () async {
        final h = await Harness.create();
        addTearDown(h.close);
        h.failure = code;
        final operation = h.repository.deleteAccount(
          reauthenticateApple: () async => credential,
          confirmManualAppleDisconnect: (failure) async {
            expect(failure.code, code);
            return confirmed;
          },
        );
        if (confirmed) {
          await operation;
        } else {
          await expectLater(
            operation,
            throwsA(isA<AccountDeletionCancelled>()),
          );
        }
        expect(h.deleted, confirmed);
      });
    }
  }
  test(
    'unsupported native reauthentication requires explicit manual confirmation',
    () async {
      final h = await Harness.create();
      addTearDown(h.close);
      await expectLater(
        h.repository.deleteAccount(),
        throwsA(isA<AppleDisconnectFailure>()),
      );
      expect(h.deleted, isFalse);
      await h.repository.deleteAccount(
        confirmManualAppleDisconnect: (_) async => true,
      );
      expect(h.deleted, isTrue);
    },
  );
  for (final returnToA in [false, true]) {
    test(
      'account switch while native prompt is pending, returnToA=$returnToA',
      () async {
        final h = await Harness.create();
        addTearDown(h.close);
        final entered = Completer<void>(), release = Completer<void>();
        final operation = h.repository.deleteAccount(
          reauthenticateApple: () async {
            entered.complete();
            await release.future;
            return credential;
          },
        );
        final result = expectLater(
          operation,
          throwsA(isA<AppleDisconnectFailure>()),
        );
        await entered.future;
        await h.switchTo('B');
        if (returnToA) await h.switchTo('A');
        release.complete();
        await result;
        expect(h.deleted, isFalse);
        expect(
          h.requests.any((r) => r.path.contains('apple-disconnect')),
          isFalse,
        );
        expect(h.client.auth.currentUser?.id, returnToA ? 'A' : 'B');
      },
    );
  }
  for (final path in [
    '/auth/v1/user',
    '/functions/v1/apple-disconnect',
    '/rest/v1/rpc/delete_my_account',
  ]) {
    test(
      'switch while $path pending preserves B and original request bearer',
      () async {
        final h = await Harness.create();
        addTearDown(h.close);
        h.gatePath = path;
        final bearer = 'Bearer ${h.client.auth.currentSession!.accessToken}';
        final operation = h.repository.deleteAccount(
          reauthenticateApple: () async => credential,
        );
        final result = path.contains('delete_my_account')
            ? operation
            : expectLater(operation, throwsA(isA<AppleDisconnectFailure>()));
        await h.entered.future;
        await h.switchTo('B');
        h.release.complete();
        await result;
        expect(h.deleted, path.contains('delete_my_account'));
        expect(h.requests.every((r) => r.bearer == bearer), isTrue);
        expect(h.requests.any((r) => r.path == '/auth/v1/logout'), isFalse);
        expect(h.client.auth.currentUser?.id, 'B');
      },
    );
  }
  test('manual fallback cannot resume after switching account', () async {
    final h = await Harness.create();
    addTearDown(h.close);
    await expectLater(
      h.repository.deleteAccount(
        confirmManualAppleDisconnect: (_) async {
          await h.switchTo('B');
          return true;
        },
      ),
      throwsA(isA<AppleDisconnectFailure>()),
    );
    expect(h.deleted, isFalse);
  });
  test(
    'server deletion remains successful if local logout network cleanup fails',
    () async {
      final h = await Harness.create(apple: false);
      addTearDown(h.close);
      h.logoutStatus = 400;
      await h.repository.deleteAccount();
      expect(h.deleted, isTrue);
      expect(h.client.auth.currentUser, isNull);
    },
  );
  test('missing server identities cannot skip Apple verification', () async {
    final h = await Harness.create();
    addTearDown(h.close);
    h.omitIdentities = true;
    await expectLater(
      h.repository.deleteAccount(),
      throwsA(isA<AppleDisconnectFailure>()),
    );
    expect(h.deleted, isFalse);
  });
  test(
    'ordinary token refresh does not cancel the captured account deletion',
    () async {
      final h = await Harness.create();
      addTearDown(h.close);
      await h.repository.deleteAccount(
        reauthenticateApple: () async {
          await h.client.auth.refreshSession();
          return credential;
        },
      );
      expect(h.deleted, isTrue);
    },
  );
  test(
    'expired session fails before network or native authentication',
    () async {
      final h = await Harness.create();
      addTearDown(h.close);
      h.client.auth.currentSession!.expiresAt = 1;
      await expectLater(
        h.repository.deleteAccount(),
        throwsA(isA<AppleDisconnectFailure>()),
      );
      expect(h.requests, isEmpty);
    },
  );
  test(
    'malformed Apple success response never permits manual fallback',
    () async {
      final h = await Harness.create();
      addTearDown(h.close);
      h.malformedSuccess = true;
      await expectLater(
        h.repository.deleteAccount(
          reauthenticateApple: () async => credential,
          confirmManualAppleDisconnect: (_) async =>
              throw StateError('not offered'),
        ),
        throwsA(
          isA<AppleDisconnectFailure>().having(
            (e) => e.code,
            'code',
            'apple_verification_failed',
          ),
        ),
      );
      expect(h.deleted, isFalse);
    },
  );
  test(
    'old repository rejects missing or different session before any request',
    () async {
      final h = await Harness.create();
      addTearDown(h.close);
      await h.switchTo('B');
      await expectLater(
        h.repository.deleteAccount(),
        throwsA(isA<AppException>()),
      );
      expect(h.requests, isEmpty);
      await h.client.auth.signOut();
      h.requests.clear();
      await expectLater(
        h.repository.deleteAccount(),
        throwsA(isA<AppException>()),
      );
      expect(h.requests, isEmpty);
    },
  );
}
