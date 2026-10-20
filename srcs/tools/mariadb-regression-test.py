#!/usr/bin/env python3
"""Exercise the built MariaDB image using owned, disposable Docker resources only."""
import argparse
import json
import os
from pathlib import Path
import secrets
import signal
import subprocess
import tempfile
import time
import uuid


class Probe:
    def __init__(self, image, directory):
        self.image = image
        self.directory = Path(directory)
        self.owner = uuid.uuid4().hex
        self.prefix = 'inception-db-test-' + self.owner[:12]
        self.volume = self.prefix + '-data'
        self.name = self.prefix + '-server'
        self.names = set()
        self.results = []
        self.secrets = {}
        for key in ('db_root_password', 'db_password', 'db_backup_password'):
            value = secrets.token_hex(32)
            self.secrets[key] = value
            self.write_secret(key, value)

    def command(self, *args, input=None, check=True):
        if args[0] == 'docker':
            args = ('docker', '--host', 'unix:///var/run/docker.sock', *args[1:])
        result = subprocess.run(args, input=input, text=True, capture_output=True,
                                timeout=120)
        if check and result.returncode:
            # Server/client diagnostics may include SQL: never echo them.
            raise RuntimeError('Docker operation failed; secret-bearing diagnostics suppressed')
        return result

    def write_secret(self, key, value):
        path = self.directory / key
        path.write_text(value)
        path.chmod(0o600)

    def inspect(self, kind, name, template):
        return self.command('docker', kind, 'inspect', '--format', template,
                            name, check=False).stdout.strip()

    def args(self, name):
        self.names.add(name)
        args = ['docker', 'run', '--pull=never', '--name', name, '--label',
                'inception.test.owner=' + self.owner, '--network', 'none',
                '--read-only', '--init', '--cap-drop', 'ALL',
                '--security-opt', 'no-new-privileges:true',
                '--tmpfs', '/run/mysqld:mode=0755,size=16m',
                '--tmpfs', '/tmp:mode=1777,size=128m',
                '--mount', 'type=volume,src=' + self.volume + ',dst=/var/lib/mysql']
        for cap in ('CHOWN', 'DAC_OVERRIDE', 'KILL', 'SETGID', 'SETUID'):
            args += ['--cap-add', cap]
        for key in self.secrets:
            args += ['--mount', 'type=bind,src=' + str(self.directory / key)
                     + ',dst=/run/secrets/' + key + ',readonly']
        args += ['-e', 'MYSQL_DATABASE=testdb', '-e', 'MYSQL_USER=testapp',
                 '-e', 'MYSQL_BACKUP_USER=testbackup']
        return args

    def remove(self, name):
        owner = self.inspect('container', name,
                             '{{index .Config.Labels "inception.test.owner"}}')
        if owner == self.owner:
            self.command('docker', 'rm', '-f', name)

    def start(self, healthy=True):
        args = self.args(self.name)
        self.command(*args[:2], '-d', *args[2:], self.image)
        began = time.monotonic()
        limit = 90 if healthy else 10
        while time.monotonic() - began < limit:
            status = self.inspect('container', self.name, '{{.State.Status}}')
            if status == 'exited':
                code = self.inspect('container', self.name, '{{.State.ExitCode}}')
                if healthy or code != '1':
                    raise RuntimeError('Unexpected database startup outcome')
                return round(time.monotonic() - began, 2)
            if healthy and not self.command('docker', 'exec', self.name,
                                           '/usr/local/bin/mariadb-healthcheck',
                                           check=False).returncode:
                return round(time.monotonic() - began, 2)
            time.sleep(0.2)
        raise RuntimeError('Database startup did not reach the expected state in time')

    def stop(self):
        self.command('docker', 'stop', '-t', '10', self.name)
        code = self.inspect('container', self.name, '{{.State.ExitCode}}')
        if code != '0':
            raise RuntimeError('Database did not stop cleanly')
        self.remove(self.name)

    def sql(self, statement):
        script = '''f=$(mktemp /run/mysqld/.test.XXXXXX)
trap 'rm -f "$f"' EXIT
printf '[client]\\nuser=root\\npassword=%s\\n' "$(cat /run/secrets/db_root_password)" > "$f"
mariadb --defaults-file="$f" --batch --skip-column-names
'''
        return self.command('docker', 'exec', '-i', self.name, 'sh', '-c',
                            script, input=statement).stdout.strip()

    def helper(self, script, statement=None):
        name = self.prefix + '-helper'
        args = self.args(name)
        self.command(*args[:2], '--rm', '-i', '--entrypoint', 'sh',
                     *args[2:], self.image, '-c', script, input=statement)

    def restore(self, statement):
        # Test-only repair of precisely the policy mutation made by this probe.
        # The application entrypoint never changes existing account passwords.
        self.helper('gosu mysql mariadbd --no-defaults --bootstrap --skip-networking '
                    '--datadir=/var/lib/mysql/data > /run/mysqld/repair.log 2>&1',
                    'FLUSH PRIVILEGES;\n' + statement.replace(';', ';\n') + '\n')

    def record(self, name, elapsed=None):
        result = {'test': name, 'result': 'PASS'}
        if elapsed is not None:
            result['rejected_after_seconds'] = elapsed
        self.results.append(result)
        print(json.dumps(result), flush=True)

    def run(self):
        self.command('docker', 'image', 'inspect', self.image)
        self.command('docker', 'volume', 'create', '--label',
                     'inception.test.owner=' + self.owner, self.volume)
        owner = self.inspect('volume', self.volume,
                             '{{index .Labels "inception.test.owner"}}')
        if owner != self.owner:
            raise RuntimeError('Refusing to use a volume not owned by this test')
        self.start()
        self.record('fresh root/application/backup authentication and database selection')
        self.sql('CREATE TABLE testdb.sentinel (id INT PRIMARY KEY); '
                 'INSERT INTO testdb.sentinel VALUES (7);')
        other = self.prefix + '-duplicate'
        args = self.args(other)
        self.command(*args[:2], '-d', *args[2:], self.image)
        deadline = time.monotonic() + 5
        while self.inspect('container', other, '{{.State.Status}}') != 'exited':
            if time.monotonic() > deadline:
                raise RuntimeError('Duplicate database startup was not rejected')
            time.sleep(0.1)
        if self.inspect('container', other, '{{.State.ExitCode}}') != '1':
            raise RuntimeError('Unexpected duplicate startup exit status')
        self.remove(other)
        self.record('exclusive volume lock remains held by foreground mariadbd')
        for key, value in self.secrets.items():
            self.stop()
            self.write_secret(key, secrets.token_hex(32))
            elapsed = self.start(healthy=False)
            self.remove(self.name)
            self.write_secret(key, value)
            self.start()
            self.record(key + ' mismatch rejected and original credential recovered', elapsed)
        policy_password = secrets.token_hex(32)
        policies = [
            ('account lock', "ALTER USER 'testapp'@'%' ACCOUNT LOCK;",
             "ALTER USER 'testapp'@'%' ACCOUNT UNLOCK;"),
            ('password expiry', "ALTER USER 'testapp'@'%' PASSWORD EXPIRE;",
             "ALTER USER 'testapp'@'%' PASSWORD EXPIRE NEVER; UPDATE mysql.global_priv SET Priv=JSON_SET(Priv,'$.password_last_changed',UNIX_TIMESTAMP()) WHERE User='testapp'; FLUSH PRIVILEGES;"),
            ('password lifetime', "ALTER USER 'testapp'@'%' PASSWORD EXPIRE INTERVAL 2 DAY;",
             "ALTER USER 'testapp'@'%' PASSWORD EXPIRE NEVER;"),
            ('host override', f"CREATE USER 'testapp'@'localhost' IDENTIFIED BY '{policy_password}';",
             "DROP USER 'testapp'@'localhost';"),
            ('anonymous host override', f"CREATE USER ''@'localhost' IDENTIFIED BY '{policy_password}';",
             "DROP USER ''@'localhost';"),
            ('application privilege', "REVOKE SELECT ON testdb.* FROM 'testapp'@'%';",
             "GRANT SELECT ON testdb.* TO 'testapp'@'%';"),
            ('backup privilege', "REVOKE EVENT ON testdb.* FROM 'testbackup'@'%';",
             "GRANT EVENT ON testdb.* TO 'testbackup'@'%';"),
            ('authentication plugin', "UPDATE mysql.global_priv SET Priv=JSON_SET(Priv,'$.plugin','unix_socket') WHERE User='testapp'; FLUSH PRIVILEGES;",
             "UPDATE mysql.global_priv SET Priv=JSON_SET(Priv,'$.plugin','mysql_native_password') WHERE User='testapp'; FLUSH PRIVILEGES;"),
            ('alternative authentication', "UPDATE mysql.global_priv SET Priv=JSON_SET(Priv,'$.auth_or',JSON_ARRAY(JSON_OBJECT(),JSON_OBJECT('plugin','unix_socket'))) WHERE User='testapp'; FLUSH PRIVILEGES;",
             "UPDATE mysql.global_priv SET Priv=JSON_REMOVE(Priv,'$.auth_or') WHERE User='testapp'; FLUSH PRIVILEGES;"),
        ]
        for label, mutate, repair in policies:
            self.sql(mutate)
            self.stop()
            elapsed = self.start(healthy=False)
            self.remove(self.name)
            self.restore(repair)
            self.start()
            self.record(label + ' rejected and original policy recovered', elapsed)
        if self.sql('SELECT COUNT(*) FROM testdb.sentinel WHERE id=7;') != '1':
            raise RuntimeError('Sentinel data was not retained')
        self.stop()
        for label, mutate, repair in [
            ('symlink completion marker',
             'mv .inception-complete .saved-complete; ln -s .saved-complete .inception-complete',
             'rm .inception-complete; mv .saved-complete .inception-complete'),
            ('legacy identity',
             'cp .inception-identity .saved-identity; head -n 2 .saved-identity > .inception-identity',
             'mv .saved-identity .inception-identity'),
        ]:
            self.helper('cd /var/lib/mysql/data; ' + mutate)
            elapsed = self.start(healthy=False)
            self.remove(self.name)
            self.helper('cd /var/lib/mysql/data; ' + repair)
            self.start()
            self.stop()
            self.record(label + ' rejected without destructive migration', elapsed)
        self.record('sentinel retained and repeated clean foreground shutdown')

    def cleanup(self):
        for name in self.names:
            self.remove(name)
        owner = self.inspect('volume', self.volume,
                             '{{index .Labels "inception.test.owner"}}')
        if owner == self.owner:
            self.command('docker', 'volume', 'rm', self.volume)


def interrupted(signum, frame):
    raise SystemExit(128 + signum)


def main():
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', default='mariadb:inception')
    args = parser.parse_args()
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix='inception-db-test-') as directory:
        probe = Probe(args.image, directory)
        try:
            probe.run()
        finally:
            probe.cleanup()


if __name__ == '__main__':
    main()
