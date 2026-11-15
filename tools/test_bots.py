#!/usr/bin/env python3
"""Networked bot check: bot players on the PC dedicated server with a phone.

Starts tools/host_station.py in test mode with `--bots 3`, then:
  - the panel status lists the 3 bots (flagged "bot"), add_bot / remove_bot work
    in the lobby, and a round can't start with bots alone;
  - one headless bot-driver client (--bot=client, wrapped by
    tests/bots_net_client.gd to watch from the phone's side) joins: it sees the
    bots in its roster and gets a role;
  - the round is started from the control channel and reaches a result; the
    client saw the bot avatars move and never crashed;
  - after the result, the client leaves and the server is back in the lobby
    with its bots still listed.

Usage: python tools/test_bots.py [--godot PATH] [--project PATH]
"""
import argparse
import sys
import time
from pathlib import Path

from bootstrap_godot import ROOT, ensure_engine, validate_engine
from test_host_station import Failure, Panel, Proc, check, free_port, godot_errors, wait_game_port_free

ROUND_TIMEOUT = 420  # s of wall time for a whole round (bots, briefing, countdowns)


def run(engine, project):
    wait_game_port_free()
    port = free_port()
    launcher = Proc([sys.executable, str(ROOT / 'tools' / 'host_station.py'), '--test-mode', '--skip-import',
                     '--godot', str(engine), '--project', str(project), '--http-port', str(port),
                     '--room-name', 'Bot Station', '--auto-lobby', '0', '--bots', '3'], 'host_station')
    client = None
    try:
        launcher.wait_for('HOST_STATION_READY', 120)
        panel = Panel(port)
        server = panel.wait(lambda s: len(s['players']) == 3, 20, 'three bots in the lobby')
        check(all(p.get('bot') for p in server['players']), f'bots not flagged: {server["players"]}')
        check(len({p['name'] for p in server['players']}) == 3 and len({p['color'] for p in server['players']}) == 3,
              f'bots share a name or colour: {server["players"]}')
        reply = panel.command('start_round')
        check(not reply['ok'] and 'phone' in (reply.get('error') or ''), f'bots-only round was allowed: {reply}')
        reply = panel.command('add_bot', skill='hard')
        check(reply['ok'], f'add_bot: {reply}')
        server = panel.wait(lambda s: len(s['players']) == 4, 10, 'a fourth bot')
        check(any(p.get('skill') == 'hard' for p in server['players']), 'add_bot ignored the skill')
        reply = panel.command('remove_bot')
        check(reply['ok'], f'remove_bot: {reply}')
        server = panel.wait(lambda s: len(s['players']) == 3, 10, 'back to three bots')
        print('  3 bots in the lobby, add/remove bot and the bots-only guard ok', flush=True)

        client = Proc([str(engine), '--headless', '--path', str(project), '--script', 'res://tests/bots_net_client.gd',
                       '--', '--bot=client', '--bot-name=Phone', '--bot-join-delay=0.5', '--bot-plan=watch',
                       f'--bot-timeout={ROUND_TIMEOUT}'], 'client')
        server = panel.wait(lambda s: len(s['players']) == 4, 90, 'the phone to join')
        roster_line = client.wait_for('BOTS_ROSTER', 30)
        check(roster_line.split()[1] == '3', f'client roster: {roster_line}')
        reply = panel.command('start_round')
        check(reply['ok'], f'start_round: {reply}')
        role = client.wait_for('BOT_ROLE', 60)
        check(role.split()[1] in ('crew', 'infiltrator'), f'client role: {role}')
        server = panel.wait(lambda s: s['state'] == 'stabilise', 60, 'the briefing to end')
        check(all(p['state'] == 'ok' for p in server['players']), f'player states: {server["players"]}')
        server = panel.wait(lambda s: s['state'] == 'result', ROUND_TIMEOUT, 'the round to finish')
        result = server['round']['result']
        check(result['winner'] in ('crew', 'infiltrator'), f'no winner: {result}')
        moved = client.wait_for('BOTS_MOVED', 30)
        count, total = moved.split()[1].split('/')
        check(int(total) == 3 and int(count) >= 2, f'bot avatars barely moved on the phone: {moved}')
        check(client.wait_for('BOTS_NAN', 10) == 'BOTS_NAN 0', 'non-finite bot positions on the phone')
        check(client.wait_for('BOT_RESULT', 30).startswith('BOT_RESULT winner='), 'client saw no result')
        deadline = time.time() + 30
        while client.proc.poll() is None and time.time() < deadline:
            time.sleep(0.2)
        check(client.proc.returncode == 0, f'client exit code {client.proc.returncode}\n' + '\n'.join(client.lines[-40:]))
        errors = godot_errors(client.lines)
        check(not errors, 'client errors:\n' + '\n'.join(errors))
        print(f'  round with 1 phone + 3 bots: {result["winner"]} ({result["reason"]}); phone saw {moved.split()[1]} '
              f'bots move, role {role.split()[1]}', flush=True)
        # The phone left: back to the lobby with the bots still aboard (no bot-only rounds).
        reply = panel.command('back_to_lobby')
        server = panel.wait(lambda s: s['state'] == 'lobby' and len(s['players']) == 3, 30, 'the lobby with 3 bots')
        check(all(p.get('bot') for p in server['players']), 'bots gone after the round')
        # A restart (same launcher options) brings the bots back.
        code, _, _ = panel.request('POST', '/api/restart', {})
        check(code == 200, 'restart refused')
        time.sleep(1.0)
        panel.wait(lambda s: s['state'] == 'lobby' and len(s['players']) == 3 and all(p.get('bot') for p in s['players']),
                   60, 'the restarted server with its 3 bots')
        launcher.proc.terminate()  # SIGTERM: same path as Ctrl+C
        launcher.proc.wait(timeout=30)
        launcher.wait_for('HOST_STATION_STOPPED', 5)
        print('  back in the lobby with the bots; a restart brings them back', flush=True)
        errors = godot_errors(launcher.lines)
        check(not errors, 'server errors:\n' + '\n'.join(errors))
        bad = [line for line in launcher.lines if 'unknown peer' in line.lower() or 'invalid peer' in line.lower()]
        check(not bad, 'the server sent something to a bot id:\n' + '\n'.join(bad[:10]))
    finally:
        if client is not None:
            client.kill()
        launcher.kill()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--godot')
    parser.add_argument('--project', type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        engine, _ = validate_engine(args.godot or ensure_engine())
        run(engine, args.project.resolve())
    except Failure as exc:
        print(f'FAILED: {exc}')
        return 1
    print('BOT NETWORK CHECKS PASSED')
    return 0


if __name__ == '__main__':
    sys.exit(main())
