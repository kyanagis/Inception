*This project has been created as part of the 42 curriculum by kyanagis.*

# Inception

## Description

Inception builds a small web infrastructure with Docker Compose inside a dedicated virtual machine. The mandatory stack contains three locally built service images: NGINX is the only public entry point on TCP 443, WordPress runs with PHP-FPM, and MariaDB stores the application database. TLS is restricted to versions 1.2 and 1.3.

WordPress files and database files persist in separate Docker named volumes. The Docker daemon is configured so the persistent data is stored below `/home/<login>/data`, while the application still uses native named volumes rather than bind mounts.

The bonus profile adds Redis object caching, explicit FTPS access to WordPress uploads, a static site, Adminer, and scheduled backups.

Security is treated as a set of hypotheses to verify rather than a set of claims. The repository includes static checks, runtime smoke tests, a bonus integration test, dependency freshness checks, crash/partial-state fault injection, backup restore drills, and a hypothesis-driven security audit. Containers use read-only root filesystems, reduced Linux capabilities, `no-new-privileges`, bounded logs, explicit networks, health checks, and file-backed Compose secrets.

### Design choices

| Topic | Chosen model | Why |
|---|---|---|
| Virtual machine vs Docker | A dedicated VM hosts Docker; containers isolate individual services | The VM supplies the kernel/host boundary, while containers provide lightweight per-service isolation and reproducible lifecycle management. |
| Secrets vs environment variables | Credentials and private keys use file-backed Compose secrets; `.env` contains only non-secret deployment values | Environment variables are easy to expose through process/container metadata, while mounted secret files can be scoped to the services that require them. |
| Docker network vs host network | Explicit bridge networks (`edge`, `frontend`, `backend`, `adminer_access`); host networking is forbidden | Bridge networks make service reachability explicit and keep MariaDB, WordPress, and Redis off the host network namespace. |
| Docker named volumes vs bind mounts | MariaDB and WordPress persistence use native named volumes; Docker's data-root is below `/home/<login>/data` | Named volumes satisfy the persistence requirement without coupling containers to arbitrary host paths; moving Docker's data-root keeps the actual volume data below the required learner path. |

Virtual machines and containers solve different isolation problems. The VM provides the host boundary and its own kernel; containers share that VM kernel while isolating services through namespaces, cgroups, networks, capabilities, and filesystems.

Passwords and private keys are not stored in the committed `.env` file. Runtime credentials are generated into the ignored `secrets/` directory and mounted only into the services that need them. The `.env` file contains non-secret deployment configuration such as the domain and database identifiers.

The mandatory network path is:

```text
client -> NGINX:443 -> WordPress/PHP-FPM:9000 -> MariaDB:3306
```

MariaDB and WordPress have no host-published ports. Redis is also private in the bonus profile. Adminer and the static site bind only to loopback. FTPS is the only bonus service intentionally exposed beyond loopback.

All service images start from a digest-pinned Debian 12 slim base. WordPress, WP-CLI, the Redis plugin, and Adminer are additionally version- and SHA-256-pinned where upstream artifacts are downloaded during image construction.

## Instructions

Use a dedicated Debian VM with rootful Docker. Do not run the host bootstrap on a shared workstation or on a Docker daemon that contains unrelated workloads.

### First setup

```sh
git clone --branch submit --single-branch https://github.com/kyanagis/Inception.git
cd Inception

make configure LOGIN=<your_42_login>
make host-setup LOGIN=<your_42_login>
make check
make doctor
make up
make test
```

`host-setup` validates that it is running in a dedicated VM, configures Docker's persistent data-root below `/home/<login>/data`, and applies the local hostname mapping required by the project. It fails closed when it detects an unsafe migration or conflicting Docker state.

Open:

```text
https://<login>.42.fr
```

The TLS certificate is locally generated and self-signed. Verify its SHA-256 fingerprint before accepting the browser exception.

### Mandatory lifecycle

```sh
make build
make up
make status
make test
make audit
make dependency-audit
make stop
make start
make restart
make down
```

`make test` converges the mandatory stack and verifies the static repository contract plus the running NGINX/WordPress/MariaDB path.

`make audit` checks declared and runtime security boundaries such as privileged mode, host namespaces, backend port publication, credential handling, read-only root filesystems, `no-new-privileges`, and Docker storage pressure.

`make dependency-audit` verifies upstream freshness and pinned integrity for WordPress Core, WP-CLI, Redis Object Cache, and Adminer. WordPress/WordPress.org archives are re-hashed, while GitHub release assets are checked against the official published asset digests where available.

### Bonus lifecycle

```sh
make bonus
make bonus-test
make backup-now
make backup-list
make backup-verify BACKUP=<backup-name>
```

`make bonus-test` verifies the complete bonus topology, Redis authentication and object-cache functionality, loopback exposure of Adminer and the static site, authenticated FTPS write boundaries including traversal/rename/PHP-execution negative probes, backup manifest verification, and a real database/files restore drill.

### Recovery and destructive reset

Before deleting data, record `make status` and the minimum required logs.

```sh
make logs
make fclean
```

`make fclean` removes the project containers, project images, and named-volume data. Verify a backup before using it when the existing state matters.

## Resources

Primary references used while implementing and reviewing the project:

- Docker Engine documentation
- Docker Compose specification and secrets documentation
- Docker storage volume documentation
- NGINX documentation
- MariaDB Server documentation
- WordPress developer documentation
- WP-CLI documentation
- PHP-FPM documentation
- Redis ACL documentation
- OpenSSL documentation
- Mozilla TLS configuration guidance
- OWASP Docker Security Cheat Sheet

Detailed operator instructions are in `USER_DOC.md`. Architecture, bootstrap, validation, recovery, and threat-oriented review procedures are in `DEV_DOC.md`. `REQUIREMENTS.md` maps subject requirements to implementation and verification evidence.

## AI usage

AI was used as a review and drafting aid for requirements traceability, shell and Compose review, threat-hypothesis generation, documentation structure, CI design, and adversarial edge-case analysis. Generated suggestions were reviewed against the repository, and executable claims are backed by repository checks or target-VM tests. AI output is not treated as authoritative evidence; the learner remains responsible for understanding and defending every submitted component.
