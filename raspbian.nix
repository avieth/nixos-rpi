# TODO must elaborate on this.
# Should take the raspbian image from the internet, extract the files we want
# from its partitions:
# - /boot
# - /lib/firmware
# - /lib/modules
# and then patch the firmware as usual.
# Can we do this without mounting?
{ pkgs }:
let
  kernel = pkgs.stdenv.mkDerivation rec {
    name = "raspbian-kernel";
    version = "bullseye-2022-09-22";
    # TODO fixup
    src = ./raspbian-${version};
    buildCommand = ''

      # Copy here so we can overwrite stuff
      cp -r $src/lib ./

      # No idea why I have to do this but apparently I do.
      chmod -R ug+w ./

      # raspbian has some weird symlink chains from /lib/firmware to
      # /etc/alternatives and back to /lib/firmware. All we need is this
      # one, which makes the brcmfmac chip work
      cp --remove-destination ./lib/firmware/cypress/cyfmac43455-sdio-standard.bin ./lib/firmware/brcm/brcmfmac43455-sdio.bin
      cp --remove-destination ./lib/firmware/regulatory.db-debian ./lib/firmware/regulatory.db
      cp --remove-destination ./lib/firmware/regulatory.db.p7s-debian ./lib/firmware/regulatory.db.p7s

      mkdir -p $out/lib
      cp -r ./lib $out
      cp -r $src/boot $out

    '';
  };
in
  kernel
