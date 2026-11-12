#!/usr/bin/env python3
"""NET-002: real Godot motion, replicas and explicit application-level impairment."""
import argparse
import json
import math
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from bootstrap_godot import ROOT, ensure_engine, validate_engine
from test_network_lab import Lab, wait_for
from validate_project import source_id


def write_control(process, value):
    temporary = process.control_path.with_suffix('.pending')
    temporary.write_text(json.dumps(value))
    temporary.replace(process.control_path)


def pose(event, identity):
    return next(x for x in event['players'] if x['id'] == identity)


def latest(process, kind):
    entries = [x for x in process.events() if x.get('event') == kind]
    return entries[-1] if entries else None


def percentile(values, proportion):
    ordered = sorted(values)
    return round(ordered[int((len(ordered) - 1) * proportion)], 3) if ordered else None


class MovementLab(Lab):
    def server(self, name, rtt=0, loss=0):
        result = super().server(name, script='movement_server.gd', extra=['--rtt-ms', str(rtt), '--loss-percent', str(loss), '--seed', '20261112'])
        wait_for(lambda: result['process'].event('motion_ready'), timeout=25)
        return result

    def driven(self, server, identity, issuance=0, control=None):
        path = self.temporary / ('drive-%d.json' % self.counter)
        path.write_text(json.dumps(control or {'axis': [0, 0]}))
        result = super().client(server, self.credential(server, identity, issuance), hold=55, script='movement_client.gd', extra=['--control-file', str(path)])
        result.control_path = path
        wait_for(lambda: result.event('view_sample'), timeout=25)
        return result

    def sample(self, server):
        return wait_for(lambda: latest(server['process'], 'motion_sample'))

    def wait_pose(self, server, identity, predicate):
        def available():
            event = self.sample(server)
            selected = next((x for x in event['players'] if x['id'] == identity), None)
            return selected if selected and predicate(selected) else None
        return wait_for(available)


