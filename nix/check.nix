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
    machine.wait_for_unit("sshd.service")
    machine.succeed("id ${userName}")
    machine.succeed("su - ${userName} -c 'docker info >/dev/null'")
    machine.succeed("su - ${userName} -c 'docker compose version'")
    machine.succeed("command -v ssh-setup")
    machine.succeed("sshd -T | grep -Fxi 'passwordauthentication no'")
    machine.succeed("sshd -T | grep -Fxi 'kbdinteractiveauthentication no'")
    machine.succeed("sshd -T | grep -Fxi 'permitrootlogin no'")
    machine.succeed("sshd -T | grep -Fxi 'x11forwarding no'")
    machine.succeed("sshd -T | grep -Fxi 'allowusers ${userName}'")
    machine.succeed("printf 'not-a-public-key\\n' > /home/${userName}/invalid.pub")
    machine.fail("su - ${userName} -c 'ssh-setup /home/${userName}/invalid.pub'")
    machine.fail("test -e /home/${userName}/.ssh/authorized_keys")
    machine.succeed("runuser -u ${userName} -- ssh-keygen -q -t ed25519 -N \"\" -f /home/${userName}/client-key")
    machine.succeed("su - ${userName} -c 'ssh-setup /home/${userName}/client-key.pub'")
    machine.succeed("su - ${userName} -c 'cat /home/${userName}/client-key.pub | ssh-setup'")
    machine.succeed("test $(grep -c '^ssh-ed25519 ' /home/${userName}/.ssh/authorized_keys) = 1")
    machine.succeed("test $(stat -c %a /home/${userName}/.ssh) = 700")
    machine.succeed("test $(stat -c %a /home/${userName}/.ssh/authorized_keys) = 600")
    machine.succeed("su - ${userName} -c 'ssh-setup --status'")
    machine.succeed("su - ${userName} -c 'ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/inception-known-hosts -i /home/${userName}/client-key ${userName}@127.0.0.1 true'")
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
