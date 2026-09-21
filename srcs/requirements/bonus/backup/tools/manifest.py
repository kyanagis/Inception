#!/usr/bin/python3
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import tarfile
import time


ARTIFACTS = ("database.sql.gz", "wordpress.tar.gz")
BACKUP_NAME = r"[0-9]{8}T[0-9]{6}Z-[A-Za-z0-9]{10}"
FORMAT = "inception-backup-v2"
IDENTITY_KEYS = ("DOMAIN_NAME", "MYSQL_DATABASE", "MYSQL_USER", "WP_ADMIN_USER", "WP_USER")
STATE_MARKER = "inception-wordpress-v1"


def digest_stream(stream):
    result = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        result.update(chunk)
    return result.hexdigest()


def digest_file(path):
    if not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError("backup artifact is not a regular file")
    with path.open("rb") as stream:
        return digest_stream(stream)


def inventory(path):
    entries = []
    seen = set()
    with tarfile.open(path, "r:gz") as archive:
        for member in archive:
            relative = PurePosixPath(member.name)
            if relative.is_absolute() or ".." in relative.parts:
                raise ValueError("unsafe archive path")
            name = str(relative)
            if name in seen or not (member.isfile() or member.isdir()):
                raise ValueError("duplicate archive path or unsupported link/special file")
            seen.add(name)
            entry = {"path": name, "type": "file" if member.isfile() else "directory", "mode": member.mode, "size": member.size}
            if member.isfile():
                with archive.extractfile(member) as stream:
                    entry["sha256"] = digest_stream(stream)
            entries.append(entry)
    return entries


def validate_identity(identity):
    if not isinstance(identity, dict) or set(identity) != set(IDENTITY_KEYS):
        raise ValueError("invalid deployment identity fields")
    if not all(isinstance(value, str) and value for value in identity.values()):
        raise ValueError("invalid deployment identity values")
    if not re.fullmatch(r"[a-z][a-z0-9-]{0,31}\.42\.fr", identity["DOMAIN_NAME"]):
        raise ValueError("invalid deployment domain")
    for key in ("MYSQL_DATABASE", "MYSQL_USER"):
        if not re.fullmatch(r"[A-Za-z0-9_]+", identity[key]):
            raise ValueError("invalid database identity")
    for key in ("WP_ADMIN_USER", "WP_USER"):
        if not re.fullmatch(r"[A-Za-z0-9_-]+", identity[key]):
            raise ValueError("invalid WordPress identity")
    if "admin" in identity["WP_ADMIN_USER"].lower() or identity["WP_ADMIN_USER"] == identity["WP_USER"]:
        raise ValueError("invalid WordPress account roles")
    if identity["MYSQL_USER"] == "root":
        raise ValueError("invalid database application account")


def source_identity():
    state = Path("/source/.inception-state")
    if not stat.S_ISDIR(state.lstat().st_mode):
        raise ValueError("missing or unsafe WordPress management state")
    for name in ("identity", "complete"):
        metadata = (state / name).lstat()
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0:
            raise ValueError("unsafe WordPress management metadata")
    if (state / "complete").read_text() != STATE_MARKER + "\n":
        raise ValueError("WordPress initialization is not complete")
    values = (state / "identity").read_text().splitlines()
    if len(values) != len(IDENTITY_KEYS):
        raise ValueError("incomplete WordPress identity")
    identity = dict(zip(IDENTITY_KEYS, values))
    validate_identity(identity)
    if any(os.environ.get(key) != value for key, value in identity.items()):
        raise ValueError("backup configuration differs from committed WordPress identity")
    return identity


def archive_version(path):
    with tarfile.open(path, "r:gz") as archive:
        for member in archive:
            if str(PurePosixPath(member.name)) != "wp-includes/version.php":
                continue
            if not member.isfile() or member.size > 65536:
                raise ValueError("invalid WordPress version file")
            with archive.extractfile(member) as stream:
                content = stream.read().decode("utf-8")
            match = re.search(r"\$wp_version\s*=\s*['\"]([^'\"]+)['\"]", content)
            if match:
                return match.group(1)
    raise ValueError("WordPress version is missing from archive")


def create(directory, server_version, client_version):
    identity = source_identity()
    version_match = re.match(r"([0-9]+\.[0-9]+)\.", server_version)
    if not version_match:
        raise ValueError("unrecognized database server version")
    checksums = {name: digest_file(directory / name) for name in ARTIFACTS}
    manifest = {
        "format": FORMAT, "created_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "database": identity["MYSQL_DATABASE"], "database_server": server_version,
        "database_client": client_version, "wordpress_version": archive_version(directory / "wordpress.tar.gz"),
        "domain": identity["DOMAIN_NAME"], "consistency": "InnoDB snapshot; files require quiescent writers",
        "deployment": identity,
        "wordpress_state": {"identity": list(identity.values()), "complete": STATE_MARKER},
        "restore": {
            "method": "bootstrap-then-import", "database_major_minor": version_match.group(1),
            "required_external_secrets": ["db_password", "db_root_password", "wp_admin_password", "wp_user_password"],
            "steps": ["bootstrap an isolated daemon with matching deployment and original secrets",
                      "stop WordPress and all file/database writers",
                      "verify checksums, archive paths, deployment and database major/minor before import",
                      "import SQL into the matching bootstrapped database and replace html from the archive",
                      "preserve bootstrapped .inception-state and database management markers; restore file ownership",
                      "restart and verify both WordPress accounts, database content and upload checksums"],
        },
        "artifacts": checksums, "files": inventory(directory / "wordpress.tar.gz"),
    }
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    with (directory / "SHA256SUMS").open("w") as stream:
        for name in (*ARTIFACTS, "manifest.json"):
            stream.write(f"{digest_file(directory / name)}  {name}\n")


