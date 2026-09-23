# References:
# - NixOS Docker: https://wiki.nixos.org/wiki/Docker
# - NixOS user management: https://nixos.org/manual/nixos/stable/#sec-user-management

{
  allowUnfree ? false,
  hostName,
  userName,
}:
{
  lib,
  pkgs,
  ...
}:

let
  loginStateDirectory = "/var/lib/inception";

  # Docker serializes its data-root verbatim in `docker volume inspect`.
  # It must therefore be the learner path itself, rather than a stable path
  # which happens to resolve through a symlink.  The service wrapper reads the
  # root prepared by inception-docker-data-link before every daemon start.
  dockerDaemon = pkgs.writeShellApplication {
    name = "inception-dockerd";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail

      state_directory=${loginStateDirectory}
      fallback_root="$state_directory/bootstrap-data/docker"
      root_file="$state_directory/docker-data-root"
      docker_root="$fallback_root"
      if [[ -s "$root_file" ]]; then
        docker_root="$(<"$root_file")"
      fi

      case "$docker_root" in
        "$fallback_root"|/home/[a-z]/data/docker|/home/[a-z][a-z0-9-]*/data/docker)
          ;;
        *)
          echo "Refusing invalid Inception Docker data-root: $docker_root" >&2
          exit 2
          ;;
      esac

      install -d -o root -g root -m 0710 "$docker_root"
      exec ${pkgs.docker}/bin/dockerd --data-root "$docker_root"
    '';
  };

  applyLogin = pkgs.writeShellApplication {
    name = "inception-apply-login";
    runtimeInputs = with pkgs; [
      coreutils
      docker
      gnugrep
      openssl
      systemd
      util-linux
    ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "inception-apply-login must run as root" >&2
        exit 1
      fi

      login="''${1:-}"
      if ! [[ "$login" =~ ^[a-z][a-z0-9-]{0,30}[a-z0-9]$|^[a-z]$ ]]; then
        echo "42 login must use lowercase letters, digits, and internal hyphens (maximum 32 characters)" >&2
        exit 2
      fi

      case "$login" in
        root|inception)
          echo "'$login' is reserved; enter your own 42 login" >&2
          exit 2
          ;;
      esac

      domain="$login.42.fr"
      data_directory="/home/$login/data"
      state_directory=${loginStateDirectory}
      bootstrap_home=/home/${userName}

      # Validate every condition that can be checked without changing state.
      # The login file is the completion marker used by the GUI autostart, so
      # it must never be written before the complete setup succeeds.
      if [ -e "$bootstrap_home/data" ] && [ ! -L "$bootstrap_home/data" ]; then
        echo "$bootstrap_home/data exists and is not a symlink; refusing to replace it" >&2
        exit 3
      fi

      install -d -m 0755 "$state_directory"
      install -d -m 0750 -o ${userName} -g users "/home/$login" "$data_directory"

      docker_target="$data_directory/docker"
      current_link=$(readlink "$bootstrap_home/data" || true)
      current_root=$(docker info --format '{{.DockerRootDir}}')
      if [ "$current_link" != "$data_directory" ] || [ "$current_root" != "$docker_target" ]; then
        [ -z "$(docker ps -aq)" ] || { echo "Docker has containers; refusing data-root switch" >&2; exit 3; }
        [ -z "$(docker volume ls -q)" ] || { echo "Docker has volumes; refusing data-root switch" >&2; exit 3; }
        [ -z "$(docker image ls -q)" ] || { echo "Docker has images; refusing data-root switch" >&2; exit 3; }
        install -d -o root -g root -m 0710 "$docker_target"
        root_file="$state_directory/docker-data-root"
        previous_root=$(cat "$root_file" 2>/dev/null || printf '%s' "$state_directory/bootstrap-data/docker")
        root_file_new="$root_file.new"
        printf '%s\n' "$docker_target" > "$root_file_new"
        chmod 0600 "$root_file_new"
        systemctl stop docker.service docker.socket
        rm -f "$bootstrap_home/data"
        ln -s "$data_directory" "$bootstrap_home/data"
        chown -h ${userName}:users "$bootstrap_home/data"
        mv -f "$root_file_new" "$root_file"
        if ! systemctl start docker.socket docker.service ||
           [ "$(docker info --format '{{.DockerRootDir}}')" != "$docker_target" ]; then
          systemctl stop docker.service docker.socket || true
          rm -f "$bootstrap_home/data"
          ln -s ${loginStateDirectory}/bootstrap-data "$bootstrap_home/data"
          chown -h ${userName}:users "$bootstrap_home/data"
          printf '%s\n' "$previous_root" > "$root_file_new"
          chmod 0600 "$root_file_new"
          mv -f "$root_file_new" "$root_file"
          systemctl start docker.socket docker.service || true
          echo "Docker data-root switch failed and was rolled back" >&2
          exit 4
        fi
      fi

      # nss-myhostname resolves the transient FQDN to this VM, so the required
      # <login>.42.fr address works locally without modifying immutable /etc/hosts.
      printf '%s\n' "$domain" > /proc/sys/kernel/hostname

      environment_file="$state_directory/environment.new"
      login_file="$state_directory/login.new"
      trap 'rm -f "$environment_file" "$login_file"' EXIT HUP INT TERM
      printf '%s\n' \
        "INCEPTION_LOGIN=$login" \
        "DOMAIN_NAME=$domain" \
        "INCEPTION_DATA_DIR=$data_directory" > "$environment_file"
      printf '%s\n' "$login" > "$login_file"
      chmod 0644 "$environment_file" "$login_file"
      mv -f "$environment_file" "$state_directory/environment"
      # Commit the completion marker last.  --first-login only skips setup
      # after this final rename has succeeded.
      mv -f "$login_file" "$state_directory/login"
      trap - EXIT HUP INT TERM

      printf 'Configured 42 login: %s\nDomain: %s\nData: %s\n' \
        "$login" "$domain" "$data_directory"
    '';
  };

  setupLogin = pkgs.writeShellApplication {
    name = "inception-setup";
    runtimeInputs = with pkgs; [
      kdePackages.kdialog
    ];
    text = ''
            first_login=0
            if [ "''${1:-}" = "--first-login" ]; then
              first_login=1
              shift
            fi

            if [ "$first_login" -eq 1 ] && [ -s ${loginStateDirectory}/login ]; then
              exit 0
            fi

            login="''${1:-}"
            graphical=0
            if [ -z "$login" ] && [ -n "''${DISPLAY:-}''${WAYLAND_DISPLAY:-}" ]; then
              graphical=1
              login="$(kdialog \
                --title 'Inception VM setup' \
                --inputbox 'Enter your 42 login. It will configure /home/<login>/data and <login>.42.fr.' \
                2>/dev/null || true)"
            fi

            if [ -z "$login" ] && [ "$graphical" -eq 0 ]; then
              printf '42 login: '
              IFS= read -r login
            fi

            if [ -z "$login" ]; then
              exit 0
            fi

            # Nix store binaries cannot be setuid.  Use the NixOS runtime
            # wrapper explicitly: writeShellApplication places runtimeInputs
            # before /run/wrappers/bin in PATH, so an unqualified sudo here
            # would otherwise select the non-setuid store binary.
            if output="$(/run/wrappers/bin/sudo ${applyLogin}/bin/inception-apply-login "$login" 2>&1)"; then
              if [ "$graphical" -eq 1 ]; then
                kdialog --title 'Inception VM setup' --msgbox "$output

      Open a new terminal before using the exported environment variables."
              else
                printf '%s\n' "$output"
              fi
            else
              status=$?
              if [ "$graphical" -eq 1 ]; then
                kdialog --title 'Inception VM setup error' --error "$output"
              else
                printf '%s\n' "$output" >&2
              fi
              exit "$status"
            fi
    '';
  };

  sshSetup = pkgs.writeShellApplication {
    name = "ssh-setup";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      iproute2
      openssh
      systemd
    ];
    text = ''
      if [ "$(id -un)" != "${userName}" ]; then
        echo "ssh-setup must run as ${userName}, not as root or another user" >&2
        exit 1
      fi

      ssh_directory="$HOME/.ssh"
      authorized_keys="$ssh_directory/authorized_keys"

      show_status() {
        printf 'sshd: '
        systemctl is-active sshd.service || true
        if [ -s "$authorized_keys" ]; then
          echo "Authorized public keys:"
          ssh-keygen -lf "$authorized_keys" || true
        else
          echo "Authorized public keys: none"
        fi
        echo "VM addresses:"
        ip -brief address show scope global || true
      }

      case "''${1:-}" in
        --status)
          [ "$#" -eq 1 ] || { echo "Usage: ssh-setup --status" >&2; exit 2; }
          show_status
          exit 0
          ;;
        --help|-h)
          echo "Usage: ssh-setup [PUBLIC_KEY_FILE]"
          echo "       ssh-setup --status"
          exit 0
          ;;
      esac

      if [ "$#" -gt 1 ]; then
        echo "Usage: ssh-setup [PUBLIC_KEY_FILE]" >&2
        exit 2
      fi

      if [ "$#" -eq 1 ]; then
        [ -f "$1" ] && [ -r "$1" ] || { echo "Cannot read public key file: $1" >&2; exit 2; }
        mapfile -t public_key_lines < "$1"
        if [ "''${#public_key_lines[@]}" -ne 1 ]; then
          echo "The public key file must contain exactly one line" >&2
          exit 2
        fi
        public_key="''${public_key_lines[0]}"
      else
        echo "Paste one SSH public-key line, then press Enter:" >&2
        if ! IFS= read -r public_key; then
          echo "No public key was received" >&2
          exit 2
        fi
      fi
      public_key=$(printf '%s' "$public_key" | tr -d '\r')
      [ -n "$public_key" ] || { echo "The public key is empty" >&2; exit 2; }

      validation_file=$(mktemp)
      trap 'rm -f "$validation_file"' EXIT HUP INT TERM
      printf '%s\n' "$public_key" > "$validation_file"
      if ! fingerprint=$(ssh-keygen -lf "$validation_file" 2>/dev/null); then
        echo "Invalid SSH public key" >&2
        exit 2
      fi

      if [ -L "$ssh_directory" ] || [ -L "$authorized_keys" ]; then
        echo "Refusing to update a symlinked SSH directory or authorized_keys file" >&2
        exit 3
      fi
      install -d -m 0700 "$ssh_directory"
      candidate_file=$(mktemp "$ssh_directory/.authorized_keys.XXXXXX")
      if [ -f "$authorized_keys" ]; then
        cat "$authorized_keys" > "$candidate_file"
      fi
      if ! grep -Fqx -- "$public_key" "$candidate_file"; then
        printf '%s\n' "$public_key" >> "$candidate_file"
      fi
      chmod 0600 "$candidate_file"
      mv -f "$candidate_file" "$authorized_keys"
      rm -f "$validation_file"
      trap - EXIT HUP INT TERM

      printf 'SSH public key installed: %s\n' "$fingerprint"
      echo "Password and root SSH logins remain disabled."
      show_status
    '';
  };
