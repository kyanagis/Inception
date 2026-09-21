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
      ./tooling.nix
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
    machine.succeed("for cmd in jq python3 ip shellcheck git make curl openssl nmap tcpdump inception-evaluate inception-audit; do command -v \"$cmd\"; done")
    machine.succeed("inception-evaluate --help")
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
    machine.fail("test -e /home/${userName}/Inception")
    machine.succeed("test $(readlink /home/${userName}/data) = /var/lib/inception/bootstrap-data")
    machine.succeed("rm /home/${userName}/data && mkdir /home/${userName}/data")
    machine.fail("inception-apply-login rejected")
    machine.fail("test -e /var/lib/inception/login")
    machine.fail("test -e /var/lib/inception/environment")
    machine.succeed("rmdir /home/${userName}/data && ln -s /var/lib/inception/bootstrap-data /home/${userName}/data && chown -h ${userName}:users /home/${userName}/data")
    machine.succeed("test $(hostname) = ${hostName}")
    machine.succeed("inception-apply-login peer42")
    machine.succeed("test -d /home/peer42/data")
    machine.succeed("test $(stat -c %U /home/peer42/data) = ${userName}")
    machine.succeed("test $(readlink /home/${userName}/data) = /home/peer42/data")
    machine.succeed("test $(readlink -f $(docker info --format '{{.DockerRootDir}}')) = /home/peer42/data/docker")
    machine.succeed("grep -Fx INCEPTION_LOGIN=peer42 /var/lib/inception/environment")
    machine.succeed("grep -Fx DOMAIN_NAME=peer42.42.fr /var/lib/inception/environment")
    machine.succeed("test $(hostname) = peer42.42.fr")
    machine.succeed("getent hosts peer42.42.fr")
    machine.succeed("inception-audit")
  '';
}
