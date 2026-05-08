#!/bin/sh
# Called by udev when the Garmin appears as 091e:0003 (after mode switch).
# Mounts via MTP (jmtpfs) then asks the server to copy + import FIT files.
export HOME=/root
LOG=/tmp/garmin_import.log
exec >> "$LOG" 2>&1
echo "$(date) === garmin_import.sh starting ==="

MOUNT=/mnt/garmin
mkdir -p "$MOUNT"

# Give the device a moment to settle after re-enumeration
sleep 2

echo "$(date) Attempting MTP mount..."
jmtpfs "$MOUNT" 2>&1
RC=$?
echo "$(date) jmtpfs exit code: $RC"

if [ $RC -ne 0 ]; then
    echo "$(date) Retrying after 3s..."
    sleep 3
    jmtpfs "$MOUNT" 2>&1
    RC=$?
    echo "$(date) jmtpfs retry exit code: $RC"
fi

if [ $RC -ne 0 ]; then
    echo "$(date) MTP mount failed"
    exit 1
fi

echo "$(date) Mounted. Contents:"
ls -la "$MOUNT"/ 2>&1 | head -20

echo "$(date) Triggering server import..."
curl -sf -X POST http://localhost:5001/health-data/import/usb-garmin \
     -H 'Content-Type: application/json' \
     -d '{"mount_path": "'"$MOUNT"'"}'
echo ""
echo "$(date) === done ==="
