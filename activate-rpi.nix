# Run this script on the pi to switch to the new configuration.
#
# - system should be the config.system.build.toplevel derivation
# - initSymlink should be the path to the symlink which the kernel command line
#   points to (/boot/cmdline.txt)
# - mkScript: writeShellScript probably.
{ system, initSymlink, mkScript }:
mkScript "activate-rpi" ''
  ${system}/bin/switch-to-configuration switch
  rm ${initSymlink}
  ln -s ${system}/init ${initSymlink}
''
