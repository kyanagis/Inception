This project has been created as part of the 42 curriculum by kyanagis.

# Inception

## Description

Inception builds a small web infrastructure with Docker Compose inside a dedicated virtual machine. The mandatory stack contains three locally built service images: NGINX is the only public entry point on TCP 443, WordPress runs with PHP-FPM, and MariaDB stores the application database. TLS is restricted to versions 1.2 and 1.3.

WordPress files and database files persist in separate Docker named volumes. The dedicated Docker daemon stores its data below /home/<login>/data, so the mandatory persistent data remains under the subject-required learner path without converting the volumes into bind mounts.

The bonus profile adds Redis object caching, explicit FTPS access to WordPress uploads, a static site, Adminer, and a scheduled backup service.

Security is treated as a set of hypotheses to verify rather than a set of claims. The repository includes static checks, runtime smoke tests, a bonus integration test, and a hypothesis-driven audit. Containers use read-only root filesystems, reduced Linux capabilities, no-new-privileges, bounded logs, explicit networks, health checks, and file-backed Compose secrets.

### Design choices

Virtual machines and containers solve different isolation problems. The VM provides the host boundary and its own kernel; containers share that VM kernel while isolating services through namespaces, cgroups, networks, capabilities, and filesystems.

Passwords and private keys are not stored in the committed .env file. Runtime credentials are generated into the ignored secrets directory and mounted only into the services that need them. The .env file contains non-secret deployment configuration such as the domain and database identifiers.

The mandatory network path is:

    client -> NGINX:443 -> WordPress/PHP-FPM:9000 -> MariaDB:3306

MariaDB and WordPress have no host-published ports. Redis is also private in the bonus profile. Adminer and the static site bind only to loopback. FTPS is the only bonus service intentionally exposed beyond loopback.

All service images start from a digest-pinned Debian 12 slim base. WordPress, WP-CLI, the Redis plugin, and Adminer are additionally version- and SHA-256-pinned where upstream artifacts are downloaded during image construction.

## Instructions

There are two supported host modes. Do not mix their bootstrap procedures.

### A. Published universal OVA

The OVA already configures Docker and its persistent data-root. Do not run make host-setup inside the OVA.

First configure the 42 login:

    inception-setup kyanagis

Open a new terminal. The universal evaluator can then fetch the current submit branch and prepare it:

    inception-evaluate --prepare

The equivalent manual procedure is:

    cd /home/inception
    git clone --branch submit --single-branch       https://github.com/kyanagis/Inception.git Inception-submit
    cd Inception-submit
    make configure LOGIN="$INCEPTION_LOGIN"
    make doctor
    make check
    make up
    make test

The OVA is intentionally not tied to a specific submit commit. inception-evaluate fast-forwards a clean checkout to the current remote submit branch and reads .inception/host-tools. If a future submit revision requires an additional ordinary userspace tool, the evaluator can provide the missing Nix package ephemerally without rebuilding the appliance.

### B. Generic dedicated Debian VM

On a fresh dedicated Debian VM with rootful Docker:

    make configure LOGIN=kyanagis
    make host-setup LOGIN=kyanagis
    make check
    make doctor
    make up
    make test

host-setup deliberately refuses the managed OVA, non-VM hosts, non-empty Docker daemons, conflicting host configuration, rootless Docker, and unsafe storage migration.

### Mandatory lifecycle

    make build
    make up
    make status
    make test
    make audit
    make stop
    make start
    make restart
    make down

Open:

    https://<login>.42.fr

The TLS certificate is locally generated and self-signed. Verify its fingerprint before accepting the browser exception.

### Bonus lifecycle

    make bonus
    make bonus-test
    make backup-now
    make backup-list
    make backup-verify BACKUP=<backup-name>

bonus-test verifies the actual service set, health status, Redis authentication, loopback exposure of Adminer and the static site, explicit FTPS TLS negotiation, and creation plus verification of a real backup.

### Destructive reset

    make fclean

This removes project containers, project images, and named-volume data. Verify backups before using it.

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

Detailed operating instructions are in USER_DOC.md. Architecture, bootstrap, validation, recovery, and threat-oriented review procedures are in DEV_DOC.md. REQUIREMENTS.md maps subject requirements to implementation and verification evidence.

## AI usage

AI was used as a review and drafting aid for requirements traceability, shell and Compose review, threat-hypothesis generation, documentation structure, CI design, and adversarial edge-case analysis. Generated suggestions were reviewed against the repository, and executable claims are backed by repository checks or target-VM tests. AI output is not treated as authoritative evidence; the learner remains responsible for understanding and defending every submitted component.
