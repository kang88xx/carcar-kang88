"""Credential-free regression tests for signing failure redaction."""
import ast
from datetime import datetime, timedelta, timezone
from fnmatch import fnmatchcase
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from uuid import UUID

# Load the isolated subprocess boundary without running provisioning setup.
source = Path(__file__).with_name('prepare_signing.py')
function = next(node for node in ast.parse(source.read_text()).body
                if isinstance(node, ast.FunctionDef) and node.name == 'run_security')
namespace = {'subprocess': subprocess}
exec(compile(ast.Module(body=[function], type_ignores=[]), str(source), 'exec'), namespace)
run_security = namespace['run_security']
profile_function = next(node for node in ast.parse(source.read_text()).body
                        if isinstance(node, ast.FunctionDef) and node.name == 'validate_profile')
profile_namespace = {'datetime': datetime, 'timezone': timezone, 'UUID': UUID, 'fnmatchcase': fnmatchcase}
exec(compile(ast.Module(body=[profile_function], type_ignores=[]), str(source), 'exec'), profile_namespace)
validate_profile = profile_namespace['validate_profile']
install_function = next(node for node in ast.parse(source.read_text()).body
                        if isinstance(node, ast.FunctionDef) and node.name == 'install_profile')
exec(compile(ast.Module(body=[install_function], type_ignores=[]), str(source), 'exec'), profile_namespace)
install_profile = profile_namespace['install_profile']


class ProfileEntitlementTest(unittest.TestCase):
    def setUp(self):
        self.bundle = 'com.kang88.carcar'
        self.profile = {
            'TeamIdentifier': ['TEAM'],
            'UUID': '40f9803a-8e78-438b-856f-715ba1bc4324',
            'ExpirationDate': datetime.now(timezone.utc) + timedelta(days=30),
            'Entitlements': {
                'application-identifier': 'PREFIX.' + self.bundle,
                'com.apple.security.application-groups': ['group.com.kang88.carcar'],
                'keychain-access-groups': ['PREFIX.*'],
                'aps-environment': 'production',
                'com.apple.developer.applesignin': ['Default'],
            },
        }

    def check_profile(self):
        return validate_profile(self.profile, 'APP', self.bundle, 'TEAM')

    def test_matching_wildcard_uses_app_prefix_not_team_id(self):
        self.assertEqual(self.check_profile(), self.profile['UUID'])

    def test_profile_uuid_case_is_preserved_for_xcode_lookup(self):
        self.profile['UUID'] = self.profile['UUID'].upper()
        self.assertEqual(self.check_profile(), self.profile['UUID'])

    def test_original_cms_is_installed_privately_for_new_and_legacy_xcode(self):
        data = b'ORIGINAL-CMS-BYTES'
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            install_profile(data, self.check_profile(), home)
            files = list(home.rglob('*.mobileprovision'))
            self.assertEqual(len(files), 2)
            self.assertTrue(any('/Developer/Xcode/UserData/' in str(p) for p in files))
            for path in files:
                self.assertEqual(path.read_bytes(), data)
                self.assertEqual(path.name, self.profile['UUID'] + '.mobileprovision')
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_exact_private_and_shared_groups_are_accepted(self):
        self.profile['Entitlements']['keychain-access-groups'] = [
            'PREFIX.' + self.bundle, 'PREFIX.com.kang88.carcar.shared']
        self.check_profile()

    def test_missing_shared_group_is_rejected(self):
        self.profile['Entitlements']['keychain-access-groups'] = ['PREFIX.' + self.bundle]
        with self.assertRaisesRegex(SystemExit, 'private and shared Keychain'):
            self.check_profile()

    def test_missing_private_group_is_rejected(self):
        self.profile['Entitlements']['keychain-access-groups'] = ['PREFIX.com.kang88.carcar.shared']
        with self.assertRaisesRegex(SystemExit, 'private and shared Keychain'):
            self.check_profile()

    def test_other_app_profile_is_rejected(self):
        self.profile['Entitlements']['application-identifier'] = 'PREFIX.kr.base60.app'
        with self.assertRaisesRegex(SystemExit, 'Bundle ID mismatch'):
            self.check_profile()

    def test_missing_app_group_is_rejected(self):
        self.profile['Entitlements']['com.apple.security.application-groups'] = []
        with self.assertRaisesRegex(SystemExit, 'include App Group'):
            self.check_profile()

    def test_expired_profile_is_rejected(self):
        self.profile['ExpirationDate'] = datetime.now(timezone.utc) - timedelta(seconds=1)
        with self.assertRaisesRegex(SystemExit, 'expired'):
            self.check_profile()

    def test_development_profile_is_rejected(self):
        self.profile['Entitlements']['get-task-allow'] = True
        with self.assertRaisesRegex(SystemExit, 'App Store distribution'):
            self.check_profile()

    def test_app_profile_without_push_capability_is_rejected(self):
        del self.profile['Entitlements']['aps-environment']
        with self.assertRaisesRegex(SystemExit, 'APP: profile must authorize production APNs'):
            self.check_profile()

    def test_app_profile_with_development_push_environment_is_rejected(self):
        self.profile['Entitlements']['aps-environment'] = 'development'
        with self.assertRaisesRegex(SystemExit, 'APP: profile must authorize production APNs'):
            self.check_profile()

    def test_app_requires_apple_sign_in_array(self):
        for value in [None, [], ['Other'], 'Default']:
            with self.subTest(value=value):
                self.profile['Entitlements']['com.apple.developer.applesignin'] = value
                with self.assertRaisesRegex(SystemExit, 'Sign in with Apple'):
                    self.check_profile()

    def test_widget_profile_does_not_require_push_capability(self):
        bundle = self.bundle + '.ParkingWidget'
        self.profile['Entitlements']['application-identifier'] = 'PREFIX.' + bundle
        del self.profile['Entitlements']['aps-environment']
        del self.profile['Entitlements']['com.apple.developer.applesignin']
        self.assertEqual(
            validate_profile(self.profile, 'WIDGET', bundle, 'TEAM'),
            self.profile['UUID'],
        )

    def test_widget_push_exemption_keeps_shared_keychain_requirement(self):
        bundle = self.bundle + '.ParkingWidget'
        self.profile['Entitlements']['application-identifier'] = 'PREFIX.' + bundle
        self.profile['Entitlements']['keychain-access-groups'] = ['PREFIX.' + bundle]
        del self.profile['Entitlements']['aps-environment']
        with self.assertRaisesRegex(SystemExit, 'WIDGET: profile must authorize private and shared Keychain groups'):
            validate_profile(self.profile, 'WIDGET', bundle, 'TEAM')

    def test_wrong_team_is_rejected(self):
        self.profile['TeamIdentifier'] = ['OTHER']
        with self.assertRaisesRegex(SystemExit, 'Team ID mismatch'):
            self.check_profile()


