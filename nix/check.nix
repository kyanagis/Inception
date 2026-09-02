# References:
# - NixOS tests: https://nixos.org/manual/nixos/stable/#sec-nixos-tests

{
  hostName,
  pkgs,
  userName,
}:

let
  projectSource = builtins.path {
    path = ../.;
    name = "inception-test-project-source";
    filter =
      path: type:
      let
        base = builtins.baseNameOf path;
      in
      base != ".git" && base != "secrets" && base != "result" && !(pkgs.lib.hasPrefix "result-" base);
  };
in
pkgs.testers.runNixOSTest {
  name = "inception-vm";

  requiredFeatures = {
    kvm = false;
    nixos-test = false;
  };

  nodes.machine = {
    imports = [
      (import ./base.nix {
        inherit hostName userName;
        allowUnfree = false;
        inherit projectSource;
      })
    ];
    virtualisation.memorySize = 1024;
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("docker.service")
    machine.succeed("id ${userName}")
    machine.succeed("su - ${userName} -c 'docker info >/dev/null'")
    machine.succeed("su - ${userName} -c 'docker compose version'")
    machine.succeed("test -x /home/${userName}/Inception/scripts/setup.sh")
    machine.succeed("mkdir /home/${userName}/data")
    machine.fail("inception-apply-login rejected")
    machine.fail("test -e /var/lib/inception/login")
    machine.fail("test -e /var/lib/inception/environment")
    machine.succeed("rmdir /home/${userName}/data")
    machine.succeed("chmod 000 /home/${userName}/Inception/scripts/setup.sh")
    machine.fail("inception-apply-login rejected")
    machine.fail("test -e /var/lib/inception/login")
    machine.fail("test -e /var/lib/inception/environment")
    machine.fail("test -e /home/${userName}/data")
    machine.succeed("test $(hostname) = ${hostName}")
    machine.succeed("chmod 0755 /home/${userName}/Inception/scripts/setup.sh")
    machine.succeed("inception-apply-login peer42")
    machine.succeed("test -d /home/peer42/data")
    machine.succeed("test $(stat -c %U /home/peer42/data) = ${userName}")
    machine.succeed("test $(readlink /home/${userName}/data) = /home/peer42/data")
    machine.succeed("grep -Fx INCEPTION_LOGIN=peer42 /var/lib/inception/environment")
    machine.succeed("grep -Fx DOMAIN_NAME=peer42.42.fr /var/lib/inception/environment")
    machine.succeed("test $(hostname) = peer42.42.fr")
    machine.succeed("getent hosts peer42.42.fr")
    machine.succeed("grep -Fx DOMAIN_NAME=peer42.42.fr /home/${userName}/Inception/srcs/.env")
    machine.succeed("test -s /home/${userName}/Inception/secrets/db_password.txt")
    machine.succeed("su - ${userName} -c 'cd /home/${userName}/Inception && make check'")
  '';
}
