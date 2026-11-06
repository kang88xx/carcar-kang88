"""CI-only signing setup. Never prints credentials or commits generated files."""
import base64
from fnmatch import fnmatchcase
import json
import os
from pathlib import Path
import plistlib
import subprocess
from datetime import datetime, timezone
from uuid import UUID

def run_security(operation, arguments):
    """Never include argv or security output in CI failure reports."""
    try:
        return subprocess.run(['security', *arguments], check=True, capture_output=True)
    except subprocess.CalledProcessError as error:
        raise SystemExit(f'Signing operation {operation} failed (exit {error.returncode}).') from None
    except OSError:
        raise SystemExit(f'Signing operation {operation} could not start.') from None


def validate_profile(profile, target, bundle, team):
    entitlements = profile.get('Entitlements', {})
    if team not in profile.get('TeamIdentifier', []):
        raise SystemExit(f'{target}: profile Team ID mismatch')
    application_id = entitlements.get('application-identifier', '')
    prefix, _, actual_bundle = application_id.partition('.')
    if actual_bundle != bundle:
        raise SystemExit(f'{target}: profile Bundle ID mismatch')
    if 'group.com.kang88.carcar' not in entitlements.get('com.apple.security.application-groups', []):
        raise SystemExit(f'{target}: profile must include App Group')
    groups = entitlements.get('keychain-access-groups', [])
    for required_group in [f'{prefix}.{bundle}', f'{prefix}.com.kang88.carcar.shared']:
        if not any(fnmatchcase(required_group, allowed) for allowed in groups):
            raise SystemExit(f'{target}: profile must authorize private and shared Keychain groups')
    if profile.get('ExpirationDate', datetime.min).replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        raise SystemExit(f'{target}: provisioning profile expired')
    if entitlements.get('get-task-allow') or profile.get('ProvisionedDevices') or profile.get('ProvisionsAllDevices'):
        raise SystemExit(f'{target}: App Store distribution profile required')
    if target == 'APP' and entitlements.get('aps-environment') != 'production':
        raise SystemExit(f'{target}: profile must authorize production APNs')
    apple_sign_in = entitlements.get('com.apple.developer.applesignin')
    if target == 'APP' and (not isinstance(apple_sign_in, list) or 'Default' not in apple_sign_in):
        raise SystemExit(f'{target}: profile must authorize Sign in with Apple')
    canonical = str(UUID(profile['UUID']))
    if profile['UUID'] not in (canonical, canonical.upper()):
        raise SystemExit(f'{target}: invalid profile UUID format')
    return profile['UUID']


def install_profile(data, uuid, home):
    # Xcode 16+ uses UserData; retain the legacy path for older toolchains.
    for relative in ['Library/Developer/Xcode/UserData/Provisioning Profiles',
                     'Library/MobileDevice/Provisioning Profiles']:
        directory = home / relative
        directory.mkdir(parents=True, exist_ok=True)
        destination = directory / f'{uuid}.mobileprovision'
        destination.write_bytes(data)
        destination.chmod(0o600)


work = Path(os.environ['RUNNER_TEMP']) / 'carcar-signing'
work.mkdir(mode=0o700, exist_ok=True)
required = ['APPLE_TEAM_ID', 'IOS_CERTIFICATE_BASE64', 'IOS_CERTIFICATE_PASSWORD',
            'IOS_APP_PROFILE_BASE64', 'IOS_WIDGET_PROFILE_BASE64',
            'ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_PRIVATE_KEY_BASE64']
missing = [name for name in required if not os.environ.get(name)]
if missing:
    raise SystemExit('Missing CI secrets: ' + ', '.join(missing))

certificate = work / 'distribution.p12'
certificate.write_bytes(base64.b64decode(os.environ['IOS_CERTIFICATE_BASE64'], validate=True))
certificate.chmod(0o600)
keychain = work / 'signing.keychain-db'
password = base64.b64encode(os.urandom(32)).decode()
# Avoid set -x in caller. Failure handling must not reveal passwords in argv.
run_security('create-keychain', ['create-keychain', '-p', password, str(keychain)])
run_security('set-keychain-settings', ['set-keychain-settings', '-lut', '21600', str(keychain)])
run_security('unlock-keychain', ['unlock-keychain', '-p', password, str(keychain)])
run_security('import-certificate', ['import', str(certificate), '-P', os.environ['IOS_CERTIFICATE_PASSWORD'], '-A', '-t', 'cert', '-f', 'pkcs12', '-k', str(keychain)])
run_security('set-key-partition-list', ['set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', password, str(keychain)])
run_security('list-keychains', ['list-keychains', '-d', 'user', '-s', str(keychain)])
profiles = {}
for target, env_name, bundle in [('APP', 'IOS_APP_PROFILE_BASE64', 'com.kang88.carcar'), ('WIDGET', 'IOS_WIDGET_PROFILE_BASE64', 'com.kang88.carcar.ParkingWidget')]:
    data = base64.b64decode(os.environ[env_name], validate=True)
    temp = work / f'{target}.mobileprovision'
    temp.write_bytes(data)
    decoded = run_security('decode-profile', ['cms', '-D', '-i', str(temp)]).stdout
    profile = plistlib.loads(decoded)
    uuid = validate_profile(profile, target, bundle, os.environ['APPLE_TEAM_ID'])
    install_profile(data, uuid, Path.home())
    profiles[bundle] = uuid
    with open(os.environ['GITHUB_ENV'], 'a') as output:
        output.write(f'{target}_PROFILE_UUID={uuid}\n')
export = {'method': 'app-store-connect', 'teamID': os.environ['APPLE_TEAM_ID'], 'signingStyle': 'manual', 'provisioningProfiles': profiles, 'uploadSymbols': True}
(work / 'ExportOptions.plist').write_bytes(plistlib.dumps(export))
api_key = {'key_id': os.environ['ASC_KEY_ID'], 'issuer_id': os.environ['ASC_ISSUER_ID'], 'key': base64.b64decode(os.environ['ASC_PRIVATE_KEY_BASE64'], validate=True).decode(), 'in_house': False}
api_file = work / 'api-key.json'
api_file.write_text(json.dumps(api_key))
api_file.chmod(0o600)
with open(os.environ['GITHUB_ENV'], 'a') as output:
    output.write(f'ASC_API_KEY_JSON={api_file}\n')
print('Signing files prepared in runner temporary storage.')
