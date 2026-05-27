# TVHeadend + Streamlink Container

[![Build & Push Multi-Arch Image](https://github.com/mmBesar/tvheadend-containers/actions/workflows/container-build.yml/badge.svg)](https://github.com/mmBesar/tvheadend-containers/actions/workflows/container-build.yml)
[![Sync — TVHeadend](https://github.com/mmBesar/tvheadend-containers/actions/workflows/sync-tvheadend.yml/badge.svg)](https://github.com/mmBesar/tvheadend-containers/actions/workflows/sync-tvheadend.yml)
[![Sync — sl-dashdrm](https://github.com/mmBesar/tvheadend-containers/actions/workflows/sync-sl-dashdrm.yml/badge.svg)](https://github.com/mmBesar/tvheadend-containers/actions/workflows/sync-sl-dashdrm.yml)
[![Sync — sl-hlsdrm](https://github.com/mmBesar/tvheadend-containers/actions/workflows/sync-sl-hlsdrm.yml/badge.svg)](https://github.com/mmBesar/tvheadend-containers/actions/workflows/sync-sl-hlsdrm.yml)
[![GitHub Container Registry](https://img.shields.io/badge/GHCR-ghcr.io%2Fmmbesar%2Ftvheadend--containers-blue?logo=github)](https://github.com/mmBesar/tvheadend-containers/pkgs/container/tvheadend-containers)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

TVHeadend compiled from source on Alpine Linux edge, with streamlink, dashdrm,
and hlsdrm plugins pre-configured and ready to use.

Supports `linux/amd64`, `linux/arm64`, and `linux/riscv64` — all built natively, no QEMU.

---

## Quick start

```yaml
services:
  tvheadend:
    image: ghcr.io/mmbesar/tvheadend-containers:latest
    container_name: tvheadend
    network_mode: host
    environment:
      PUID: 1000
      PGID: 1000
      TZ: UTC
    volumes:
      - ./config:/var/lib/tvheadend
      - ./recordings:/var/lib/tvheadend/recordings
    devices:
      - /dev/dri:/dev/dri       # optional — GPU transcoding
      - /dev/dvb:/dev/dvb       # optional — DVB tuners
    restart: unless-stopped
```

### With picons

Picons live inside the config volume — no extra mount needed:

```yaml
    volumes:
      - ./config:/var/lib/tvheadend
      - ./recordings:/var/lib/tvheadend/recordings
```

Drop your picon `.png` files into `./config/picons/` on the host, then set
the path in TVHeadend under:
**Configuration → General → Base → Picon path** → `/var/lib/tvheadend/picons`

---

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` | `1000` | UID to run as — should match your host user |
| `PGID` | `1000` | GID to run as — should match your host group |
| `TZ` | `UTC` | Timezone, e.g. `Africa/Cairo`, `Europe/London` |

---

## Paths

| Path | Description |
|------|-------------|
| `/var/lib/tvheadend` | Config and database — **must be mounted** |
| `/var/lib/tvheadend/recordings` | Recordings output |
| `/var/lib/tvheadend/picons` | Picon/channel logos — inside the config volume |

---

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| `9981` | HTTP | WebUI |
| `9982` | HTSP | Kodi, Jellyfin, and other clients |
| `9983` | HTTPS | WebUI (TLS) |

---

## Authentication

On first start, a wildcard `*` access entry is created — **no login required
by default**, matching classic LinuxServer behavior.

**To enable authentication:**
1. Go to **Configuration → Users → Passwords** — create your user
2. Go to **Configuration → Users → Access Entries** — create an entry for your user
3. Disable or delete the `*` wildcard entry

To revert to open access, re-enable the `*` entry.

---

## Streamlink

streamlink is pre-installed with the **dashdrm** and **hlsdrm** plugins
loaded automatically — no `--plugin-dir` flag needed anywhere.

### DASH streams (with or without DRM)

Use the `dashdrm://` prefix in TVHeadend's pipe command:

```
pipe:///usr/bin/env streamlink --stdout \
  --http-header "User-Agent=Mozilla/5.0" \
  --http-header "Referer=https://your-provider.example/" \
  --http-header "Origin=https://your-provider.example" \
  --dashdrm-decryption-key "YOUR_KEY_IN_HEX" \
  --ffmpeg-ffmpeg "/usr/bin/ffmpeg" \
  --ffmpeg-fout "mpegts" \
  --default-stream best \
  --url "dashdrm://https://your-provider.example/manifest.mpd"
```

Omit `--dashdrm-decryption-key` for unencrypted DASH streams.

### HLS streams (with or without DRM)

Use the `hlsdrm://` prefix:

```
pipe:///usr/bin/env streamlink --stdout \
  --http-header "User-Agent=Mozilla/5.0" \
  --http-header "Referer=https://your-provider.example/" \
  --http-header "Origin=https://your-provider.example" \
  --hlsdrm-decryption-key "YOUR_KEY_IN_HEX" \
  --ffmpeg-ffmpeg "/usr/bin/ffmpeg" \
  --ffmpeg-fout "mpegts" \
  --default-stream best \
  --url "hlsdrm://https://your-provider.example/stream.m3u8"
```

### Plain IPTV / HLS (no DRM)

```
pipe:///usr/bin/env streamlink --stdout \
  --http-header "User-Agent=Mozilla/5.0" \
  --default-stream best \
  --url "https://your-provider.example/stream.m3u8"
```

### Key format

Keys can be passed as hex only or as a `KID:KEY` pair:

```
--dashdrm-decryption-key "aabbccdd..."
--dashdrm-decryption-key "kid_in_hex:key_in_hex"
```

See [dashdrm docs](https://github.com/titus-au/streamlink-plugin-dashdrm) and
[hlsdrm docs](https://github.com/titus-au/streamlink-plugin-hlsdrm) for
advanced options (multi-key, multi-audio, multi-period).

---

## DVB descrambling

This image connects to an external OSCam or NCam server via
**CAPMT (Linux Network DVBAPI)**. To configure:

1. Run an OSCam or NCam container on your network
2. In TVHeadend go to **Configuration → CAs → Add**
3. Select **CAPMT (Linux Network DVBAPI)**
4. Set the server IP and port (default OSCam: `9000`, NCam: `9001`)

---

## Credits

| Project | Author | License |
|---------|--------|---------|
| [TVHeadend](https://github.com/tvheadend/tvheadend) | TVHeadend Project | GPL-3.0 |
| [streamlink](https://github.com/streamlink/streamlink) | Streamlink Team | BSD-2-Clause |
| [streamlink-plugin-dashdrm](https://github.com/titus-au/streamlink-plugin-dashdrm) | titus-au | BSD-2-Clause |
| [streamlink-plugin-hlsdrm](https://github.com/titus-au/streamlink-plugin-hlsdrm) | titus-au | BSD-2-Clause |
| [Alpine Linux](https://alpinelinux.org) | Alpine Linux Team | Various |
| [RISE RISC-V Runners](https://risev-runners.org) | RISE Project | — |
