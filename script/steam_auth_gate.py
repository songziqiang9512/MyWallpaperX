#!/usr/bin/env python3.12
"""Explicit real-account gate. Protocol frames and credentials are never logged or persisted."""
from __future__ import annotations

import argparse
import getpass
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import time
from urllib.parse import urlparse
import uuid

MAX_FRAME = 1024 * 1024

class GateError(Exception):
    pass

class Helper:
    def __init__(self, command, deadline):
        self.deadline = deadline
        # Deliberately suppress raw helper diagnostics too: neither channel is a safe account log.
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.buffer = bytearray()
        os.set_blocking(self.process.stdin.fileno(), False)
        self.write_selector = selectors.DefaultSelector()
        self.write_selector.register(self.process.stdin, selectors.EVENT_WRITE)

    def send(self, request):
        data = (json.dumps(request, ensure_ascii=False) + '\n').encode()
        if len(data) > MAX_FRAME:
            raise GateError('request too large')
        while data:
            remaining = self.deadline - time.monotonic()
            if remaining <= 0 or not self.write_selector.select(remaining):
                raise GateError('helper input deadline exceeded')
            try:
                count = os.write(self.process.stdin.fileno(), data)
                data = data[count:]
            except BlockingIOError:
                continue

    def receive(self):
        while True:
            if time.monotonic() >= self.deadline:
                raise GateError('authentication deadline exceeded')
            end = self.buffer.find(b'\n')
            if end >= 0:
                if end > MAX_FRAME:
                    raise GateError('helper frame too large')
                data = bytes(self.buffer[:end]); del self.buffer[:end + 1]
                try:
                    frame = json.loads(data)
                except (ValueError, UnicodeDecodeError):
                    raise GateError('invalid helper frame') from None
                if not isinstance(frame, dict) or type(frame.get('v')) is not int or frame.get('v') != 1:
                    raise GateError('invalid helper envelope')
                return frame
            if len(self.buffer) > MAX_FRAME:
                raise GateError('helper frame too large')
            if not self.selector.select(max(0, self.deadline - time.monotonic())):
                raise GateError('authentication deadline exceeded')
            data = os.read(self.process.stdout.fileno(), 65536)
            if not data:
                raise GateError('helper exited without authentication terminal')
            self.buffer.extend(data)

    def close(self):
        # Closing stdin plus bounded process termination cannot block on a full input pipe.
        self.selector.close()
        self.write_selector.close()
        try:
            self.process.stdin.close()
        except OSError:
            pass
        try:
            self.process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try:
                self.process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                self.process.kill(); self.process.wait(timeout=1)
        self.process.stdout.close()


