# Copied from /usr/bin/btuart on raspbian.
# Will hciattach to get an hci0 device.
{ bluez, util-linux, mkScript }:
mkScript "btattach" ''
  HCIATTACH=${bluez}/bin/hciattach
  # Original script has this condition without the && but I found it would give
  # AA:AA:AA:AA:AA:AA as the address of my device so I made it never match.
  if grep -q "raspberrypi,4" /proc/device-tree/compatible && false; then
    BDADDR=
  else
    SERIAL=`cat /proc/device-tree/serial-number | cut -c9-`
    B1=`echo $SERIAL | cut -c3-4`
    B2=`echo $SERIAL | cut -c5-6`
    B3=`echo $SERIAL | cut -c7-8`
    BDADDR=`printf b8:27:eb:%02x:%02x:%02x $((0x$B1 ^ 0xaa)) $((0x$B2 ^ 0xaa)) $((0x$B3 ^ 0xaa))`
  fi

  echo "Address is $BDADDR"

  # Bail out if the kernel is managing the Bluetooth modem initialisation
  if ( ${util-linux}/bin/dmesg | grep -q -E "hci[0-9]+: BCM: chip" ); then
    # On-board bluetooth is already enabled
    echo "Bailing out"
    exit 0
  fi

  uart0="`cat /proc/device-tree/aliases/uart0`"
  serial1="`cat /proc/device-tree/aliases/serial1`"

  if [ "$uart0" = "$serial1" ] ; then
    uart0_pins="`wc -c /proc/device-tree/soc/gpio@7e200000/uart0_pins/brcm\,pins | cut -f 1 -d ' '`"
    if [ "$uart0_pins" = "16" ] ; then
      echo "High speed"
      # Modification from the original here: raspbian uses /dev/serial1 but
      # that device doesn't exist on NixOS so we use /dev/ttyAMA0
      # FIXME is that portable?
      $HCIATTACH /dev/ttyAMA0 bcm43xx 3000000 flow - $BDADDR
    else
      echo "Medium speed"
      $HCIATTACH /dev/ttyAMA0 bcm43xx 921600 noflow - $BDADDR
    fi
  else
    echo "Low speed"
    $HCIATTACH /dev/ttyAMA0 bcm43xx 460800 noflow - $BDADDR
  fi
''
