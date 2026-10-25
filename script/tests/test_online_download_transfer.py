"""Real OnlineLibrary selection/download delegates against owned loopback HTTP.

Only UI publications and autoplay delivery are recording leaves. The selected
variant, service transfer methods, URLSession delegate, HTTP and file moves run
from production. Application outputs/staging stay inside the isolated HOME;
URLSession retains its platform-owned temporary path until the delegate moves it.
"""
from __future__ import annotations

import collections
import hashlib
import http.server
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

from script.tests.test_steam_library_interactions import method
from script.tests.test_ui_request_schedulers import declaration

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'MyWallpaperX/Modules/OnlineLibrary/Core'
FIXTURE = ROOT / 'script/tests/fixtures/OnlineDownloadTransferHarness.swift'
PAYLOAD = bytes(range(256)) * 2048


@unittest.skipUnless(sys.platform == 'darwin', 'requires macOS URLSession')
class OnlineDownloadTransferTests(unittest.TestCase):
    def test_real_get_delegate_selection_progress_ownership_errors_and_cancellation(self):
        requests: list[tuple[str, str]] = []
        transfers: list[tuple[str, int, int]] = []
        cancellation_finished = threading.Event()
        request_lock = threading.Lock()

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.1'

            def log_message(self, *_):
                pass

            def do_HEAD(self):
                with request_lock:
                    requests.append(('HEAD', self.path))
                self.send_response(500)
                self.send_header('Content-Length', '0')
                self.end_headers()

            def do_GET(self):
                with request_lock:
                    requests.append(('GET', self.path))
                if self.path == '/redirect':
                    self.send_response(302)
                    self.send_header('Location', '/known')
                    self.send_header('Content-Length', '0')
                    self.end_headers()
                    return
                self.send_response(404 if self.path == '/error' else 200)
                self.send_header('Content-Type', 'video/mp4')
                body = PAYLOAD * 8 if self.path == '/cancel' else PAYLOAD
                if self.path != '/unknown':
                    self.send_header('Content-Length', str(len(body) + (4096 if self.path == '/disconnect' else 0)))
                self.send_header('Connection', 'close')
                self.end_headers()
                sent = 0
                try:
                    if self.path == '/disconnect':
                        self.wfile.write(PAYLOAD[:1024])
                        self.wfile.flush()
                        sent = 1024
                        self.connection.shutdown(socket.SHUT_RDWR)
                        return
                    for index in range(0, len(body), 16384):
                        block = body[index:index + 16384]
                        self.wfile.write(block)
                        self.wfile.flush()
                        sent += len(block)
                        time.sleep(0.02 if self.path == '/cancel' else 0.003)
                except (BrokenPipeError, ConnectionResetError, OSError):
                    pass
                finally:
                    self.close_connection = True
                    with request_lock:
                        transfers.append((self.path, sent, len(body)))
                    if self.path == '/cancel':
                        cancellation_finished.set()

        service_path = CORE / 'OnlineLibraryService.swift'
        model_path = CORE / 'OnlineLibraryModels.swift'
        service = service_path.read_text()
        delegate = declaration(service, 'nonisolated private final class OLDownloadTaskDelegate:')
        move = '            try FileManager.default.moveItem(at: location, to: stagingURL)'
        self.assertEqual(delegate.count(move), 1)
        delegate = delegate.replace(move,
            '            let identity = TransferProbe.identity(location)\n' + move
            + '\n            TransferProbe.shared.moved(from: location, to: stagingURL, identity: identity)')
        methods = '\n'.join(method(service, signature) for signature in [
            '    func download(item:', '    func downloadAndSet(item:',
            '    private func postReadyToPlay(', '    private func startDownload(',
            '    private func fetchAndMove(', '    private func downloadFile(',
            '    static var downloadDirectory:',
        ])
        adoption = 'rename(tmp.path, dest.path)'
        self.assertEqual(methods.count(adoption), 1)
        methods = methods.replace(adoption, 'TransferProbe.shared.renameStaged(tmp, to: dest)')
        source = FIXTURE.read_text().replace('// DOWNLOAD_DELEGATE', delegate).replace('// SERVICE_METHODS', methods)
        with tempfile.TemporaryDirectory(prefix='mwx-online-transfer-',
                dir=os.environ.get('MWX_ONLINE_DOWNLOAD_WORK_ROOT', '/private/tmp')) as raw:
            work = Path(raw)
            for name in ['home', 'tmp']:
                (work / name).mkdir()
            environment = dict(os.environ, HOME=str(work / 'home'), CFFIXED_USER_HOME=str(work / 'home'),
                               TMPDIR=str(work / 'tmp') + '/')
            harness = work / 'Harness.swift'; harness.write_text(source)
            inputs = [service_path, model_path, FIXTURE, Path(__file__)]
            identities = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
            command = ['xcrun', 'swiftc', '-swift-version', '5', '-default-isolation', 'MainActor',
                       '-parse-as-library', str(model_path), str(harness),
                       '-module-cache-path', str(work / 'modules'), '-o', str(work / 'transfer')]
            compiled = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=150)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            try:
                completed = subprocess.run([str(work / 'transfer'),
                    f'http://127.0.0.1:{server.server_port}', str(work / 'home')],
                    env=environment, capture_output=True, text=True, timeout=45)
            finally:
                server.shutdown(); server.server_close(); thread.join(timeout=5)
            cancellation_observed = cancellation_finished.wait(timeout=2) if completed.returncode == 0 else False
            proof = os.environ.get('MWX_ONLINE_DOWNLOAD_PROOF_DIR')
            if proof:
                saved = Path(proof); saved.mkdir(parents=True, exist_ok=True)
                (saved / 'inputs.json').write_text(json.dumps({'inputs': identities, 'command': command,
                    'boundary': __doc__, 'transforms': ['observe inode around the actual delegate move',
                        'one final adoption temporarily removes owned-parent write permission around actual Darwin.rename']}, indent=2))
                (saved / 'compile.log').write_text(compiled.stdout + compiled.stderr)
                (saved / 'runtime.log').write_text(completed.stdout + completed.stderr)
                (saved / 'http.json').write_text(json.dumps(requests, indent=2))
                (saved / 'transfers.json').write_text(json.dumps(transfers, indent=2))
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertTrue(cancellation_observed, 'cancellation request did not finish at the server')
            self.assertIn('online-download-transfer-pass', completed.stdout)
            counts = collections.Counter(requests)
            self.assertFalse(any(verb == 'HEAD' for verb, _ in requests), requests)
            for path in ['/known', '/redirect', '/unknown', '/error', '/disconnect', '/cancel']:
                self.assertGreater(counts['GET', path], 0, (path, requests))
            self.assertTrue(any(path == '/cancel' and 0 < sent < total for path, sent, total in transfers),
                ('Task.cancel must stop the actual GET before its complete body', transfers))
            self.assertEqual(identities, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})


if __name__ == '__main__':
    unittest.main()
