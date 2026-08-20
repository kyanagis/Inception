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

  applyLogin = pkgs.writeShellApplication {
    name = "inception-apply-login";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
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

      install -d -m 0755 "$state_directory"
      install -d -m 0750 -o ${userName} -g users "/home/$login" "$data_directory"

      environment_file="$state_directory/environment.new"
      printf '%s\n' \
        "INCEPTION_LOGIN=$login" \
        "DOMAIN_NAME=$domain" \
        "INCEPTION_DATA_DIR=$data_directory" > "$environment_file"
      chmod 0644 "$environment_file"
      mv -f "$environment_file" "$state_directory/environment"

      printf '%s\n' "$login" > "$state_directory/login"
      chmod 0644 "$state_directory/login"

      if [ -e "$bootstrap_home/data" ] && [ ! -L "$bootstrap_home/data" ]; then
        echo "$bootstrap_home/data exists and is not a symlink; refusing to replace it" >&2
        exit 3
      fi
      ln -sfn "$data_directory" "$bootstrap_home/data"
      chown -h ${userName}:users "$bootstrap_home/data"

      # nss-myhostname resolves the transient FQDN to this VM, so the required
      # <login>.42.fr address works locally without modifying immutable /etc/hosts.
      printf '%s\n' "$domain" > /proc/sys/kernel/hostname

      printf 'Configured 42 login: %s\nDomain: %s\nData: %s\n' \
        "$login" "$domain" "$data_directory"
    '';
  };

  setupLogin = pkgs.writeShellApplication {
    name = "inception-setup";
    runtimeInputs = with pkgs; [
      kdePackages.kdialog
      sudo
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

            if output="$(sudo ${applyLogin}/bin/inception-apply-login "$login" 2>&1)"; then
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
in
{
  networking = {
    inherit hostName;
    firewall.allowedTCPPorts = [
      22
      443
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
    mutableUsers = false;
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

  security.sudo.wheelNeedsPassword = false;
  services.getty.autologinUser = userName;
  services.displayManager.autoLogin = {
    enable = true;
    user = userName;
  };

  systemd = {
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
    setupLogin
    openssl
    vim
  ];

  system.stateVersion = "26.05";
}