def verify(directory):
    if not stat.S_ISREG((directory / "manifest.json").lstat().st_mode):
        raise ValueError("invalid manifest file")
    manifest = json.loads((directory / "manifest.json").read_text())
    if not isinstance(manifest, dict) or manifest.get("format") != FORMAT or set(manifest.get("artifacts", {})) != set(ARTIFACTS):
        raise ValueError("unsupported manifest format")
    identity = manifest.get("deployment")
    validate_identity(identity)
    if manifest.get("database") != identity["MYSQL_DATABASE"] or manifest.get("domain") != identity["DOMAIN_NAME"]:
        raise ValueError("inconsistent deployment identity")
    if manifest.get("wordpress_state") != {"identity": [identity[key] for key in IDENTITY_KEYS], "complete": STATE_MARKER}:
        raise ValueError("inconsistent WordPress management state")
    restore = manifest.get("restore", {})
    version_match = re.match(r"([0-9]+\.[0-9]+)\.", manifest.get("database_server", ""))
    if not version_match or restore.get("method") != "bootstrap-then-import" or restore.get("database_major_minor") != version_match.group(1):
        raise ValueError("inconsistent restoration contract")
    sums = (directory / "SHA256SUMS")
    if not stat.S_ISREG(sums.lstat().st_mode):
        raise ValueError("invalid checksum file")
    expected_lines = []
    for name in (*ARTIFACTS, "manifest.json"):
        checksum = digest_file(directory / name)
        expected_lines.append(f"{checksum}  {name}")
        if name in ARTIFACTS and manifest["artifacts"][name] != checksum:
            raise ValueError("artifact checksum mismatch")
    if sums.read_text().splitlines() != expected_lines:
        raise ValueError("checksum manifest mismatch")
    with gzip.open(directory / "database.sql.gz", "rb") as stream:
        if not stream.read(1):
            raise ValueError("empty SQL dump")
        for _ in iter(lambda: stream.read(1024 * 1024), b""):
            pass
    if inventory(directory / "wordpress.tar.gz") != manifest.get("files"):
        raise ValueError("file inventory mismatch")
    if archive_version(directory / "wordpress.tar.gz") != manifest.get("wordpress_version"):
        raise ValueError("WordPress version differs from archived distribution")
    return manifest


def prune(directory, partial, days=1, current=None):
    pattern = (r"\.partial-" if partial else "") + BACKUP_NAME
    threshold = time.time() - days * 86400
    for entry in directory.iterdir():
        metadata = entry.lstat()
        if entry == current or not re.fullmatch(pattern, entry.name):
            continue
        if metadata.st_uid != os.geteuid() or not stat.S_ISDIR(metadata.st_mode) or metadata.st_mtime >= threshold:
            continue
        if not partial:
            marker = entry / "manifest.json"
            if not marker.exists() or not stat.S_ISREG(marker.lstat().st_mode):
                continue
            try:
                if json.loads(marker.read_text()).get("format") not in ("inception-backup-v1", FORMAT):
                    continue
            except (ValueError, OSError):
                continue
        shutil.rmtree(entry)


def client_options(path):
    raw = Path("/run/secrets/db_password").read_text()
    password = raw.removesuffix("\n")
    if not password or any(character in password for character in "\n\r\x00"):
        raise ValueError("invalid database secret")
    user = os.environ["MYSQL_USER"]
    if not re.fullmatch(r"[A-Za-z0-9_]+", user):
        raise ValueError("invalid database user")
    password = password.replace("\\", "\\\\").replace('"', '\\"')
    with path.open("w") as stream:
        stream.write(f'[client]\nhost=mariadb\nuser={user}\npassword="{password}"\n')
    path.chmod(0o600)


def list_backups(directory):
    if not stat.S_ISDIR(directory.lstat().st_mode):
        raise ValueError("backup root is not a directory")
    found = False
    for entry in sorted(directory.iterdir(), reverse=True):
        if not re.fullmatch(BACKUP_NAME, entry.name) or not stat.S_ISDIR(entry.lstat().st_mode):
            continue
        manifest = verify(entry)
        print(f'{entry.name}\t{manifest["created_utc"]}\tWordPress {manifest["wordpress_version"]}\t{manifest["domain"]}')
        found = True
    if not found:
        print("No verified backups found")


def main():
    operation = sys.argv[1]
    directory = Path(sys.argv[2])
    if operation == "create" and len(sys.argv) == 5:
        create(directory, sys.argv[3], sys.argv[4])
    elif operation == "verify" and len(sys.argv) == 3:
        verify(directory)
        print("Backup verified")
    elif operation == "prune-partial" and len(sys.argv) == 3:
        prune(directory, True)
    elif operation == "retain" and len(sys.argv) == 5:
        prune(directory, False, int(sys.argv[3]), Path(sys.argv[4]))
    elif operation == "client-options" and len(sys.argv) == 3:
        client_options(directory)
    elif operation == "check-source" and len(sys.argv) == 3:
        source_identity()
    elif operation == "list" and len(sys.argv) == 3:
        list_backups(directory)
    else:
        raise ValueError("usage: backup-manifest create|verify|list|prune-partial|retain|client-options|check-source ...")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, IndexError, tarfile.TarError) as error:
        print(f"Backup operation failed: {error}", file=sys.stderr)
        sys.exit(1)
