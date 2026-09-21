# Inception

## Description

Inception builds a small, reproducible web infrastructure with Docker Compose inside a dedicated Debian virtual machine. The mandatory stack contains three images built by this repository: NGINX is the sole public entry point on TCP 443, WordPress runs with PHP-FPM, and MariaDB stores the application database. TLS is restricted to versions 1.2 and 1.3. WordPress files and database files persist in separate Docker named volumes.

The bonus profile adds Redis object caching, an explicit-FTPS service for WordPress files, a static site, Adminer, and a scheduled backup service. Bonus ports are opened only when the bonus profile is selected; Adminer and the static site bind to loopback.

All service images start from a digest-pinned Debian 12 slim base. Application artifacts are version- and SHA-256-pinned. Runtime credentials are generated locally, mounted as Compose secrets, and excluded from Git. Containers use read-only root filesystems, reduced Linux capabilities, `no-new-privileges`, bounded logs, health checks, and explicit networks.

### Design choices

#### Virtual machines vs Docker

A virtual machine emulates a complete machine and runs its own kernel, giving a strong isolation boundary at a higher resource cost. A Docker container shares the host kernel and isolates processes through namespaces and cgroups. This project uses a dedicated VM as the host boundary and containers for repeatable service packaging. Containers are not treated as VMs: each one runs a foreground service as PID 1, with no keep-alive shell loops.

#### Secrets vs environment variables

Environment variables are suitable for non-confidential deployment settings such as a domain or database name, but they are easily exposed through process and container inspection. Passwords and private keys are therefore local files mounted through Docker Compose secrets. The committed `.env` contains identifiers and configuration only; it must never contain credentials.

#### Docker network vs host network

Docker bridge networks provide service-name discovery and restrict which containers can communicate. Host networking removes that boundary and can expose services unintentionally, so it is not used. The internal frontend and backend networks isolate application traffic; only NGINX joins the edge network in the mandatory stack.

#### Docker volumes vs bind mounts

Named volumes are managed by Docker and decouple container paths from arbitrary host paths. Bind mounts directly expose a selected host path and are prohibited for the two mandatory persistent stores. This project relocates the dedicated Docker daemon data root under `/home/<login>/data/docker`, so the named-volume data remains under `/home/<login>/data` without converting the volumes into bind mounts.

## Instructions

Use a dedicated Debian VM with systemd, a local rootful Docker Engine, Docker Compose v2, `jq`, OpenSSL, `flock`, and GNU core utilities. The host bootstrap deliberately refuses a daemon containing existing containers, images, volumes, or custom networks because silently migrating unrelated Docker state would be unsafe.

```sh
make configure LOGIN=kyanagis
make host-setup LOGIN=kyanagis
make check
make
make test
```

Open the HTTPS URL configured by `DOMAIN_NAME` in `srcs/.env` and accept the locally generated certificate only after verifying its fingerprint. The administration panel is at `/wp-admin/`. Credentials are created in the ignored `secrets/` directory; do not copy them into tickets, logs, shell history, or Git.

Useful commands:

```sh
make help          # command summary
make check         # offline/static repository checks
make doctor        # host and persistent-storage checks
make build         # build mandatory images only
make up            # start the mandatory stack
make bonus         # start mandatory and bonus services
make test          # running mandatory-stack integration tests
make status        # container and health status
make logs          # follow bounded container logs
make down          # remove containers/networks, retain data
make fclean        # destructive: remove project images and volume data
```

Detailed end-user instructions are in `USER_DOC.md`; setup, architecture, validation, backup, and recovery procedures are in `DEV_DOC.md`.

## Resources

- [Docker Engine documentation](https://docs.docker.com/engine/)
- [Docker Compose documentation](https://docs.docker.com/compose/)
- [Docker storage volumes](https://docs.docker.com/engine/storage/volumes/)
- [Docker secrets in Compose](https://docs.docker.com/compose/how-tos/use-secrets/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [MariaDB Server documentation](https://mariadb.com/kb/en/documentation/)
- [WordPress developer resources](https://developer.wordpress.org/)
- [PHP-FPM configuration](https://www.php.net/manual/en/install.fpm.configuration.php)
- [Mozilla TLS configuration guidance](https://ssl-config.mozilla.org/)
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)

AI was used as a review and drafting aid for requirements traceability, shell and Compose review, threat-oriented edge-case analysis, documentation structure, and test design. Version and checksum claims were independently checked against downloaded upstream artifacts, generated changes were reviewed against the subject, and local static checks were executed. AI was not treated as an authority or as a substitute for peer review, runtime validation in the target VM, or human accountability.
