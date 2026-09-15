"""Account gate uses a fake subprocess, never a real account or external service."""
import contextlib
import io
from pathlib import Path
import sys
import tempfile
import time
import unittest
from script.steam_auth_gate import GateError, run_gate

ROOT = Path(__file__).resolve().parents[2]
LOGIN_PANEL = ROOT / 'MyWallpaperX/Modules/SteamWorkshop/UI/SteamLoginPanelController.swift'

FAKE = r'''
import json, sys, time
mode = sys.argv[1]
def emit(**value):
    print(json.dumps(dict(v=1, processEpoch=1, **value)), flush=True)
if mode == 'deadline': time.sleep(10); sys.exit()
emit(type='ready', protocol=1)
request = json.loads(sys.stdin.readline())
assert request['accountEpoch'] == 1
assert request['authAttemptId']
attempt = request['authAttemptId']
base = dict(requestId='gate-login', accountEpoch=1, authAttemptId=attempt)
if mode == 'wrong':
    emit(type='result', ok=False, error={'code': 'accessDenied', 'message':'SECRET'}, **base); sys.exit()
if mode == 'network':
    emit(type='result', ok=False, error={'code': 'network', 'message':'SECRET'}, **base); sys.exit()
if mode == 'oversized':
    print('x' * (1024 * 1024 + 10), flush=True); sys.exit()
if mode == 'device-confirm':
    emit(type='event', event='authState', state='awaitingDeviceConfirmation', sequence=1, **base)
if mode in ('device-code', 'email-code', 'wrong-attempt', 'reject-code'):
    event = dict(base)
    if mode == 'wrong-attempt': event['authAttemptId'] = 'stale'
    emit(type='event', event='authState', state='awaitingDeviceCode' if mode != 'email-code' else 'awaitingEmailCode', sequence=1, **event)
    code = json.loads(sys.stdin.readline())
    assert code['authAttemptId'] == attempt and code['accountEpoch'] == 1 and code['payload']['code'] == 'CODESECRET'
    emit(type='result', requestId=code['requestId'], ok=True, data={'accepted': mode != 'reject-code'})
if mode == 'qr':
    emit(type='event', event='authState', state='qrChallenge', sequence=1, challengeUrl='https://s.team/q/1/test', **base)
    emit(type='event', event='authState', state='qrChallenge', sequence=2, challengeUrl='https://s.team/q/1/refreshed', **base)
emit(type='result', ok=True, data={'state': 'online', 'steamId':'76561198000000000'},
     private={'refreshToken':'TOKEN_SECRET', 'accessToken':'ACCESS_SECRET', 'accountName':'PRIVATE_NAME'}, **base)
'''

class SteamAuthGateTests(unittest.TestCase):
    def run_case(self, scenario, mode='password', fails=False, prompts=0):
        with tempfile.TemporaryDirectory(prefix='mwx-auth-gate-test-') as directory:
            fixture = Path(directory) / 'fake.py'
            fixture.write_text(FAKE)
            output = []
            codes = []
            def code_input(prompt):
                codes.append(prompt)
                return 'CODESECRET'
            args = ([sys.executable, '-u', str(fixture), scenario], mode, 'PRIVATE_NAME', 'PASSWORD_SECRET')
            with contextlib.redirect_stdout(io.StringIO()) as captured:
                if fails:
                    with self.assertRaises(GateError):
                        run_gate(*args, timeout=.1 if scenario == 'deadline' else 3, emit=output.append, code_input=code_input)
                else:
                    run_gate(*args, timeout=3, emit=output.append, code_input=code_input)
            rendered = str(output) + captured.getvalue()
            for secret in ['TOKEN_SECRET', 'ACCESS_SECRET', 'PRIVATE_NAME', 'PASSWORD_SECRET', 'CODESECRET']:
                self.assertNotIn(secret, rendered)
            self.assertEqual(len(codes), prompts)
            return output

    def test_no_guard(self): self.run_case('immediate')
    def test_device_code_not_swallowed(self): self.run_case('device-code', prompts=1)
    def test_email_code(self): self.run_case('email-code', prompts=1)
    def test_confirmation_does_not_ask_code(self): self.run_case('device-confirm')
    def test_qr_refresh(self): self.assertEqual(sum('s.team' in x for x in self.run_case('qr', mode='qr')), 2)
    def test_wrong_password_exact_error(self): self.run_case('wrong', mode='wrong-password')
    def test_network_not_wrong_password_success(self): self.run_case('network', mode='wrong-password', fails=True)
    def test_online_not_wrong_password_success(self): self.run_case('immediate', mode='wrong-password', fails=True)
    def test_stale_attempt(self): self.run_case('wrong-attempt', fails=True)
    def test_guard_rejected(self): self.run_case('reject-code', fails=True, prompts=1)
    def test_bounded_frame(self): self.run_case('oversized', fails=True)
    def test_deadline(self):
        started = time.monotonic(); self.run_case('deadline', fails=True)
        self.assertLess(time.monotonic() - started, 3)

    def test_login_panel_exposes_keyboard_and_accessibility_actions(self):
        panel = LOGIN_PANEL.read_text()
        self.assertIn('loginButton.keyEquivalent = "\\r"', panel)
        self.assertIn('submit.keyEquivalent = "\\r"', panel)
        self.assertIn('window.makeFirstResponder(auth.isOnline ? usernameField : refreshQRButton)', panel)
        self.assertIn('self?.window?.makeFirstResponder(self?.usernameField)', panel)
        self.assertGreaterEqual(panel.count('window?.makeFirstResponder(codeField)'), 3)
        self.assertIn('private let zoomQRButton', panel)
        self.assertIn('zoomQRButton.action = #selector(showZoomWindow)', panel)
        self.assertIn('qrImageView.setAccessibilityLabel("Steam 登录二维码")', panel)
        self.assertIn('statusLabel.setAccessibilityRole(.staticText)', panel)
        self.assertIn('NSAccessibility.post(element: statusLabel, notification: .valueChanged)', panel)
