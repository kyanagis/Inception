#!/bin/sh
set -eu

read_secret() {
  [ -r "$1" ] || { echo "Missing secret: $1" >&2; exit 1; }
  value=$(tr -d '\r\n' < "$1")
  [ -n "$value" ] || { echo "Empty secret: $1" >&2; exit 1; }
  printf '%s' "$value"
}

if [ "${1:-}" != "proftpd" ]; then
  exec "$@"
fi

: "${FTP_USER:?FTP_USER is required}"
: "${FTP_PASV_MIN_PORT:?FTP_PASV_MIN_PORT is required}"
: "${FTP_PASV_MAX_PORT:?FTP_PASV_MAX_PORT is required}"
case "$FTP_USER" in ''|*[!A-Za-z0-9_-]*) echo "Invalid FTP_USER" >&2; exit 2;; esac
case "$FTP_PASV_MIN_PORT:$FTP_PASV_MAX_PORT" in *[!0-9:]*) echo "Invalid passive port range" >&2; exit 2;; esac

password=$(read_secret /run/secrets/ftp_password)
password_hash=$(printf '%s' "$password" | openssl passwd -6 -stdin)
unset password

install -d -m 0700 /run/proftpd
printf '%s:%s:33:33:WordPress files:/srv/wordpress:/usr/sbin/nologin\n' \
  "$FTP_USER" "$password_hash" > /run/proftpd/ftpd.passwd
printf 'ftpusers:x:33:%s\n' "$FTP_USER" > /run/proftpd/ftpd.group
chmod 0600 /run/proftpd/ftpd.passwd /run/proftpd/ftpd.group
unset password_hash

cat > /tmp/proftpd.conf <<EOF
ServerName "Inception FTPS"
ServerType standalone
DefaultServer on
UseIPv6 off
Port 2121
Umask 022
MaxInstances 20
User nobody
Group nogroup
PidFile /run/proftpd/proftpd.pid
ScoreboardFile /run/proftpd/proftpd.scoreboard
SystemLog /run/proftpd/proftpd.log
TransferLog /run/proftpd/proftpd-xfer.log
ControlsEngine off
DelayEngine off
UseReverseDNS off
RequireValidShell off
DefaultRoot ~
AuthOrder mod_auth_file.c
AuthUserFile /run/proftpd/ftpd.passwd
AuthGroupFile /run/proftpd/ftpd.group
PassivePorts ${FTP_PASV_MIN_PORT} ${FTP_PASV_MAX_PORT}
AllowOverwrite on
LoadModule mod_tls.c
TLSEngine on
TLSRequired on
TLSProtocol TLSv1.2 TLSv1.3
TLSCipherSuite ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256
TLSECCertificateFile /run/secrets/tls_certificate
TLSECCertificateKeyFile /run/secrets/tls_private_key
TLSOptions NoSessionReuseRequired
TLSLog /run/proftpd/proftpd-tls.log
EOF

exec "$@"