def exercise(lab, report):
    def check(name, operation):
        print(name + '...', flush=True)
        try:
            operation()
        except Exception:
            report['checks'].append({'name': name, 'passed': False})
            raise
        report['checks'].append({'name': name, 'passed': True})

    server = lab.server('movement-main')
    first = lab.driven(server, 'player-1')
    second = lab.driven(server, 'player-2')

    def replicas():
        for client in (first, second):
            wait_for(lambda: len(latest(client, 'view_sample')['players']) == 2)
            view = latest(client, 'view_sample')
            authoritative = wait_for(lambda: server['process'].event('motion_sample', tick=view['tick']))
            assert view['players'] == authoritative['players']
            assert set(view['visible']) == {'player-1', 'player-2'}
    check('two-clients-receive-authoritative-replicas', replicas)
    check('server-floor-contact', lambda: lab.wait_pose(server, 'player-1', lambda x: abs(x['p'][1] - 0.9) < 0.04))

    start = pose(lab.sample(server), 'player-1')['p']
    write_control(first, {'axis': [1, 0]})
    check('directional-intent-moves-only-owned-body', lambda: (
        lab.wait_pose(server, 'player-1', lambda x: x['p'][0] > start[0] + 2),
        assert_true(abs(pose(lab.sample(server), 'player-2')['p'][0]) < 0.01)))
    write_control(first, {'axis': [0, 0]})
    check('release-stops-authoritative-motion', lambda: lab.wait_pose(server, 'player-1', lambda x: abs(x['v'][0]) < 0.01))

    write_control(second, {'axis': [0, -1]})
    check('central-obstacle-blocks-motion', lambda: lab.wait_pose(server, 'player-2', lambda x: 1.3 < x['p'][2] < 1.45 and abs(x['v'][2]) < 0.01))
    write_control(second, {'axis': [0, 0]})

    def invalid(name, packet, reason):
        # Some reasons were already observed: inspect the cumulative count instead.
        before = lab.sample(server)['rejections'].get(reason, 0)
        write_control(first, {'axis': [0, 0], 'injection_id': name, 'raw_input': packet})
        wait_for(lambda: lab.sample(server)['rejections'].get(reason, 0) > before)
        assert all(abs(value) < 20 for entry in lab.sample(server)['players'] for value in entry['p'])
        assert pose(lab.sample(server), 'player-2')['p'][2] > 1.3

    base = {'kind': 'input', 'seq': 500, 'move_x': 0, 'move_z': 0, 'sprint': False}
    for name, edits, reason in [
        ('client-position-claim', {'position': [99, 4, 99]}, 'input_shape'),
        ('other-actor-claim', {'player_id': 'player-2'}, 'input_shape'),
        ('client-delta-claim', {'dt': 50}, 'input_shape'),
        ('axis-out-of-range', {'move_x': 2}, 'input_axis'),
        ('axis-wrong-type', {'move_x': 'fast'}, 'input_axis'),
        ('sprint-wrong-type', {'sprint': 1}, 'input_sprint'),
        ('sequence-replay', {'seq': 1}, 'stale_sequence'),
        ('sequence-jump', {'seq': 1000000}, 'sequence_jump'),
        ('wrong-epoch', {'room_epoch': 'previous-room'}, 'input_epoch'),
    ]:
        packet = {**base, **edits}
        check(name, lambda n=name, p=packet, r=reason: invalid(n, p, r))

    def stale_input():
        write_control(first, {'axis': [1, 0]})
        lab.wait_pose(server, 'player-1', lambda x: x['v'][0] > 3.5)
        start_x = pose(lab.sample(server), 'player-1')['p'][0]
        write_control(first, {'axis': [1, 0], 'suspend_input': True})
        lab.wait_pose(server, 'player-1', lambda x: abs(x['v'][0]) < 0.01)
        end_x = pose(lab.sample(server), 'player-1')['p'][0]
        assert 0 <= end_x - start_x < 1.8
    check('missing-input-times-out-with-bounded-coast', stale_input)

    write_control(first, {'axis': [1, 0]})
    lab.wait_pose(server, 'player-1', lambda x: x['v'][0] > 3.5)
    write_control(first, {'axis': [1, 0], 'focused': False})
    check('focus-policy-clears-movement-intent', lambda: lab.wait_pose(server, 'player-1', lambda x: abs(x['v'][0]) < 0.01))

    def local_tamper():
        write_control(first, {'axis': [0, 0], 'teleport_id': 'local-only'})
        wait_for(lambda: first.event('prediction_corrected'))
        wait_for(lambda: max(abs(x) for x in latest(first, 'view_sample')['local_p']) < 20)
        assert max(abs(x) for x in pose(lab.sample(server), 'player-1')['p']) < 20
    check('local-teleport-is-corrected-not-replicated', local_tamper)

    def flood():
        write_control(first, {'axis': [1, 1], 'sprint': True, 'injection_id': 'flood', 'burst': 180})
        wait_for(lambda: lab.sample(server)['rejections'].get('rate_limit', 0) > 0)
        for event in server['process'].events():
            if event.get('event') != 'motion_sample':
                continue
            for entry in event['players']:
                assert math.hypot(entry['v'][0], entry['v'][2]) <= 6.01
    check('flood-and-diagonal-input-cannot-increase-speed', flood)
    write_control(first, {'axis': [0, 0]})

    def removal():
        lab.leave(server, first)
        wait_for(lambda: set(latest(second, 'view_sample')['visible']) == {'player-2'})
        assert len(lab.sample(server)['players']) == 1
    check('disconnect-removes-remote-avatar', removal)
    returning = lab.driven(server, 'player-1', 1)
    check('fresh-admission-has-one-avatar', lambda: wait_for(lambda: set(latest(second, 'view_sample')['visible']) == {'player-1', 'player-2'}))
    lab.leave(server, returning)
    lab.leave(server, second)
    lab.stop(server)

    for rtt in (50, 100, 200):
        for loss in (0, 1, 3):
            def profile(rtt=rtt, loss=loss):
                current = lab.server('profile-%d-%d' % (rtt, loss), rtt=rtt, loss=loss)
                walker = lab.driven(current, 'player-1', control={'axis': [1, 0]})
                observer = lab.driven(current, 'player-2')
                start_tick = lab.sample(current)['tick']
                wait_for(lambda: lab.sample(current)['tick'] >= start_tick + 60)
                lab.wait_pose(current, 'player-1', lambda x: x['p'][0] > -3)
                sample = latest(walker, 'view_sample')
                assert sample and sample['snapshot_count'] >= 12
                assert len(sample['acknowledgement_ms']) >= 5
                assert len(latest(observer, 'view_sample')['visible']) == 2
                assert all(abs(value) < 20 for item in lab.sample(current)['players'] for value in item['p'])
                stats = lab.sample(current)['counters']
                assert stats['queue_peak'] <= 512
                report['profiles'].append({'requested_simulated_rtt_ms': rtt, 'requested_motion_loss_percent': loss,
                    'ack_samples': len(sample['acknowledgement_ms']), 'input_to_snapshot_p95_ms': percentile(sample['acknowledgement_ms'], 0.95),
                    'prediction_error_p95_m': percentile(sample['prediction_error_m'], 0.95), 'counters': stats,
                    'method': 'server application queues add half target delay to each motion direction and seeded drops; auth/control remain ordinary loopback'})
                lab.leave(current, walker)
                lab.leave(current, observer)
                lab.stop(current)
            check('simulated-motion-rtt-%d-loss-%d' % (rtt, loss), profile)

    def logs():
        text = '\n'.join(process.path.read_text() for process in lab.processes)
        assert 'ERROR:' not in text and all(token not in text for token in lab.tokens)
    check('no-engine-errors-or-credential-leaks', logs)


def assert_true(value):
    assert value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--output', type=Path, default=ROOT / 'builds' / 'movement-lab')
    args = parser.parse_args()
    if not __debug__:
        parser.error('Run without Python -O')
    output = args.output.resolve()
    if output == ROOT or (ROOT in output.parents and output.relative_to(ROOT).parts[0] != 'builds'):
        parser.error('Output inside the repository must be under builds/')
    output.mkdir(parents=True, exist_ok=True)
    report = {'status': 'failed', 'source_id': source_id(ROOT), 'checks': [], 'profiles': [],
              'scope': 'Godot motion/replica processes on loopback; application-level simulated motion-message delay/loss, not OS transport or phone tests'}
    try:
        engine, report['engine'] = validate_engine(args.godot or ensure_engine())
        with tempfile.TemporaryDirectory(prefix='maldiven-motion-') as directory:
            temporary = Path(directory)
            project = temporary / 'project'
            shutil.copytree(ROOT / 'experiments' / 'net-lab', project, ignore=shutil.ignore_patterns('.godot'))
            lab = MovementLab(engine, project, temporary, output)
            try:
                exercise(lab, report)
                report['status'] = 'passed'
            finally:
                lab.close()
    except Exception as exc:
        report['error'] = str(exc)
        print('FAILED: ' + str(exc), flush=True)
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Report: ' + str(output / 'report.json'))
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
