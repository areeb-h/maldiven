#!/usr/bin/env python3
"""Check remote-invite boundaries without requiring a live tunnel or paid account."""
import base64
import html
import json
import re
import socket
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from run_friends_server import public_endpoint, write_invites


class PublicInvites(unittest.TestCase):
    def test_hostname_is_resolved_to_ipv4_for_existing_apk(self):
        with patch('socket.getaddrinfo', return_value=[(socket.AF_INET, socket.SOCK_DGRAM, 17, '', ('8.8.8.8', 32100))]) as resolve:
            self.assertEqual(public_endpoint('crew.gl.ply.gg:32100'), ('8.8.8.8', 32100))
            resolve.assert_called_once_with('crew.gl.ply.gg', 32100, socket.AF_INET, socket.SOCK_DGRAM)

    def test_non_public_or_invalid_endpoints_are_rejected(self):
        for value in ['https://crew.gl.ply.gg:32100', 'crew.gl.ply.gg:32100/path', 'crew.gl.ply.gg', 'crew.gl.ply.gg:0', 'crew.gl.ply.gg:65536', 'crew.gl.ply.gg:not-a-port', '[::1]:32100']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                public_endpoint(value)
        for address in ['127.0.0.1', '192.168.1.20', '100.64.0.1', '0.0.0.0', '224.0.0.1', '203.0.113.1']:
            with self.subTest(address=address), self.assertRaises(ValueError):
                public_endpoint(address + ':32100')

    def test_dns_failure_has_actionable_error(self):
        with patch('socket.getaddrinfo', side_effect=socket.gaierror('unavailable')):
            with self.assertRaisesRegex(ValueError, 'Cannot resolve'):
                public_endpoint('crew.gl.ply.gg:32100')

    def test_remote_invite_preserves_credentials_and_wire_shape(self):
        credential = {'player_id': 'player-1', 'issuance': 0, 'join': {'ticket': 'synthetic-test-only'}}
        with tempfile.TemporaryDirectory() as name:
            path = Path(name) / 'invites.html'
            write_invites(path, '8.8.8.8', 32100, 'synthetic-public-certificate', [credential], remote=True)
            page = path.read_text(encoding='utf-8')
            encoded = html.unescape(re.search(r'<textarea[^>]*>([^<]+)</textarea>', page).group(1))
            payload = json.loads(base64.b64decode(encoded.removeprefix('MDV1.')))
            self.assertEqual(payload, {'host': '8.8.8.8', 'port': 32100, 'certificate': 'synthetic-public-certificate', 'credential': credential})
            self.assertIn('Phones can use another network', page)
            self.assertNotIn('use the same Wi-Fi', page)


if __name__ == '__main__':
    unittest.main(verbosity=2)
