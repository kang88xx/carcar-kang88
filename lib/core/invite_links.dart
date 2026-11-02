import 'package:shared_preferences/shared_preferences.dart';

const inviteSite = 'https://kang88xx.github.io/carcar-kang88/invite/';
const _pendingInviteKey = 'carcar.pending_invite.v1';
final _inviteCode = RegExp(r'^[0-9a-f]{48}$');

bool isAuthCallback(Uri uri) =>
    uri.scheme == 'com.kang88.carcar' &&
    uri.host == 'login-callback' &&
    uri.userInfo.isEmpty &&
    !uri.hasPort &&
    (uri.path.isEmpty || uri.path == '/');

String? parseInvite(String input) {
  final text = input.trim();
  if (_inviteCode.hasMatch(text.toLowerCase())) return text.toLowerCase();
  final uri = Uri.tryParse(text);
  if (uri == null ||
      text.length > 2048 ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort) {
    return null;
  }
  final native = uri.scheme == 'com.kang88.carcar' && uri.host == 'invite';
  final web =
      uri.scheme == 'https' &&
      uri.host == 'kang88xx.github.io' &&
      uri.path == '/carcar-kang88/invite/';
  if (!native && !web) return null;
  try {
    final code =
        (native
                ? uri.queryParameters
                : Uri.splitQueryString(uri.fragment))['invite_code']
            ?.toLowerCase();
    return code != null && _inviteCode.hasMatch(code) ? code : null;
  } on FormatException {
    return null;
  }
}

String inviteLink(String code) {
  if (!_inviteCode.hasMatch(code)) {
    throw ArgumentError('Invalid invitation code');
  }
  // Fragment keeps the invitation out of web server access logs.
  return '$inviteSite#invite_code=$code';
}

class PendingInvite {
  PendingInvite(this.preferences);
  final SharedPreferences preferences;
  String? _memoryValue;
  String? get code {
    final stored = _memoryValue ?? preferences.getString(_pendingInviteKey);
    if (stored == null) return null;
    final parts = stored.split(':');
    if (parts.length != 2 || !_inviteCode.hasMatch(parts[1])) return null;
    final expiry = int.tryParse(parts[0]);
    if (expiry == null || DateTime.now().millisecondsSinceEpoch >= expiry) {
      return null;
    }
    return parts[1];
  }

  Future<bool> receive(Uri uri) async {
    final value = parseInvite(uri.toString());
    if (value == null) return false;
    final expiry = DateTime.now()
        .add(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    _memoryValue = '$expiry:$value';
    if (!await preferences.setString(_pendingInviteKey, _memoryValue!)) {
      throw StateError('Invitation could not be saved');
    }
    return true;
  }

  Future<void> clear() async {
    _memoryValue = '';
    if (!await preferences.remove(_pendingInviteKey)) {
      throw StateError('Invitation could not be removed');
    }
  }
}
