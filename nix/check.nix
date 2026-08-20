# References:
# - NixOS tests: https://nixos.org/manual/nixos/stable/#sec-nixos-tests

{
  hostName,
  pkgs,
  userName,
}:

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
    machine.succeed("inception-apply-login peer42")
    machine.succeed("test -d /home/peer42/data")
    machine.succeed("test $(stat -c %U /home/peer42/data) = ${userName}")
    machine.succeed("test $(readlink /home/${userName}/data) = /home/peer42/data")
    machine.succeed("grep -Fx INCEPTION_LOGIN=peer42 /var/lib/inception/environment")
    machine.succeed("grep -Fx DOMAIN_NAME=peer42.42.fr /var/lib/inception/environment")
    machine.succeed("test $(hostname) = peer42.42.fr")
    machine.succeed("getent hosts peer42.42.fr")
  '';
}