class SigningRedactionTest(unittest.TestCase):
    def test_failed_security_command_hides_arguments_and_output(self):
        secret = 'TEST-PRIVATE-KEYCHAIN-PASSWORD'
        error = subprocess.CalledProcessError(73, ['security', 'unlock-keychain', '-p', secret],
                                             output=secret.encode(), stderr=secret.encode())
        with patch.object(subprocess, 'run', side_effect=error) as runner:
            with self.assertRaises(SystemExit) as caught:
                run_security('unlock-keychain', ['unlock-keychain', '-p', secret])
        self.assertEqual(str(caught.exception), 'Signing operation unlock-keychain failed (exit 73).')
        self.assertNotIn(secret, str(caught.exception))
        self.assertTrue(caught.exception.__suppress_context__)
        self.assertTrue(runner.call_args.kwargs['capture_output'])

    def test_missing_security_binary_hides_exception_details(self):
        with patch.object(subprocess, 'run', side_effect=FileNotFoundError('SECRET-PATH')):
            with self.assertRaises(SystemExit) as caught:
                run_security('create-keychain', ['create-keychain', '-p', 'SECRET'])
        self.assertEqual(str(caught.exception), 'Signing operation create-keychain could not start.')
        self.assertTrue(caught.exception.__suppress_context__)

    def test_success_returns_profile_bytes_without_printing(self):
        completed = subprocess.CompletedProcess(['security'], 0, stdout=b'profile', stderr=b'')
        with patch.object(subprocess, 'run', return_value=completed):
            self.assertIs(run_security('decode-profile', ['cms']), completed)


if __name__ == '__main__':
    unittest.main()
