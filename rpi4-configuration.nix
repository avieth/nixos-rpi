{ pkgs, lib, ... }: {

  nixpkgs.crossSystem = { config = "aarch64-unknown-linux-gnu"; };

  nixpkgs.overlays = [
    # Must use bluez-5.55, which the version found on raspbian bullseye 2022-09-22.
    # 5.63 was found not to work.
    (self: super: {
      bluez = super.bluez.overrideAttrs (_: {
        version = "5.55";
        src = pkgs.fetchurl {
          url = "mirror://kernel/linux/bluetooth/bluez-5.55.tar.xz";
          sha256 = "124v9s4y1s7s6klx5vlmzpk1jlr4x84ch7r7scm7x2f42dqp2qw8";
        };
      });
    })
  ];

  # We don't want a bootloader; it's already there.
  # The activation script will print a warning, but that's fine.
  system.build.installBootloader = false;
  boot.loader.grub.enable = false;
  boot.loader.raspberryPi.enable = false;
  boot.loader.generic-extlinux-compatible.enable = false;
  boot.loader.systemd-boot.enable = false;

  boot.kernelModules = [
    "hci_uart"
    "bluetooth"
    "btusb"
    "btbcm"
    "bnep"
  ];

  # TODO relocate everything else.
  users.mutableUsers = true;
  users.users.root.initialPassword = "root";
  services.openssh = {
    enable = true;
    permitRootLogin = "yes";
    passwordAuthentication = true;
  };
  systemd.services.sshd.wantedBy = [ "multi-user.target" ];

  networking = {
    useDHCP = true;
    # Default is a wired setup, but wireless works fine if you want that.
    wireless = { enable = false; };
    firewall = {
      enable = true;
      trustedInterfaces = [
        "eth0"
      ];
    };
  };

  # Adjust the allowedIpRanges and the extraConfig for your own network and
  # pulseaudio configuration. The module-tunnel-sink is useful if you want to
  # send the audio to a machine that has a better sound device, since rumour has
  # it the one on the pi isn't very good.
  hardware.pulseaudio = {
    enable = true;
    tcp = {
      enable = true;
      anonymousClients = {
        allowedIpRanges = [
          "127.0.0.1"
          "192.168.1.0/24"
        ];
      };
    };
    systemWide = true;
    extraConfig = ''
      load-module module-tunnel-sink server=192.168.1.2 sink=bt-guest
    '';
  };

  hardware.bluetooth = {
    enable = true;
  };
  systemd.services.bluetooth-hciattach = {
    # FIXME better wantedBy definition?
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      # TODO is it possible to "unattach"?
      ExecStart = pkgs.callPackage ./btuart.nix { mkScript = pkgs.writeShellScript; };
      # Not exactly sure why, but oneshot won't work. Best guess is that the
      # hciattach program somehow stops working if the shell which spawned it
      # vanishes?
      Type = "forking";
    };
  };

  # Since I won't be using 802.11, I'll turn off the power for wlan0.
  # iwconfig is made available by wirelesstools in systemPackages.
  networking.localCommands = ''
    iwconfig wlan0 power off
    iwconfig wlan0 txpower off
  '';

  services.xserver.enable = false;

  environment.systemPackages = with pkgs; [
    vim
    wirelesstools
  ];

}
