#!/usr/bin/env python3
"""Submit one bounded SSM deployment and wait for its actual exit status."""
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


def aws(*args):
    return subprocess.run(["aws", "ssm", *args, "--output", "json"], text=True, capture_output=True)


def main():
    image, revision, instance = (os.environ[key] for key in ("IMAGE_REF", "SOURCE_REVISION", "INSTANCE_ID"))
    if not re.fullmatch(r"ghcr\.io/ymkt-95/terraform-cloud-platform-demo@sha256:[a-f0-9]{64}", image):
        raise ValueError("Invalid immutable image reference")
    if not re.fullmatch(r"[a-f0-9]{40}", revision) or not re.fullmatch(r"i-[a-f0-9]{17}", instance):
        raise ValueError("Invalid revision or instance ID")
    script = base64.b64encode(Path("scripts/deploy-on-instance.sh").read_bytes()).decode()
    # All substituted values are validated hex/IDs or base64, not raw shell input.
    command = f"printf '%s' '{script}' | base64 -d | bash -s -- '{image}' '{revision}'"
    result = aws("send-command", "--instance-ids", instance, "--document-name", "AWS-RunShellScript",
                 "--timeout-seconds", "120", "--comment", f"GitHub deployment {revision[:12]}",
                 "--parameters", json.dumps({"commands": [command], "executionTimeout": ["900"]}))
    if result.returncode:
        raise RuntimeError(result.stderr)
    command_id = json.loads(result.stdout)["Command"]["CommandId"]
    print(f"SSM deployment command: {command_id}", flush=True)
    # A command can finish after the runner disappears; the host-side lock prevents overlaps.
    for _ in range(216):
        result = aws("get-command-invocation", "--command-id", command_id, "--instance-id", instance)
        if result.returncode:
            if "InvocationDoesNotExist" not in result.stderr:
                raise RuntimeError(result.stderr)
        else:
            invocation = json.loads(result.stdout)
            status = invocation["Status"]
            if status not in ("Pending", "InProgress", "Delayed", "Cancelling"):
                print(invocation.get("StandardOutputContent", ""))
                print(invocation.get("StandardErrorContent", ""), file=sys.stderr)
                if status != "Success" or invocation.get("ResponseCode") != 0:
                    raise RuntimeError(f"Deployment failed: {status}")
                return
        time.sleep(5)
    raise TimeoutError(f"SSM command {command_id} is still unresolved; inspect it before redeploying")


if __name__ == "__main__":
    main()
