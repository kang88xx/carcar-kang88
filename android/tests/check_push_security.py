"""Static release guards; real token delivery still needs platform runtime QA."""
from pathlib import Path
import plistlib
import xml.etree.ElementTree as E

root = Path(__file__).resolve().parents[2]
android = root / 'android/app/src/main'
ns = '{http://schemas.android.com/apk/res/android}'
manifest = E.parse(android / 'AndroidManifest.xml')
app = manifest.find('application')
metadata = {x.get(ns+'name'): x.get(ns+'value') for x in app.findall('meta-data')}
for name in ['firebase_messaging_auto_init_enabled', 'firebase_analytics_collection_enabled',
             'firebase_messaging_notification_delegation_enabled', 'firebase_messaging_installation_id_enabled']:
    assert metadata[name] == 'false', name
service = next(x for x in app.findall('service') if x.get(ns+'name') == '.FamilyMessagingService')
assert service.get(ns+'exported') == 'false'
receiver = (android / 'kotlin/com/kang88/carcar/FamilyMessagingService.kt').read_text()
assert 'message.data["kind"]' in receiver
for forbidden in ['message.notification', 'message.data["floor"]', 'message.data["plate"]', 'message.data["spot"]']:
    assert forbidden not in receiver, forbidden
for source in [android / 'kotlin/com/kang88/carcar/PushNotifications.kt', root / 'ios/Runner/PushNotifications.swift']:
    text = source.read_text()
    for secret in ['accessToken', 'refreshToken', 'service_role']:
        assert secret not in text
    assert 'Log.' not in text and 'print(' not in text
entitlements = plistlib.loads((root / 'ios/Runner/Runner.entitlements').read_bytes())
assert entitlements['aps-environment'] == '$(APS_ENVIRONMENT)'
assert 'aps-environment' not in plistlib.loads((root / 'ios/ParkingWidget/ParkingWidget.entitlements').read_bytes())
project = (root / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
assert project.count('APS_ENVIRONMENT = production;') == 2
assert project.count('APS_ENVIRONMENT = development;') == 1
assert 'PushNotifications.swift in Sources' in project
print('PASS: push opt-in metadata, private service, generic notification content, credential boundaries, APNs configuration')
