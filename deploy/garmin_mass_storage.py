#!/usr/bin/env python3
"""Send USB command to switch a Garmin device from vendor-specific mode to
USB mass storage mode.

Garmin watches (e.g. Instinct E) present with bInterfaceClass 0xff (vendor
specific) even when set to "Mass Storage" in the watch UI.  Sending the
magic packet 0x140000002f0400000100000000 over the bulk-out endpoint causes
the device to re-enumerate as a standard USB mass storage device.

Reference: https://github.com/Leberwurscht/vivosmart
           https://github.com/mormegil-cz/GarminUsbMassStorageMode

Must be run as root (or via udev which already runs as root).
"""

import binascii
import logging
import sys
import time

LOG_FILE = "/tmp/garmin_mass_storage.log"
GARMIN_VENDOR = 0x091E
MASS_STORAGE_CMD = "140000002f0400000100000000"

logging.basicConfig(
    filename=LOG_FILE,
    level=logging.DEBUG,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)


def switch_to_mass_storage(product_id=None):
    import usb.core

    kwargs = {"idVendor": GARMIN_VENDOR}
    if product_id is not None:
        kwargs["idProduct"] = product_id

    dev = usb.core.find(**kwargs)
    if dev is None:
        log.error("No Garmin device found")
        return False

    log.info("Found Garmin 0x%04x at bus %d dev %d", dev.idProduct, dev.bus, dev.address)

    iface = dev[0][(0, 0)]
    log.info(
        "Interface class=0x%02x subclass=0x%02x protocol=0x%02x",
        iface.bInterfaceClass,
        iface.bInterfaceSubClass,
        iface.bInterfaceProtocol,
    )

    if iface.bInterfaceClass != 0xFF:
        log.info("Device already in non-vendor mode (class=0x%02x), skipping", iface.bInterfaceClass)
        return True

    try:
        if dev.is_kernel_driver_active(0):
            log.info("Detaching kernel driver")
            dev.detach_kernel_driver(0)
    except usb.core.USBError as e:
        log.warning("Kernel driver detach: %s", e)

    try:
        dev.set_configuration()
        log.info("Configuration set")
    except usb.core.USBError as e:
        log.warning("set_configuration: %s", e)

    bulk_out = None
    for ep in iface:
        is_out = (ep.bEndpointAddress & 0x80) == 0
        is_bulk = (ep.bmAttributes & 3) == 2
        log.debug("  EP 0x%02x out=%s bulk=%s", ep.bEndpointAddress, is_out, is_bulk)
        if is_out and is_bulk:
            bulk_out = ep

    if bulk_out is None:
        log.error("No bulk-out endpoint found")
        return False

    log.info("Writing mass storage command to EP 0x%02x", bulk_out.bEndpointAddress)
    data = binascii.unhexlify(MASS_STORAGE_CMD)
    try:
        dev.write(bulk_out.bEndpointAddress, data)
        log.info("Command sent successfully")
    except usb.core.USBError as e:
        log.error("Write failed: %s", e)
        return False

    return True


if __name__ == "__main__":
    pid = int(sys.argv[1], 16) if len(sys.argv) > 1 else None
    log.info("=== garmin_mass_storage.py starting (pid_filter=%s) ===", pid)
    try:
        ok = switch_to_mass_storage(pid)
    except Exception:
        log.exception("Unhandled exception")
        ok = False
    log.info("=== done (success=%s) ===", ok)
    sys.exit(0 if ok else 1)
