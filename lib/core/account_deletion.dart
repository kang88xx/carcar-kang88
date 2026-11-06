/// User explicitly cancelled; no account deletion was submitted.
class AccountDeletionCancelled implements Exception {
  const AccountDeletionCancelled();
}

/// Fixed, non-sensitive failure codes from the Apple disconnect service.
class AppleDisconnectFailure implements Exception {
  const AppleDisconnectFailure(this.code);
  final String code;

  bool get allowsManualDisconnect => const {
    'apple_not_configured',
    'apple_unavailable',
    'apple_reauthentication_required',
  }.contains(code);

  String get message => switch (code) {
    'session_invalid' => '로그인 상태가 변경되었어요. 다시 로그인해 주세요.',
    'apple_identity_mismatch' => '현재 계정에 연결된 Apple 계정으로 다시 인증해 주세요.',
    'apple_verification_failed' => 'Apple 계정을 확인하지 못했어요. 계정 삭제를 중단했어요.',
    'apple_reauthentication_required' => 'Apple 인증이 만료되었어요. 다시 인증해 주세요.',
    'apple_not_configured' ||
    'apple_unavailable' => 'Apple 연결을 자동으로 해제하지 못했어요.',
    _ => 'Apple 연결 해제 요청을 확인하지 못했어요. 다시 시도해 주세요.',
  };

  @override
  String toString() => message;
}
