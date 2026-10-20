#!/usr/bin/env python3
"""Verify lifecycle readiness on this stack; restore mandatory mode on completion."""
import hashlib
import json
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parents[2]
DOCKER = ['docker', '--host', 'unix:///var/run/docker.sock']
COMPOSE = DOCKER + ['compose', '--env-file', 'srcs/.env', '-f', 'srcs/docker-compose.yml']
MANDATORY = {'mariadb', 'wordpress', 'nginx'}
BONUS = MANDATORY | {'redis', 'ftp', 'static-site', 'adminer', 'backup'}


def command(args, timeout=240, check=True):
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    if check and result.returncode:
        # Preserve confidentiality of secret-bearing commands and Docker output.
        raise RuntimeError('Lifecycle operation failed (exit %d): %s' %
                           (result.returncode, args[0]))
    return result


def sanitize_diagnostics(value):
    """Keep useful CI errors while removing credentials and private key material."""
    value = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', value)
    value = re.sub(r'-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(?:-----END [A-Z ]*PRIVATE KEY-----|\Z)',
                   '[REDACTED PRIVATE KEY]', value, flags=re.DOTALL)
    value = re.sub(r'(?i)\b[0-9a-f]{64,}\b', '[REDACTED HEX VALUE]', value)
    # Replace the actual generated secrets too, covering future non-hex formats.
    for path in (ROOT / 'secrets').glob('*.txt'):
        if path.is_file() and not path.is_symlink():
            try:
                secret = path.read_text().strip()
            except (OSError, UnicodeError):
                continue
            if secret:
                value = value.replace(secret, '[REDACTED SECRET]')
    value = re.sub(r"(?im)((?:[a-z0-9_.-]*(?:password|passwd|secret|token|salt)[a-z0-9_.-]*)\s*[=:]\s*)(?:'[^'\n]*'|\"[^\"\n]*\"|[^\s,;]+)",
                   r'\1[REDACTED]', value)
    value = re.sub(r"(?i)(IDENTIFIED\s+BY\s+)(?:'[^']*'|\"[^\"]*\")", r'\1[REDACTED]', value)
    return value


def make(target):
    result = command(['make', target], timeout=600, check=False)
    if result.returncode:
        with tempfile.NamedTemporaryFile(mode='w', prefix='inception-lifecycle-',
                                         suffix='.log', delete=False) as log:
            log.write(result.stdout + result.stderr)
            path = log.name
        print('make %s diagnostics (credentials redacted):' % target, file=sys.stderr)
        print(sanitize_diagnostics(result.stdout + result.stderr), file=sys.stderr)
        raise RuntimeError('make %s failed; private diagnostics: %s' % (target, path))


def running(project):
    ids = command(DOCKER + ['ps', '--no-trunc', '--quiet', '--filter',
                           'label=com.docker.compose.project=' + project]).stdout.split()
    if not ids:
        return {}
    containers = json.loads(command(DOCKER + ['inspect', *ids]).stdout)
    result = {}
    for container in containers:
        service = container['Config']['Labels'].get('com.docker.compose.service')
        if service in result:
            raise RuntimeError('Ambiguous running service')
        result[service] = container['Id']
        if container['State'].get('Health', {}).get('Status', 'healthy') != 'healthy':
            raise RuntimeError('Lifecycle command returned before service readiness')
    return result


def siteurl():
    return command(COMPOSE + ['exec', '-T', '--user', 'www-data', 'wordpress',
                             'wp', 'option', 'get', 'siteurl', '--path=/var/www/html']).stdout.strip()


def salts():
    # The salt values remain inside the container; only a digest crosses stdout.
    value = command(COMPOSE + ['exec', '-T', 'wordpress', 'sha256sum',
                               '/var/www/.inception-state/salts']).stdout.split()[0]
    if len(value) != hashlib.sha256().digest_size * 2:
        raise RuntimeError('Invalid salt digest')
    return value


def https(domain):
    command(['curl', '--fail', '--silent', '--show-error', '--max-time', '15',
             '--cacert', 'secrets/tls_certificate.pem', '--resolve',
             domain + ':443:127.0.0.1', 'https://' + domain + '/'])


