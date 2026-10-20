#!/usr/bin/env python3
"""Exercise configuration preservation and secret-loss refusal in a disposable tree."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def run(args, cwd, success=True):
    result = subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=90)
    if (result.returncode == 0) != success:
        raise RuntimeError(f"Unexpected result for {args[0]}: {result.returncode}\n" + result.stdout.decode(errors="replace"))
    return result.stdout


def main():
    source = Path(__file__).resolve().parents[2]
    original = (source / "srcs/.env").read_bytes()
    domain = [line.partition(b"=")[2] for line in original.splitlines()
              if line.startswith(b"DOMAIN_NAME=")]
    if len(domain) != 1 or not domain[0].endswith(b".42.fr"):
        raise RuntimeError("Configure the project first")
    login = domain[0][:-6].decode("ascii")
    os.environ["LOGIN"] = login
    with tempfile.TemporaryDirectory(prefix="inception-config-test.") as temporary:
        root = Path(temporary)
        shutil.copytree(source / "srcs", root / "srcs")
        for name in ("Makefile", "README.md", "USER_DOC.md", "DEV_DOC.md"):
            shutil.copy2(source / name, root / name)
        shutil.copytree(source / ".inception", root / ".inception")
        env = root / "srcs/.env"
        custom = original + b"\n# configuration preservation regression\n"
        env.write_bytes(custom)
        os.chmod(env, 0o600)
        before = (env.read_bytes(), env.stat().st_mtime_ns)
        run(["sh", "srcs/tools/configure.sh", login], root)
        run(["make", "doctor", f"LOGIN={login}"], root)
        run(["sh", "srcs/host/evaluate", "prepare"], root)
        assert (env.read_bytes(), env.stat().st_mtime_ns) == before
        for suffix in (b"DOMAIN_NAME=other.42.fr\n",
                       b"export DOMAIN_NAME=other.42.fr\n",
                       b" DOMAIN_NAME = other.42.fr\n"):
            env.write_bytes(custom + suffix)
            before = (env.read_bytes(), env.stat().st_mtime_ns)
            run(["sh", "srcs/tools/configure.sh", login], root, success=False)
            assert (env.read_bytes(), env.stat().st_mtime_ns) == before
        env.write_bytes(custom)
        before = (env.read_bytes(), env.stat().st_mtime_ns)
        run(["sh", "srcs/tools/configure.sh", "anotherlogin"], root, success=False)
        assert (env.read_bytes(), env.stat().st_mtime_ns) == before
        # setup only queries the deployed volume; all candidate secrets live in
        # this temporary tree, and refusal must happen before TLS generation.
        run(["docker", "--host", "unix:///var/run/docker.sock", "volume",
             "inspect", "inception_mariadb_data"], root)
        secret_dir = root / "secrets"
        secret_dir.mkdir(mode=0o700)
        for name in ("db_password", "db_root_password", "wp_admin_password",
                     "wp_user_password", "ftp_password"):
            value = run(["openssl", "rand", "-hex", "32"], root)
            (secret_dir / f"{name}.txt").write_bytes(value)
        before = {file.name: file.read_bytes() for file in secret_dir.iterdir()}
        run(["sh", "srcs/tools/setup.sh"], root, success=False)
        after = {file.name: file.read_bytes() for file in secret_dir.iterdir()
                 if file.name != ".setup.lock"}
        assert after == before, "Secret-loss refusal changed another secret"
    print("Configuration preservation, ambiguous identity and missing-secret tests passed.")


if __name__ == "__main__":
    main()
