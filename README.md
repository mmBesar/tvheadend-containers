# TVHeadend + Streamlink — Self-Built Multi-Arch Container

TVHeadend compiled from source on Alpine Linux edge.  
No dependency on LinuxServer.io or any other third-party image.

## Supported architectures

| Arch | Runner | Notes |
|------|--------|-------|
| `linux/amd64` | `ubuntu-latest` | Native |
| `linux/arm64` | `ubuntu-24.04-arm` | Native GitHub-hosted (free) |
| `linux/riscv64` | `ubuntu-24.04-riscv` | Native via RISE RISC-V Runners |

**No QEMU is used for any architecture.**

## Add-ons included

- **streamlink** — official release, uses system `py3-lxml` (6.x)
- **streamlink-drm** — installed `--no-deps` to bypass the `lxml<5` constraint,
  all other deps installed manually, then copied to `/usr/local/bin/streamlink-drm`

## riscv64 differences

`libhdhomerun` is not available in Alpine for riscv64.  
TVHeadend is built with `--disable-hdhomerun_client` on that arch.  
Everything else (DVB-CSA, IPTV, SAT>IP, streamlink) works normally.

## Workflows

### `upstream-sync.yml`
- Runs every 6 hours (and on `workflow_dispatch`)
- Fetches `tvheadend/tvheadend:master` into our `upstream` branch
- Strips upstream's `.github/` so it never interferes
- Vendors `support/container-entrypoint.sh` into `main` if changed
- Dispatches `upstream-release` event to trigger a new build

### `container-build.yml`
- Triggered by: push to `main` (Dockerfile/support changes), `workflow_dispatch`,
  or `upstream-release` dispatch from the sync workflow
- Builds natively on 3 runners in parallel
- Creates a combined multi-arch manifest at `:latest` and `:<short-sha>`
- Records built SHA in `built-tags.txt` to prevent duplicate builds

## Usage

```yaml
services:
  tvheadend:
    image: ghcr.io/mmbesar/tvheadend-streamlink:latest
    container_name: tvheadend
    network_mode: host        # required for IPTV multicast
    environment:
      - TVHEADEND_DATA_DIR=/config
    volumes:
      - ./config:/config
      - ./recordings:/var/lib/tvheadend/recordings
    restart: unless-stopped
```

## First-time setup

1. Push this repo to `github.com/mmBesar/<repo-name>`
2. The RISE RISC-V runner requires installing the **risev-runners.org** GitHub App
   on your repo — follow https://risev-runners.org to connect it
3. Trigger the first build manually:  
   `Actions → Build & Push Multi-Arch Image → Run workflow`