def run_gate(command, mode, username='', secret='', *, timeout=180, code_input=None, emit=print):
    deadline = time.monotonic() + timeout
    helper = Helper(command, deadline)
    attempt = 'gate-' + uuid.uuid4().hex
    request_id = 'gate-login'
    epoch = 1
    code_count = 0
    sequence = 0
    try:
        ready = helper.receive()
        if ready.get('type') != 'ready' or ready.get('protocol') != 1 or type(ready.get('processEpoch')) is not int:
            raise GateError('helper handshake mismatch')
        process_epoch = ready['processEpoch']
        request = dict(v=1, type='request', requestId=request_id, accountEpoch=epoch, authAttemptId=attempt)
        if mode in ('password', 'wrong-password'):
            request.update(command='loginPassword', payload={'username': username}, private={'password': secret})
        elif mode == 'restore':
            request.update(command='restoreSession', payload={'accountName': username}, private={'refreshToken': secret})
        elif mode == 'qr':
            request.update(command='loginQR')
        else:
            raise GateError('unsupported mode')
        helper.send(request)
        request.clear(); secret = ''
        while True:
            frame = helper.receive()
            if not isinstance(frame.get('requestId', ''), str):
                raise GateError('invalid request identity')
            for key in ('data', 'private', 'error'):
                if frame.get(key) is not None and not isinstance(frame[key], dict):
                    raise GateError('invalid result object')
            if frame.get('processEpoch') != process_epoch:
                raise GateError('helper generation changed')
            if frame.get('requestId', '').startswith('gate-code-'):
                if frame.get('ok') is not True or (frame.get('data') or {}).get('accepted') is not True:
                    raise GateError('Guard code was not accepted')
                continue
            if frame.get('requestId') != request_id:
                continue
            if frame.get('accountEpoch') != epoch:
                raise GateError('account epoch mismatch')
            if frame.get('type') == 'result':
                if mode == 'wrong-password':
                    if frame.get('ok') is not False or (frame.get('error') or {}).get('code') != 'accessDenied':
                        raise GateError('expected one accessDenied terminal for wrong password')
                    emit('PASS: wrong password rejected (accessDenied)')
                    return
                if frame.get('ok') is not True:
                    code = (frame.get('error') or {}).get('code')
                    allowed = {'network', 'rateLimited', 'authExpired', 'invalidChallenge', 'accessDenied', 'cancelled'}
                    raise GateError('authentication failed: ' + (code if code in allowed else 'invalid terminal'))
                data = frame.get('data') or {}
                private = frame.get('private') or {}
                steam_id = data.get('steamId', '')
                if (frame.get('authAttemptId') != attempt or data.get('state') != 'online'
                        or not isinstance(steam_id, str) or not steam_id.isascii() or not steam_id.isdecimal()
                        or not 0 < int(steam_id) <= 2**64 - 1 or not isinstance(private.get('refreshToken'), str)
                        or not private['refreshToken']):
                    raise GateError('online terminal incomplete')
                emit('PASS: authenticated online; private credentials suppressed')
                return
            if frame.get('type') != 'event' or frame.get('event') != 'authState':
                continue
            if frame.get('authAttemptId') != attempt:
                raise GateError('authentication attempt mismatch')
            current = frame.get('sequence')
            if type(current) is not int or current <= sequence:
                raise GateError('authentication event out of order')
            sequence = current
            state = frame.get('state')
            if state in ('awaitingEmailCode', 'awaitingDeviceCode'):
                if mode == 'wrong-password':
                    raise GateError('wrong-password gate unexpectedly reached Guard')
                if code_input is None or code_count >= 5:
                    raise GateError('Guard input unavailable or retry limit exceeded')
                emit('Guard: ' + state)
                code = code_input('Steam Guard code (hidden): ')
                if time.monotonic() >= deadline:
                    raise GateError('authentication deadline exceeded')
                code_count += 1
                helper.send(dict(v=1, type='request', requestId=f'gate-code-{code_count}', command='submitChallenge',
                                 accountEpoch=epoch, authAttemptId=attempt, payload={'code': code}))
                code = ''
            elif state == 'qrChallenge':
                url = frame.get('challengeUrl', '')
                parsed = urlparse(url) if isinstance(url, str) else None
                if not parsed or parsed.scheme != 'https' or parsed.hostname != 's.team' or parsed.username or not parsed.path.startswith('/q/') or any(ord(c) < 32 for c in url):
                    raise GateError('invalid QR challenge URL')
                # The expiring challenge is intentional interactive output, never the token/frame.
                emit('Scan with Steam (expiring challenge): ' + url)
            elif state == 'awaitingDeviceConfirmation':
                emit('Confirm this login in the Steam mobile app; no code input needed')
            elif state in ('connecting', 'authenticating', 'loggingOn', 'polling', 'online'):
                emit('Steam: ' + state)
    finally:
        helper.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['password', 'qr', 'wrong-password', 'restore'])
    parser.add_argument('username', nargs='?')
    parser.add_argument('token_file', nargs='?')
    parser.add_argument('--timeout', type=float, default=180)
    args = parser.parse_args(argv)
    if not 1 <= args.timeout <= 600:
        parser.error('--timeout must be between 1 and 600 seconds')
    path = os.environ.get('STEAM_HELPER', str(Path(__file__).resolve().parents[1] / 'SteamService/bin/publish/SteamService'))
    if not Path(path).is_file() or not os.access(path, os.X_OK):
        parser.error('helper missing; build it or set STEAM_HELPER')
    def alarm(_signal, _frame):
        raise GateError('authentication deadline exceeded')
    old_handler = signal.signal(signal.SIGALRM, alarm)
    signal.setitimer(signal.ITIMER_REAL, args.timeout)
    started = time.monotonic()
    try:
        username = args.username or (input('Steam username: ') if args.mode != 'qr' else '')
        secret = ''
        if args.mode == 'password':
            secret = getpass.getpass('Steam password: ')
        elif args.mode == 'wrong-password':
            secret = 'incorrect-' + uuid.uuid4().hex
        elif args.mode == 'restore':
            if not args.token_file:
                parser.error('restore requires username and token_file')
            with open(args.token_file, 'r', encoding='utf-8') as handle:
                secret = handle.read(MAX_FRAME + 1).strip()
            if not secret or len(secret.encode()) > MAX_FRAME:
                raise GateError('token file empty or oversized')
        run_gate([path], args.mode, username, secret, timeout=max(0, args.timeout - (time.monotonic() - started)),
                 code_input=getpass.getpass)
        return 0
    except (GateError, OSError, EOFError, KeyboardInterrupt):
        # Do not print arbitrary exception messages that could contain credentials or private paths.
        print('FAIL: authentication gate did not pass; credentials and raw diagnostics suppressed')
        return 1
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, old_handler)

if __name__ == '__main__':
    raise SystemExit(main())
