#!/usr/bin/env python3
"""Run destructive recovery checks only against privately owned Docker resources."""
import json
import os
from pathlib import Path
import secrets
import signal
import shlex
import subprocess
import sys
import tempfile
import time

root = Path(sys.argv[1]).resolve()
docker = ['docker', '--host', 'unix:///var/run/docker.sock']
token = secrets.token_hex(12)
project = 'inception-fault-' + token
label = 'fr.42.inception.fault-owner'
# Caller exports must not override this test's independent fixture identity.
blocked = {line.split('=', 1)[0] for line in (root / 'srcs/.env.example').read_text().splitlines() if '=' in line}
blocked.update({'WP_REDIS_DISABLED', 'COMPOSE_PROFILES', 'COMPOSE_FILE', 'COMPOSE_PROJECT_NAME'})
process_env = {key: value for key, value in os.environ.items() if key not in blocked}
services = ('mariadb', 'wordpress', 'nginx')


def interrupted(signum, frame):
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
signal.signal(signal.SIGHUP, interrupted)


def run(args, check=True, timeout=240):
    return subprocess.run(args, check=check, capture_output=True, text=True, timeout=timeout, env=process_env)


def inspect(kind, name):
    result = run(docker + [kind, 'inspect', name], check=False)
    return json.loads(result.stdout)[0] if result.returncode == 0 else None


def owned(kind, name):
    value = inspect(kind, name)
    if value is None or (value.get('Config', value).get('Labels') or {}).get(label) != token:
        raise RuntimeError('Refusing missing or unowned resource: ' + name)
    return value


