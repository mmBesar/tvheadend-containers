#!/bin/sh
# container-entrypoint.sh
#
# Handles PUID, PGID, TZ, device group membership, and first-run ACL setup.
# Runs as root via tini, drops privileges to tvheadend user after setup.
#
# Env vars:
#   PUID  — UID to run as (default: 1000)
#   PGID  — GID to run as (default: 1000)
#   TZ    — timezone name (default: UTC)
set -eu

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
TVH_DATA="${TVHEADEND_DATA_DIR:-/var/lib/tvheadend}"

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
# Walk every actual device node under /dev/dvb and /dev/dri — the device nodes
# carry the real restricting GID, not the parent directory.
for DEV in $(find /dev/dvb /dev/dri -type c 2>/dev/null); do
    DEV_GID=$(stat -c '%g' "$DEV")
    [ "$DEV_GID" = "0" ] && continue
    id -G tvheadend | tr ' ' '\n' | grep -qx "$DEV_GID" && continue
    getent group "$DEV_GID" > /dev/null 2>&1 \
        || addgroup -S -g "$DEV_GID" "devgrp${DEV_GID}"
    DEV_GROUP=$(getent group "$DEV_GID" | cut -d: -f1)
    adduser tvheadend "$DEV_GROUP" 2>/dev/null || true
    echo "[init] added tvheadend to group '${DEV_GROUP}' (gid=${DEV_GID}) for ${DEV}"
done

# ── Fix ownership on data directories ────────────────────────────────────────
chown -R tvheadend:tvheadend \
    "${TVH_DATA}" \
    /var/log/tvheadend

# ── Streamlink — config file and auto sideloading ────────────────────────────
# Docs: https://streamlink.github.io/cli/config.html
#       https://streamlink.github.io/cli/plugin-sideloading.html
#
# For tvheadend user (HOME=/var/lib/tvheadend):
#   Config:       $HOME/.config/streamlink/config     (sets plugin-dir fallback)
#   Auto-sideload: $HOME/.local/share/streamlink/plugins  (scanned automatically)
#
# We symlink shipped plugins to the XDG data path so streamlink discovers them
# with zero CLI flags. Config file is a belt-and-braces fallback.
# Both are written on every start (idempotent).

# 1. Config file
STREAMLINK_CFG="${TVH_DATA}/.config/streamlink/config"
mkdir -p "$(dirname "$STREAMLINK_CFG")"
printf '# Streamlink config - managed by entrypoint\nplugin-dir=/usr/local/share/streamlink/plugins\n' > "$STREAMLINK_CFG"

# 2. XDG sideload path — symlink shipped plugins so streamlink auto-discovers them
STREAMLINK_PLUGINS="${TVH_DATA}/.local/share/streamlink/plugins"
mkdir -p "$STREAMLINK_PLUGINS"
for PLUGIN in /usr/local/share/streamlink/plugins/*.py; do
    ln -snf "$PLUGIN" "${STREAMLINK_PLUGINS}/$(basename "$PLUGIN")"
done

chown -R tvheadend:tvheadend "${TVH_DATA}/.config" "${TVH_DATA}/.local"
echo "[init] streamlink config: ${STREAMLINK_CFG}"
echo "[init] streamlink plugins symlinked: $(ls /usr/local/share/streamlink/plugins/)"

# ── First-run: create wildcard access entry (no authentication by default) ───
#
# Matches LinuxServer.io behaviour exactly:
#   - username "*" with prefix 0.0.0.0/0 = any user, any IP, no password needed
#   - Full admin + streaming + DVR rights
#   - To enable authentication: disable or delete this entry in the WebUI,
#     then create your own named user. That's it.
#
# We only create this if the accesscontrol directory is completely empty
# (genuine first run, not an existing install being migrated).
ACL_DIR="${TVH_DATA}/accesscontrol"
if [ ! -d "$ACL_DIR" ] || [ -z "$(ls -A "$ACL_DIR" 2>/dev/null)" ]; then
    echo "[init] First run — creating wildcard access entry (no auth required)"
    mkdir -p "$ACL_DIR"
    # UUID is static so it's idempotent if entrypoint runs twice
    cat > "${ACL_DIR}/4d1c5e2a9f0b3e8d7c6a1b2f4e3d5c9a" << 'ACLEOF'
{
    "index": 0,
    "enabled": true,
    "username": "*",
    "prefix": "0.0.0.0/0,::/0",
    "webui": true,
    "admin": true,
    "streaming": ["basic","advanced","htsp"],
    "dvr": ["basic","htsp","all","all_rw","failed"],
    "htsp_anonymize": false,
    "conn_limit_type": 0,
    "conn_limit": 0,
    "channel_min": 0,
    "channel_max": 0,
    "channel_tag_exclude": false,
    "comment": "Default open access — disable this entry to enable authentication"
}
ACLEOF
    chown -R tvheadend:tvheadend "$ACL_DIR"
    echo "[init] Wildcard entry created. To require login: disable it in"
    echo "[init] Configuration → Users → Access Entries and create your own user."
fi

echo "[init] uid=$(id -u tvheadend) gid=$(id -g tvheadend) tz=${TZ:-UTC}"

# ── Drop privileges and exec tvheadend ───────────────────────────────────────
exec su-exec tvheadend tvheadend \
    --config "${TVH_DATA}" \
    --http_port 9981 \
    --htsp_port 9982 \
    "$@"
