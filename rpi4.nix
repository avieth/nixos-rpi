{ hostName ? "nixos-rpi4", configuration ? ./rpi4-configuration.nix }:
let

  # rpi-cross branch.
  # Includes cross compilation fixes for dbus-python and polkit.
  # Also has the hack to cut out the kernel from the toplevel system config.
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/avieth/nixpkgs/archive/11c189a23838f27644fc7070c0317cd90f5f3b4d.tar.gz";
    sha256 = "0fdrkz94gqs6kqsxr5vdphw725f7bjw8k97wkri20lfzpxkj6hzb";
  };
  # FIXME better way to do this?
  nixpkgsPath = subpath: builtins.toPath (builtins.toString nixpkgs + subpath);
  nixos = nixpkgsPath "/nixos";

  # Impsoe some config common to both the initial and update.
  withCommonConfig = { pkgs, lib, ... }: baseConfig: baseConfig // {
    imports = baseConfig.imports ++ [configuration];
    nix.package = pkgs.nix_2_7;
    networking.hostName = hostName;

    # First step: come up with a stub kernel that most of the nixos infrastructure
    # is happy to deal with.
    # FIXME remaining problems;
    # - The assertions in nixos/modules/system/boot/raspbian.nix
    # - The systemBuilder in nixos/modules/system/activation/top-level.nix must
    #   be made to not use the kernel, or this stub be made to provide what it
    #   needs.
    boot.kernelPackages =
      let kernel = import ./raspbian.nix { inherit pkgs; };
          overridable = lib.makeOverridable (_: kernel) {};
          extensible = _self: { kernel = overridable; };
      in  lib.makeExtensible extensible;

  };

  # Disk stuff, so we can adjust the kernel command line to find the
  # root disk and the init program.
  diskId = "ffffffff"; # We choose the disk identifier so that we can know the kernel command line root value.
  partNo = "02"; # Root is partition 2 (see sdImage definition).
  partuuid = "${diskId}-${partNo}"; # MBR partition identifier scheme

  # Note about the bootloader:
  #
  # Thought it might be a good idea to have an installBootLoader which updates
  # the cmdline.txt with the new init. No good, since the new init depends upon
  # the bootloader as part of system.build.toplevel
  #
  # Instead, we'll have no boot loader install after the initial SD card image
  # creation. It'll always point to initSymlink (defined below), and we'll
  # update this symlink part of system activation (see activate-rpi.nix)
  initSymlink = "/nixos-rpi-init";
  cmdline = "console=serial0,115200 console=tty1 root=PARTUUID=${partuuid} rootfstype=ext4 fsck.repair=yes rootwait init=${initSymlink}";

  initial = rec {
    configuration = { config, pkgs, ... }@args: withCommonConfig args {
      imports = [
        (nixpkgsPath "/nixos/modules/installer/sd-card/sd-image.nix")
      ];
      sdImage = {
        compressImage = false;
        inherit diskId;
        firmwarePartitionOffset = 8;
        firmwareSize = 256;
        rootPartitionUUID = "44444444-4444-4444-8888-888888888888";
        # Assumes that the config is set to use the raspbian "kernel" derivation
        # but maybe we should just explicitly take it here.
        # FIXME must patch the cmdline.txt root=PARTUUID
        # 
        populateFirmwareCommands = ''
          echo "Populate firmware"
          cp -r ${config.boot.kernelPackages.kernel}/boot/* firmware
          # Overwrite existing command line.
          chmod ug+w firmware/cmdline.txt
          echo "${cmdline}" > firmware/cmdline.txt
        '';
        # Copy over the /lib directory, which has the kernel modules and
        # firmware from the working raspbian distribution.
        populateRootCommands = ''
          echo "Populate root"
          cp -r ${config.boot.kernelPackages.kernel}/lib ./files

          # raspbian has some weird symlink chains from /lib/firmware to
          # /etc/alternatives and back to /lib/firmware. All we need is this
          # one, which makes the brcmfmac chip work
          #rm files/lib/firmware/brcm/brcmfmac43455-sdio.bin
          #cp files/lib/firmware/cypress/cyfmac43455-sdio-standard.bin files/lib/firmware/brcm/brcmfmac43455-sdio.bin
        '';
      };
    };
    evaluation = import nixos { inherit configuration; };
  };

  update = rec {
    configuration = { pkgs, ... }@args: withCommonConfig args {
      imports = [];
      fileSystems = {
        "/" = {
          fsType = "ext4";
          device = "/dev/disk/by-uuid/${initial.evaluation.config.sdImage.rootPartitionUUID}";
        };
        "/boot" = {
          fsType = "vfat";
          device = "/dev/disk/by-label/${initial.evaluation.config.sdImage.firmwarePartitionName}";
          options = [ "ro" ];
          depends = [ "/" ];
        };
      };
    };
    evaluation = import nixos { inherit configuration; };
  };

in {
  initial = initial.evaluation.config.system.build.sdImage;
  update = import ./activate-rpi.nix {
    system = update.evaluation.config.system.build.toplevel;
    inherit initSymlink;
    mkScript = update.evaluation.pkgs.writeShellScript;
  };
  kernel = (import nixos { inherit (initial) configuration; }).config.boot.kernelPackages.kernel;
  raspbian = (import nixpkgs {}).callPackage ./raspbian.nix {};
}