with tempfile.TemporaryDirectory(prefix=project + '.') as temporary:
    scratch = Path(temporary)
    scratch.chmod(0o700)
    env = scratch / 'environment'
    template = (root / 'srcs/.env.example').read_text()
    env.write_text(template.replace('LOGIN', 'faulttest'))
    config = json.loads(run(docker + ['compose', '--env-file', str(env), '-f',
        str(root / 'srcs/docker-compose.yml'), 'config', '--format', 'json']).stdout)
    config['name'] = project
    config['services'] = {name: config['services'][name] for name in services}
    volumes = {v['source'] for s in config['services'].values() for v in s.get('volumes', [])}
    networks = {n for s in config['services'].values() for n in s.get('networks', {})}
    passwords = {v['source'] for s in config['services'].values() for v in s.get('secrets', [])}
    config['volumes'] = {v: {'name': project + '_' + v, 'driver': 'local',
                            'labels': {label: token}} for v in volumes}
    config['networks'] = {n: {**config['networks'][n], 'name': project + '_' + n,
                              'labels': {label: token}} for n in networks}
    config['secrets'] = {name: {'file': str(scratch / name)} for name in passwords}
    for name in passwords - {'tls_certificate', 'tls_private_key'}:
        path = scratch / name
        path.write_text(secrets.token_hex(32) + '\n')
        path.chmod(0o600)
    run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
         '-subj', '/CN=faulttest.42.fr', '-addext', 'subjectAltName=DNS:faulttest.42.fr',
         '-keyout', str(scratch / 'tls_private_key'), '-out', str(scratch / 'tls_certificate')])
    for name in ('tls_certificate', 'tls_private_key'):
        (scratch / name).chmod(0o600)
    for service in config['services'].values():
        service.pop('build', None)
        service['pull_policy'] = 'never'
        service.pop('ports', None)
        service.pop('container_name', None)
        service['labels'] = {label: token}
        for mount in service.get('volumes', []):
            if mount['type'] != 'volume' or mount['source'] not in volumes:
                raise RuntimeError('Unexpected mount in isolated topology')
    config['services']['wordpress']['environment']['WP_REDIS_DISABLED'] = '1'
    path = scratch / 'compose.json'
    path.write_text(json.dumps(config))
    path.chmod(0o600)
    compose = docker + ['compose', '--project-name', project, '--env-file', str(env), '-f', str(path)]
    resources = [(kind, value['name']) for kind in ('volume', 'network')
                 for value in config[kind + 's'].values()]
    for kind, name in resources:
        if inspect(kind, name) is not None:
            raise RuntimeError('Isolated resource collision: ' + name)

    def container(service):
        cid = run(compose + ['ps', '--all', '--quiet', service]).stdout.strip()
        if not cid or '\n' in cid:
            raise RuntimeError('Expected one isolated container: ' + service)
        state = owned('container', cid)
        for mount in state.get('Mounts', []):
            if mount['Type'] == 'volume' and mount.get('Name') not in {
                    value['name'] for value in config['volumes'].values()}:
                raise RuntimeError('Unexpected volume attached to isolated container')
            if mount['Type'] == 'bind' and Path(mount['Source']).parent != scratch:
                raise RuntimeError('Unexpected bind attached to isolated container')
        return cid, state

    def execute(service, command):
        cid, _ = container(service)
        return run(docker + ['exec', cid, 'sh', '-ec', command])

    def up():
        run(compose + ['up', '--detach', '--no-build', '--wait', '--wait-timeout', '180'], timeout=210)
        for kind, name in resources:
            owned(kind, name)
        for service in services:
            container(service)

    def site():
        execute('wordpress', 'runuser -u www-data -- wp --path=/var/www/html core is-installed')
        result = execute('nginx', 'curl --fail --insecure --silent --resolve faulttest.42.fr:443:127.0.0.1 https://faulttest.42.fr/')
        if 'Inception' not in result.stdout or 'wp-admin/install.php' in result.stdout:
            raise RuntimeError('Recovered WordPress website is not installed')

    def inject(service, command):
        # Validate every mount before allowing destructive commands, including stopped containers.
        for name in services:
            container(name)
        run(compose + ['run', '--rm', '--no-deps', '--entrypoint', 'sh', service, '-ec', command])

    try:
        up()
        site()
        execute('wordpress', 'printf retained > /var/www/html/wp-content/uploads/fault-retention.txt')
        for service, pidfile in (('wordpress', '/run/php/php-fpm.pid'), ('mariadb', '/run/mysqld/mysqld.pid')):
            cid, state = container(service)
            before = state['RestartCount']
            execute(service, 'kill -KILL "$(cat ' + pidfile + ')"')
            for attempt in range(120):
                state = owned('container', cid)
                if state['RestartCount'] > before and state.get('State', {}).get('Health', {}).get('Status') == 'healthy':
                    break
                time.sleep(1)
            else:
                raise RuntimeError(service + ' failed crash recovery')
        site()
        execute('wordpress', 'test "$(cat /var/www/html/wp-content/uploads/fault-retention.txt)" = retained')
        # A real in-flight FastCGI request must finish when FPM receives SIGQUIT.
        request_name = 'fault-request-' + token + '.php'
        request_file = '/var/www/html/' + request_name
        marker = '/var/www/html/wp-content/uploads/fault-request-started'
        source = "<?php $deadline = microtime(true) + 3.0; file_put_contents('" + marker + "', 'ready'); while (microtime(true) < $deadline) { usleep(10000); } echo 'REQUEST_COMPLETED';"
        execute('wordpress', 'printf %s ' + shlex.quote(source) + ' > ' + shlex.quote(request_file)
                + '; chmod 0644 ' + shlex.quote(request_file))
        nginx_id, _ = container('nginx')
        wordpress_id, _ = container('wordpress')
        request_started = time.monotonic()
        request = subprocess.Popen(docker + ['exec', nginx_id, 'curl', '--fail', '--insecure', '--silent',
            '--max-time', '20', '--resolve', 'faulttest.42.fr:443:127.0.0.1',
            'https://faulttest.42.fr/' + request_name], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, env=process_env)
        try:
            for attempt in range(40):
                if run(docker + ['exec', wordpress_id, 'test', '-f', marker], check=False).returncode == 0:
                    break
                time.sleep(0.1)
            else:
                raise RuntimeError('FastCGI request never reached PHP worker')
            run(compose + ['stop', 'wordpress'])
            response, error = request.communicate(timeout=20)
            request_duration = time.monotonic() - request_started
            if request_duration < 2.8:
                raise RuntimeError('PHP request finished before its bounded three-second workload')
            stopped = owned('container', wordpress_id)['State']
            if request.returncode != 0 or response != 'REQUEST_COMPLETED' or stopped['ExitCode'] != 0 or stopped.get('OOMKilled'):
                raise RuntimeError('FPM lost active request or stopped abnormally: ' + error)
        finally:
            if request.poll() is None:
                request.terminate()
                request.communicate(timeout=25)
        up()
        execute('wordpress', 'rm -- ' + shlex.quote(request_file) + ' ' + shlex.quote(marker))
        run(compose + ['stop', 'nginx', 'wordpress'])
        inject('wordpress', 'test -d /var/www/.inception-state; rm -rf /var/www/html /var/www/.inception-wordpress; '
               'mkdir /var/www/.inception-wordpress; printf partial > /var/www/.inception-wordpress/crash-marker; '
               'rm -f /var/www/.inception-state/complete')
        up()
        site()
        execute('wordpress', 'test -f /var/www/.inception-state/complete; test ! -e /var/www/.inception-wordpress')
        run(compose + ['stop'])
        inject('wordpress', 'rm -f /var/www/.inception-state/complete')
        inject('mariadb', 'rm -rf /var/lib/mysql/data /var/lib/mysql/.inception-bootstrap; '
               'mkdir /var/lib/mysql/.inception-bootstrap; '
               'printf "%s\\n" inception-bootstrap-v1 > /var/lib/mysql/.inception-bootstrap/.inception-owned; '
               'printf "%s\\n%s\\n%s\\n" "$MYSQL_DATABASE" "$MYSQL_USER" "$MYSQL_BACKUP_USER" '
               '> /var/lib/mysql/.inception-bootstrap/.inception-identity')
        up()
        site()
        execute('mariadb', 'test -f /var/lib/mysql/data/.inception-complete; test ! -e /var/lib/mysql/.inception-bootstrap')
        print('Isolated crash and partial-state recovery tests passed.')
    except subprocess.CalledProcessError as error:
        # Only disposable credentials are used here; commands never contain passwords.
        print(error.stderr, file=sys.stderr)
        raise
    finally:
        # Never prune or remove shared images. Refuse resources without the private ownership token.
        listing = run(docker + ['ps', '--all', '--quiet', '--filter', f'label={label}={token}'])
        for cid in listing.stdout.split():
            owned('container', cid)
            run(docker + ['rm', '--force', cid])
        for kind, name in resources:
            if inspect(kind, name) is not None:
                owned(kind, name)
                run(docker + [kind, 'rm', name])