in
{
  networking = {
    inherit hostName;
    firewall.allowedTCPPorts = [
      22
      443
      2121
    ];
    firewall.allowedTCPPortRanges = [
      {
        from = 21100;
        to = 21110;
      }
    ];
  };

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  nixpkgs.config = lib.mkIf allowUnfree {
    allowUnfree = true;
  };

  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  users = {
    mutableUsers = true;
    users.${userName} = {
      isNormalUser = true;
      description = userName;
      shell = pkgs.zsh;
      extraGroups = [
        "docker"
        "wheel"
      ];
      initialPassword = "inception";
    };
  };

  programs = {
    bash.interactiveShellInit = ''
      if [ -r ${loginStateDirectory}/environment ]; then
        set -a
        . ${loginStateDirectory}/environment
        set +a
      fi
    '';

    zsh = {
      enable = true;
      interactiveShellInit = ''
        if [ -r ${loginStateDirectory}/environment ]; then
          set -a
          . ${loginStateDirectory}/environment
          set +a
        fi
      '';
    };
  };

  security.sudo = {
    wheelNeedsPassword = true;
    extraRules = [
      {
        users = [ userName ];
        commands = [
          {
            command = "${applyLogin}/bin/inception-apply-login";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
  services.getty.autologinUser = userName;
  services.displayManager.autoLogin = {
    enable = true;
    user = userName;
  };
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
    };
    extraConfig = ''
      AllowUsers ${userName}
    '';
  };

  system.activationScripts.inception-login-state = lib.stringAfter [ "etc" ] ''
    if [ -s ${loginStateDirectory}/login ]; then
      login="$(cat ${loginStateDirectory}/login)"
      case "$login" in
        ""|[!a-z]*|*[!a-z0-9-]*|*-|root|inception)
          echo "Invalid persisted Inception login: $login" >&2
          exit 1
          ;;
      esac
      printf '%s\n' "$login.42.fr" > /proc/sys/kernel/hostname
    fi
  '';

  systemd = {
    services.inception-docker-data-link = {
      description = "Prepare the Docker data-root for the configured 42 login";
      requiredBy = [ "docker.service" ];
      before = [ "docker.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        install -d -o root -g root -m 0710 ${loginStateDirectory}/bootstrap-data/docker
        root_file=${loginStateDirectory}/docker-data-root
        fallback_root=${loginStateDirectory}/bootstrap-data/docker
        docker_root="$fallback_root"
        if [ -s ${loginStateDirectory}/login ]; then
          login="$(cat ${loginStateDirectory}/login)"
          case "$login" in
            [a-z]|[a-z][a-z0-9-]*[a-z0-9]) docker_root="/home/$login/data/docker" ;;
            *) echo "Invalid persisted Inception login: $login" >&2; exit 1 ;;
          esac
        fi
        install -d -o root -g root -m 0710 "$docker_root"
        if [ ! -r "$root_file" ] || [ "$(cat "$root_file")" != "$docker_root" ]; then
          root_file_new="$root_file.new"
          printf '%s\n' "$docker_root" > "$root_file_new"
          chmod 0600 "$root_file_new"
          mv -f "$root_file_new" "$root_file"
        fi
        if [ ! -e /home/${userName}/data ] && [ ! -L /home/${userName}/data ]; then
          ln -s ${loginStateDirectory}/bootstrap-data /home/${userName}/data
          chown -h ${userName}:users /home/${userName}/data
        fi
        test -L /home/${userName}/data
      '';
    };
    services.docker.serviceConfig.ExecStart = lib.mkForce [
      ""
      "${dockerDaemon}/bin/inception-dockerd"
    ];
    services.inception-login-state = {
      description = "Restore the configured Inception 42 login";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        if [ -s ${loginStateDirectory}/login ]; then
          login="$(cat ${loginStateDirectory}/login)"
          printf '%s\n' "$login.42.fr" > /proc/sys/kernel/hostname
        fi
      '';
    };

    tmpfiles.rules = [
      "d ${loginStateDirectory} 0755 root root -"
    ];
  };

  environment.etc."profile.d/inception-login.sh".text = ''
    if [ -r ${loginStateDirectory}/environment ]; then
      set -a
      . ${loginStateDirectory}/environment
      set +a
    fi
  '';

  environment.systemPackages = with pkgs; [
    applyLogin
    curl
    docker-compose
    git
    gnumake
    ripgrep
    setupLogin
    sshSetup
    openssl
    vim
  ];

  system.stateVersion = "26.05";
}
