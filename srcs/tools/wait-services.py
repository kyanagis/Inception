#!/usr/bin/env python3
"""Wait for the existing containers without reconciling their configuration."""
import argparse
import json
import re
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected', type=int, required=True)
    parser.add_argument('--timeout', type=float, default=180)
    parser.add_argument('containers', nargs='*')
    args = parser.parse_args()
    if not 0 < args.timeout <= 180 or not 1 <= args.expected <= 8:
        parser.error('Expected 1–8 containers and a timeout between 0 and 180 seconds')
    if (len(set(args.containers)) != args.expected or
            len(args.containers) != args.expected or
            any(not re.fullmatch('[0-9a-f]{64}', value) for value in args.containers)):
        parser.error('A required service container is missing or ambiguous')
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        try:
            result = subprocess.run(
                ['docker', '--host', 'unix:///var/run/docker.sock', 'inspect', *args.containers],
                capture_output=True, text=True,
                timeout=max(0.01, min(10, deadline - time.monotonic())))
            if result.returncode:
                print('A required service container could not be inspected', file=sys.stderr)
                return 1
            states = json.loads(result.stdout)
            if len(states) == args.expected and all(
                    item['State']['Running'] and
                    item['State'].get('Health', {}).get('Status', 'healthy') == 'healthy'
                    for item in states):
                print(f'All {args.expected} service containers are ready.')
                return 0
        except (subprocess.TimeoutExpired, json.JSONDecodeError, KeyError):
            print('Could not determine service readiness', file=sys.stderr)
            return 1
        time.sleep(min(1, max(0, deadline - time.monotonic())))
    print('Service readiness timed out', file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main())
