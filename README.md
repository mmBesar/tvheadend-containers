# TVHeadend + Streamlink Container

[![Build & Push Multi-Arch Image](https://github.com/mmBesar/tvheadend-containers/actions/workflows/container-build.yml/badge.svg)](https://github.com/mmBesar/tvheadend-containers/actions/workflows/container-build.yml)
[![Sync — TVHeadend](https://github.com/mmBesar/tvheadend-containers/actions/workflows/sync-tvheadend.yml/badge.svg)](https://github.com/mmBesar/tvheadend-containers/actions/workflows/sync-tvheadend.yml)
[![Sync — sl-dashdrm](https://github.com/mmBesar/tvheadend-containers/actions/workflows/sync-sl-dashdrm.yml/badge.svg)](https://github.com/mmBesar/tvheadend-containers/actions/workflows/sync-sl-dashdrm.yml)
[![Sync — sl-hlsdrm](https://github.com/mmBesar/tvheadend-containers/actions/workflows/sync-sl-hlsdrm.yml/badge.svg)](https://github.com/mmBesar/tvheadend-containers/actions/workflows/sync-sl-hlsdrm.yml)
[![GitHub Container Registry](https://img.shields.io/badge/GHCR-ghcr.io%2Fmmbesar%2Ftvheadend--containers-blue?logo=github)](https://github.com/mmBesar/tvheadend-containers/pkgs/container/tvheadend-containers)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

TVHeadend compiled from source on Alpine Linux edge, with streamlink, dashdrm,
and hlsdrm plugins included. All three architectures built natively — no QEMU.

## Supported architectures

| Arch | Builder | Notes |
|------|---------|-------|
| `linux/amd64` | `ubuntu-latest` | Native |
| `linux/arm64` | `ubuntu-24.04-arm` | Native GitHub-hosted (free) |
| `linux/riscv64` | `ubuntu-24.04-riscv` | Native via RISE RISC-V Runners |

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` | `1000` | UID to run tvheadend as |
| `PGID` | `1000` | GID to run tvheadend as |
| `TZ` | `UTC` | Timezone, e.g. `Africa/Cairo` |

## Usage

```yaml
services:
  tvheadend:
    image: ghcr.io/mmbesar/tvheadend-containers:latest
    container_name: tvheadend
    network_mode: host
    environment:
      PUID: 1000
      PGID: 1000
      TZ: Africa/Cairo
    volumes:
      - ./config:/var/lib/tvheadend
      - ./recordings:/var/lib/tvheadend/recordings
    devices:
      - /dev/dri:/dev/dri       # optional — GPU transcoding
      - /dev/dvb:/dev/dvb       # optional — DVB tuners
    restart: unless-stopped
```

## Authentication

On first start a wildcard `*` access entry is created — no login required by
default, matching classic LinuxServer behavior.

**To enable authentication:**
1. Create your user under **Configuration → Users → Passwords**
2. Create an access entry under **Configuration → Users → Access Entries**
3. Disable or delete the `*` wildcard entry

## Streamlink plugins

Both plugins are **automatically loaded** on every `streamlink` invocation —
no `--plugin-dir` flag needed anywhere. A system-wide config at
`/etc/streamlink/streamlinkrc` sets the plugin directory permanently.

### dashdrm — DASH streams with DRM/ClearKey

For DASH `.mpd` streams (including encrypted ones):

```
pipe:///usr/bin/env streamlink --stdout \
  --http-header "User-Agent=Mozilla/5.0" \
  --http-header "Referer=https://example.com/" \
  --http-header "Origin=https://example.com" \
  --dashdrm-decryption-key "KID:KEY_IN_HEX" \
  --ffmpeg-ffmpeg "/usr/bin/ffmpeg" \
  --ffmpeg-fout "mpegts" \
  --default-stream best \
  --url "dashdrm://https://example.com/manifest.mpd"
```

For unencrypted DASH streams, omit `--dashdrm-decryption-key`.

### hlsdrm — HLS streams with DRM/ClearKey

For HLS `.m3u8` streams (including encrypted ones):

```
pipe:///usr/bin/env streamlink --stdout \
  --http-header "User-Agent=Mozilla/5.0" \
  --http-header "Referer=https://example.com/" \
  --http-header "Origin=https://example.com" \
  --hlsdrm-decryption-key "KID:KEY_IN_HEX" \
  --ffmpeg-ffmpeg "/usr/bin/ffmpeg" \
  --ffmpeg-fout "mpegts" \
  --default-stream best \
  --url "hlsdrm://https://example.com/stream.m3u8"
```

### Shahid MBC example (DASH + DRM)

```
pipe:///usr/bin/env streamlink --stdout \
  --http-header "User-Agent=Mozilla/5.0 (X11; Linux x86_64; rv:147.0) Gecko/20100101 Firefox/147.0" \
  --http-header "Referer=https://shahid.mbc.net/" \
  --http-header "Origin=https://shahid.mbc.net" \
  --dashdrm-decryption-key "17774f82a3b9e33ea7a149596acbb20f" \
  --stream-sorting-excludes ">576p+a193k" \
  --ffmpeg-ffmpeg "/usr/bin/ffmpeg" \
  --ffmpeg-fout "mpegts" \
  --default-stream best \
  --url "dashdrm://https://shd-gcp-live.lg.mncdn.com/live/bitmovin-mbc-2/51db9d7fa48a27d051f1eecb68069151/index.mpd"
```

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| `9981` | HTTP | WebUI |
| `9982` | HTSP | Kodi / client apps |
| `9983` | HTTPS | WebUI (TLS) |

## riscv64 notes

`libhdhomerun` is not available in Alpine for riscv64. TVHeadend is built
with `--disable-hdhomerun_client` on that arch. Everything else works normally.

## Branches & Workflows

| Branch | Mirrors | Sync Workflow |
|--------|---------|---------------|
| `tvheadend` | `tvheadend/tvheadend:master` | `sync-tvheadend.yml` every 6h |
| `sl-dashdrm` | `titus-au/streamlink-plugin-dashdrm:main` | `sync-sl-dashdrm.yml` every 6h |
| `sl-hlsdrm` | `titus-au/streamlink-plugin-hlsdrm:main` | `sync-sl-hlsdrm.yml` every 6h |

Builds always use our own mirrored branches — never fetches from upstream
at build time — so builds are reproducible and resilient to upstream outages.

## RISE RISC-V Runners

Install the **RISE RISC-V Runners** GitHub App at [risev-runners.org](https://risev-runners.org).

> If you delete and recreate this repo, re-authorize the RISE app under
> **Settings → Integrations → GitHub Apps**.

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
