"""Static security/configuration guardrails; does not claim iOS compilation/runtime QA."""
from pathlib import Path
import plistlib
root = Path(__file__).resolve().parents[2]
def read(path): return (root / path).read_text()
for target in ('Runner', 'ParkingWidget'):
    ent = plistlib.loads((root / f'ios/{target}/{target}.entitlements').read_bytes())
    info = plistlib.loads((root / f'ios/{target}/Info.plist').read_bytes())
    assert ent['keychain-access-groups'] == ['$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)', '$(AppIdentifierPrefix)com.kang88.carcar.shared']
    assert info['WidgetKeychainGroup'] == ent['keychain-access-groups'][1]
swift = read('ios/Shared/WidgetSession.swift')
assert 'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly' in swift
assert 'SecItemDelete' in swift and 'flock(fd, LOCK_EX)' in swift
assert 'defaults.set' not in swift.split('enum WidgetSnapshots')[0] and 'refreshToken' not in swift
intent = read('ios/ParkingWidget/ParkingIntent.swift')
assert 'completionHandler(nil)' in intent and '(200...299).contains' in intent
assert 'generation' in intent and 'operation' in intent and 'created_by' in intent
kotlin = read('android/app/src/main/kotlin/com/kang88/carcar/WidgetSession.kt')
assert 'AES/GCM/NoPadding' in kotlin and 'AndroidKeyStore' in kotlin
assert 'putString("ciphertext"' in kotlin and 'refreshToken' not in kotlin
save = read('android/app/src/main/kotlin/com/kang88/carcar/WidgetActions.kt')
assert 'instanceFollowRedirects = false' in save and 'code in 200..299' in save
assert 'WidgetRules.sameOperation' in save and 'created_by' in save
manifest = read('android/app/src/main/AndroidManifest.xml')
assert 'android:allowBackup="false"' in manifest
print('Widget secure storage, redirect, response, entitlement guardrails passed (static)')
