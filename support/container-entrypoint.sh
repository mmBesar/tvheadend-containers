#!/bin/sh
# container-entrypoint.sh
#
# Handles PUID, PGID, TZ, device group membership, and first-run ACL
# before exec'ing tvheadend. Runs as root via tini, drops privileges after.
#
# Env vars:
#   PUID  — UID to run as (default: 1000)
#   PGID  — GID to run as (default: 1000)
#   TZ    — timezone name (default: UTC)
set -eu

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# ── Timezone ──────────────────────────────────────────────────────────────────
if [ -n "${TZ:-}" ]; then
    ZONE_FILE="/usr/share/zoneinfo/${TZ}"
    if [ -f "$ZONE_FILE" ]; then
        ln -snf "$ZONE_FILE" /etc/localtime
        echo "$TZ" > /etc/timezone
    else
        echo "[init] WARNING: unknown timezone '${TZ}', falling back to UTC" >&2
    fi
fi

# ── PUID / PGID remapping ─────────────────────────────────────────────────────
CURRENT_UID=$(id -u tvheadend)
CURRENT_GID=$(id -g tvheadend)

if [ "$PGID" != "$CURRENT_GID" ]; then
    groupmod -o -g "$PGID" tvheadend
fi

if [ "$PUID" != "$CURRENT_UID" ]; then
    usermod -o -u "$PUID" tvheadend
fi

# ── Device group membership ───────────────────────────────────────────────────
# Walk every actual device node under /dev/dvb and /dev/dri and ensure
# tvheadend is a member of whichever group owns each device.
# (The parent directory GID is often root and meaningless — the devices
# themselves carry the real restricting GID.)
for DEV in $(find /dev/dvb /dev/dri -type c 2>/dev/null); do
    DEV_GID=$(stat -c '%g' "$DEV")
    # Skip GID 0 (root-owned devices — no group restriction)
    [ "$DEV_GID" = "0" ] && continue
    # Already a member? Skip.
    id -G tvheadend | tr ' ' '\n' | grep -qx "$DEV_GID" && continue
    # Create a group for this GID if none exists yet
    getent group "$DEV_GID" > /dev/null 2>&1 \
        || addgroup -S -g "$DEV_GID" "devgrp${DEV_GID}"
    DEV_GROUP=$(getent group "$DEV_GID" | cut -d: -f1)
    adduser tvheadend "$DEV_GROUP" 2>/dev/null || true
    echo "[init] added tvheadend to group '${DEV_GROUP}' (gid=${DEV_GID}) for ${DEV}"
done

# ── Fix ownership on data directories ────────────────────────────────────────
chown -R tvheadend:tvheadend \
    /var/lib/tvheadend \
    /var/log/tvheadend

echo "[init] uid=$(id -u tvheadend) gid=$(id -g tvheadend) tz=${TZ:-UTC}"

# ── First-run detection ───────────────────────────────────────────────────────
# If there is no accesscontrol config yet, pass --noacl so TVHeadend starts
# with open access (matching the old LinuxServer behavior). Once you save
# any access rule in the WebUI the file appears and --noacl is no longer added.
TVH_EXTRA_FLAGS=""
if [ ! -f /var/lib/tvheadend/accesscontrol/a* ] 2>/dev/null \
   && [ -z "$(ls /var/lib/tvheadend/accesscontrol/ 2>/dev/null)" ]; then
    echo "[init] No accesscontrol config found — starting with --noacl (open access)"
    TVH_EXTRA_FLAGS="--noacl"
fi

# ── Drop privileges and exec tvheadend ───────────────────────────────────────
exec su-exec tvheadend tvheadend \
    --config /var/lib/tvheadend \
    --http_port 9981 \
    --htsp_port 9982 \
    $TVH_EXTRA_FLAGS \
    "$@"