def verify(project, domain, expected, ids, url, salt_digest, mode):
    # This is deliberately the first probe after make returns: no polling or retries.
    if siteurl() != url:
        raise RuntimeError('Site URL changed across lifecycle operation')
    https(domain)
    current = running(project)
    if set(current) != expected or current != ids:
        raise RuntimeError('Service set or container identity changed')
    if salts() != salt_digest:
        raise RuntimeError('Persistent WordPress salts changed')
    env = json.loads(command(DOCKER + ['inspect', '--format', '{{json .Config.Env}}',
                                      ids['wordpress']]).stdout)
    if 'WP_REDIS_DISABLED=' + ('1' if mode == 'mandatory' else '0') not in env:
        raise RuntimeError('The saved WordPress cache mode changed')


def negative_readiness():
    owner = uuid.uuid4().hex
    name = 'inception-lifecycle-test-' + owner[:12]
    container_id = None
    try:
        result = command(DOCKER + ['run', '--detach', '--pull=never', '--name', name,
                                  '--label', 'inception.test.owner=' + owner,
                                  '--network', 'none', '--read-only',
                                  '--health-cmd', 'exit 1', '--health-interval', '1s',
                                  '--health-timeout', '1s', '--health-retries', '1',
                                  '--entrypoint', 'sleep', 'nginx:inception', '30'])
        container_id = result.stdout.strip()
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            status = command(DOCKER + ['inspect', '--format',
                                      '{{.State.Health.Status}}', container_id]).stdout.strip()
            if status == 'unhealthy':
                break
            time.sleep(0.1)
        else:
            raise RuntimeError('Negative readiness fixture did not become unhealthy')
        started = time.monotonic()
        result = command([sys.executable, 'srcs/tools/wait-services.py', '--timeout', '2',
                          '--expected', '1', '--', container_id], timeout=6, check=False)
        elapsed = time.monotonic() - started
        if result.returncode == 0 or not 1.5 <= elapsed <= 5:
            raise RuntimeError('Unhealthy fixture was accepted or timeout was unbounded')
        print(json.dumps({'test': 'unhealthy readiness timeout', 'result': 'PASS',
                          'seconds': round(elapsed, 2)}), flush=True)
    finally:
        if container_id:
            label = command(DOCKER + ['inspect', '--format',
                                     '{{index .Config.Labels "inception.test.owner"}}',
                                     container_id], check=False).stdout.strip()
            if label == owner:
                command(DOCKER + ['rm', '--force', container_id])


def main():
    config = json.loads(command(COMPOSE + ['--profile', 'bonus', 'config', '--format', 'json']).stdout)
    project = config['name']
    domain = config['services']['nginx']['environment']['DOMAIN_NAME']
    try:
        for mode, target, expected in [('mandatory', 'up', MANDATORY),
                                       ('bonus', 'bonus', BONUS)]:
            make(target)
            url = siteurl()
            if url != 'https://' + domain:
                raise RuntimeError('Unexpected configured WordPress URL')
            digest = salts()
            ids = running(project)
            if set(ids) != expected:
                raise RuntimeError('Unexpected initial running service set')
            make('restart')
            verify(project, domain, expected, ids, url, digest, mode)
            print(json.dumps({'test': mode + ' restart readiness, identity and persistence',
                              'result': 'PASS', 'services': len(expected)}), flush=True)
            make('stop')
            if running(project):
                raise RuntimeError('Stop left stack services running')
            make('start')
            verify(project, domain, expected, ids, url, digest, mode)
            print(json.dumps({'test': mode + ' stop/start readiness, identity and persistence',
                              'result': 'PASS', 'services': len(expected)}), flush=True)
        negative_readiness()
    finally:
        # This test intentionally operates the submitted stack, retaining all data.
        make('up')
    final_ids = running(project)
    if set(final_ids) != MANDATORY:
        raise RuntimeError('Could not restore the mandatory service set')
    https(domain)
    print(json.dumps({'test': 'mandatory mode restored', 'result': 'PASS'}), flush=True)


if __name__ == '__main__':
    main()
