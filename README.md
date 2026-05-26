# TVHeadend + Streamlink Container

[![Build & Push Multi-Arch Image](https://github.com/mmBesar/tvheadend-containers/actions/workflows/container-build.yml/badge.svg)](https://github.com/mmBesar/tvheadend-containers/actions/workflows/container-build.yml)
[![Sync — TVHeadend Upstream](https://github.com/mmBesar/tvheadend-containers/actions/workflows/upstream-sync.yml/badge.svg)](https://github.com/mmBesar/tvheadend-containers/actions/workflows/upstream-sync.yml)
[![Sync — streamlink-drm Mirror](https://github.com/mmBesar/tvheadend-containers/actions/workflows/streamlink-drm-sync.yml/badge.svg)](https://github.com/mmBesar/tvheadend-containers/actions/workflows/streamlink-drm-sync.yml)
[![GitHub Container Registry](https://img.shields.io/badge/GHCR-ghcr.io%2Fmmbesar%2Ftvheadend--containers-blue?logo=github)](https://github.com/mmBesar/tvheadend-containers/pkgs/container/tvheadend-containers)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

TVHeadend compiled from source on Alpine Linux edge, with streamlink and
the dashdrm plugin included. All three architectures built natively — no QEMU.

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
    network_mode: host          # required for IPTV multicast
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

On first start, a wildcard access entry (`*`) is created automatically —
**no login is required by default**, exactly like the classic LinuxServer image.

**To enable authentication:**
1. Open the WebUI → **Configuration → Users → Access Entries**
2. Create your own user with a username and password under **Configuration → Users → Passwords**
3. Disable or delete the `*` wildcard entry
4. From this point on, TVHeadend will require login

**To go back to open access:** re-enable the `*` entry, or create a new one
with username `*` and prefix `0.0.0.0/0`.

The wildcard entry is only created on a genuine first run (empty config
directory). Existing installs are never touched.

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| `9981` | HTTP | WebUI |
| `9982` | HTSP | Kodi / client apps |
| `9983` | HTTPS | WebUI (TLS) |

## Streamlink & DRM streams

This image includes [streamlink](https://streamlink.github.io) and the
[dashdrm plugin](https://github.com/titus-au/streamlink-plugin-dashdrm)
for DRM-protected streams.

The dashdrm plugin is a **sideloaded streamlink plugin** — not a separate
binary. You use `streamlink` as normal; the plugin is loaded automatically
and adds support for DASH streams with ClearKey/Widevine DRM.

```bash
# Regular stream
streamlink https://example.com/stream best

# DRM stream (dashdrm plugin handles it transparently)
streamlink https://example.com/drm-stream best
```

In TVHeadend, configure your IPTV network pipe command as:
```
streamlink --stdout {url} best
```

## riscv64 notes

`libhdhomerun` is not available in Alpine for riscv64. TVHeadend is built
with `--disable-hdhomerun_client` on that arch. Everything else — DVB-CSA,
IPTV, SAT>IP, streamlink — works normally.

## Workflows

| Workflow | Schedule | Purpose |
|----------|----------|---------|
| `upstream-sync.yml` | Every 6h | Mirrors `tvheadend/tvheadend:master` → our `upstream` branch |
| `streamlink-drm-sync.yml` | Every 6h (offset) | Mirrors dashdrm plugin → our `streamlink-drm` branch |
| `container-build.yml` | On push / dispatch | Builds all three arches natively; creates multi-arch manifest |

Builds always use our own mirrored branches — never fetches from upstream
at build time — so builds are reproducible and resilient to upstream outages.

## RISE RISC-V Runners

The riscv64 build requires the **RISE RISC-V Runners** GitHub App.
Install it at [risev-runners.org](https://risev-runners.org).

> If you delete and recreate this repo, re-authorize the RISE app under
> **Settings → Integrations → GitHub Apps** — it binds to the repo's internal
> ID, not its name.

---

## Credits

| Project | Author | License |
|---------|--------|---------|
| [TVHeadend](https://github.com/tvheadend/tvheadend) | TVHeadend Project | GPL-3.0 |
| [streamlink](https://github.com/streamlink/streamlink) | Streamlink Team | BSD-2-Clause |
| [streamlink-plugin-dashdrm](https://github.com/titus-au/streamlink-plugin-dashdrm) | titus-au | BSD-2-Clause |
| [Alpine Linux](https://alpinelinux.org) | Alpine Linux Team | Various |
| [RISE RISC-V Runners](https://risev-runners.org) | RISE Project | — |
