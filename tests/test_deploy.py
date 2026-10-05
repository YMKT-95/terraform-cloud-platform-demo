"""Fault-injection tests for the deployment's cutover and recovery behavior."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
REVISION = '1' * 40
IMAGE = 'ghcr.io/ymkt-95/terraform-cloud-platform-demo@sha256:' + 'a' * 64
FAKE = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
path = Path(os.environ['FAKE_STATE'])
state = json.loads(path.read_text())
args = sys.argv[1:]
name = Path(sys.argv[0]).name
app, candidate = 'terraform-demo-app', 'terraform-demo-candidate'
scenario = os.environ['SCENARIO']
if name == 'docker':
    op = args[0]
    if op == 'pull': pass
    elif op == 'rm': state.pop(args[-1], None)
    elif op == 'run':
        container = args[args.index('--name') + 1]
        state[container] = {'image': args[-1], 'running': True}
    elif op == 'port': print('127.0.0.1:34567')
    elif op == 'inspect':
        if args[-1] not in state: sys.exit(1)
    elif op == 'stop': state[args[-1]]['running'] = False
    elif op == 'start': state[args[-1]]['running'] = True
    elif op == 'rename': state[args[2]] = state.pop(args[1])
    elif op == 'logs': pass
    else: raise RuntimeError(args)
    path.write_text(json.dumps(state))
elif name == 'curl':
    url = args[-1]
    if (scenario == 'candidate_failure' and ':34567' in url) or (scenario == 'cutover_failure' and ':34567' not in url): sys.exit(22)
    print(json.dumps({'status': 'healthy'} if url.endswith('/health') else {'revision': '1' * 40}, separators=(',', ':')))
elif name == 'timeout': os.execvp(args[1], args[1:])
'''


class DeploymentRecovery(unittest.TestCase):
    def run_scenario(self, scenario, image=IMAGE):
        with tempfile.TemporaryDirectory() as directory:
            tmp = Path(directory)
            state = tmp / 'state.json'
            state.write_text(json.dumps({'terraform-demo-app': {'image': 'old-image', 'running': True}}))
            for command in ('docker', 'curl', 'timeout', 'flock', 'sleep'):
                executable = tmp / command
                executable.write_text(FAKE)
                executable.chmod(0o755)
            script = (ROOT / 'scripts/deploy-on-instance.sh').read_text().replace('/var/lock/terraform-demo-deploy.lock', str(tmp / 'lock'))
            env = dict(os.environ, PATH=f'{tmp}:{os.environ["PATH"]}', FAKE_STATE=str(state), SCENARIO=scenario)
            result = subprocess.run(['bash', '-s', '--', image, REVISION], input=script, env=env, text=True, capture_output=True)
            return result, json.loads(state.read_text())

    def test_success_preserves_previous(self):
        result, state = self.run_scenario('success')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state['terraform-demo-app'], {'image': IMAGE, 'running': True})
        self.assertEqual(state['terraform-demo-previous'], {'image': 'old-image', 'running': False})
        self.assertNotIn('terraform-demo-candidate', state)

    def test_candidate_failure_leaves_service_running(self):
        result, state = self.run_scenario('candidate_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state, {'terraform-demo-app': {'image': 'old-image', 'running': True}})

    def test_failed_cutover_restores_old_service(self):
        result, state = self.run_scenario('cutover_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state, {'terraform-demo-app': {'image': 'old-image', 'running': True}})
        self.assertIn('Restored previous container', result.stderr)

    def test_mutable_image_rejected_before_changes(self):
        result, state = self.run_scenario('success', 'ghcr.io/ymkt-95/terraform-cloud-platform-demo:latest')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state, {'terraform-demo-app': {'image': 'old-image', 'running': True}})


if __name__ == '__main__':
    unittest.main()
