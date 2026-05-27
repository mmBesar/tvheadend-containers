# SPDX-License-Identifier: GPL-3.0-or-later
#
# TVHeadend — built from source on Alpine Linux edge
# Supports: linux/amd64, linux/arm64, linux/riscv64
#
# Builds from OUR mirrored branches — never fetches from upstream directly:
#   TVH source   → our `upstream` branch      (synced from tvheadend/tvheadend)
#   dashdrm plugin → our `streamlink-drm` branch (synced from titus-au/streamlink-plugin-dashdrm)
#
# Runtime env vars:
#   PUID  — UID to run tvheadend as (default: 1000)
#   PGID  — GID to run tvheadend as (default: 1000)
#   TZ    — timezone, e.g. Africa/Cairo (default: UTC)

ARG ALPINE_VERSION="edge"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: TVHeadend — compile from our `upstream` branch
# ─────────────────────────────────────────────────────────────────────────────
FROM alpine:${ALPINE_VERSION} AS tvh-builder

# Both args are overridden at build time by container-build.yml to point at
# our repo + the resolved `upstream` branch HEAD. Defaults here are the
# fallback for local `docker build` without passing --build-arg.
ARG TVH_REPO="https://github.com/mmBesar/tvheadend-containers"
ARG TVH_REF="upstream"
ARG TARGETARCH

WORKDIR /src

RUN apk add --no-cache \
      avahi-dev \
      bash \
      bsd-compat-headers \
      build-base \
      cmake \
      coreutils \
      dbus-dev \
      findutils \
      gettext-dev \
      git \
      gnu-libiconv-dev \
      libdvbcsa-dev \
      linux-headers \
      musl-dev \
      "openssl-dev>3" \
      pcre2 \
      pngquant \
      python3 \
      uriparser-dev \
      wget \
      zlib-dev \
 && if [ "$TARGETARCH" != "riscv64" ]; then \
      apk add --no-cache libhdhomerun-dev; \
    fi

# Clone then checkout — supports both branch names and full SHAs
RUN git clone "${TVH_REPO}" /src \
 && cd /src \
 && git checkout "${TVH_REF}" \
 && git submodule update --init --depth 1

RUN cd /src \
 && git config --global --add safe.directory /src/data/dvb-scan \
 && HDH_FLAG="--enable-hdhomerun_client" \
 && [ "$TARGETARCH" = "riscv64" ] && HDH_FLAG="--disable-hdhomerun_client" || true \
 && ./configure \
      --prefix=/usr/local \
      --disable-doc \
      --disable-execinfo \
      --disable-ffmpeg_static \
      --disable-hdhomerun_static \
      --disable-libfdkaac_static \
      --disable-libmfx_static \
      --disable-libopus_static \
      --disable-libtheora_static \
      --disable-libvorbis_static \
      --disable-libvpx_static \
      --disable-libx264_static \
      --disable-libx265_static \
      --enable-bundle \
      --enable-dvbcsa \
      --enable-pngquant \
      --python=python3 \
      $HDH_FLAG

RUN cd /src \
 && make DESTDIR=/tvheadend -j"$(( $(nproc) > 1 ? $(nproc) - 1 : 1 ))" install

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: streamlink builder
#
# Official streamlink + dashdrm + hlsdrm plugins.
# Plugins go to /usr/local/share/streamlink/plugins/ — the XDG system-wide
# sideload path that streamlink scans automatically on every invocation.
# A system-wide config at /etc/streamlink/streamlinkrc sets plugin-dir
# permanently so no --plugin-dir is ever needed in TVHeadend pipe commands.
# gcc + python3-dev present to compile pycryptodome on arches with no wheel.
# ─────────────────────────────────────────────────────────────────────────────
FROM alpine:${ALPINE_VERSION} AS streamlink-builder

ARG TARGETARCH
ARG DASHDRM_REPO="https://github.com/mmBesar/tvheadend-containers"
ARG DASHDRM_REF="sl-dashdrm"
ARG HLSDRM_REPO="https://github.com/mmBesar/tvheadend-containers"
ARG HLSDRM_REF="sl-hlsdrm"

RUN apk add --no-cache \
      gcc \
      git \
      musl-dev \
      py3-lxml \
      py3-pip \
      python3 \
      python3-dev

# Install official streamlink
RUN pip install --break-system-packages streamlink

# Install pycryptodome (needed by both drm plugins for ClearKey decryption).
# On riscv64 there is no PyPI wheel — try RISE pre-built index first,
# gcc compiles from source as fallback.
RUN if [ "$TARGETARCH" = "riscv64" ]; then \
      pip install --break-system-packages \
        --extra-index-url https://gitlab.com/api/v4/projects/56254198/packages/pypi/simple \
        pycryptodome; \
    else \
      pip install --break-system-packages pycryptodome; \
    fi

# Create the system-wide sideload directory
RUN mkdir -p /usr/local/share/streamlink/plugins

# Clone and install dashdrm plugin
# File is at dashdrm/dashdrm.py inside the repo
RUN git clone "${DASHDRM_REPO}" /tmp/dashdrm \
 && cd /tmp/dashdrm \
 && git checkout "${DASHDRM_REF}" \
 && cp /tmp/dashdrm/dashdrm/dashdrm.py /usr/local/share/streamlink/plugins/dashdrm.py \
 && rm -rf /tmp/dashdrm \
 && echo "dashdrm installed OK"

# Clone and install hlsdrm plugin
# File is at hlsdrm/hlsdrm.py inside the repo (same structure as dashdrm)
RUN git clone "${HLSDRM_REPO}" /tmp/hlsdrm \
 && cd /tmp/hlsdrm \
 && git checkout "${HLSDRM_REF}" \
 && find /tmp/hlsdrm -name "*.py" -not -path "*/.git/*" \
 && cp /tmp/hlsdrm/hlsdrm/hlsdrm.py /usr/local/share/streamlink/plugins/hlsdrm.py \
 && rm -rf /tmp/hlsdrm \
 && echo "hlsdrm installed OK"

# Verify both plugin files are in place
RUN ls -la /usr/local/share/streamlink/plugins/

# Snapshot packages and binary for the runner stage.
# Plugins (dashdrm.py, hlsdrm.py) stay in /usr/local/share/streamlink/plugins/
# and are copied directly from there — NOT from site-packages/streamlink/plugins/
# which contains only built-in plugins and must never be used as plugin-dir.
RUN SITE=$(python3 -c "import site; print(site.getsitepackages()[0])") \
 && mkdir -p /export/site-packages /export/bin /export/plugins \
 && cp -a "${SITE}/." /export/site-packages/ \
 && cp "$(which streamlink)" /export/bin/streamlink \
 && cp /usr/local/share/streamlink/plugins/dashdrm.py /export/plugins/dashdrm.py \
 && cp /usr/local/share/streamlink/plugins/hlsdrm.py  /export/plugins/hlsdrm.py \
 && echo "streamlink: $(streamlink --version)"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3: runner — minimal runtime image
# ─────────────────────────────────────────────────────────────────────────────
FROM alpine:${ALPINE_VERSION} AS runner

ARG TARGETARCH

LABEL org.opencontainers.image.title="TVHeadend + Streamlink"
LABEL org.opencontainers.image.description="TVHeadend built from source on Alpine with streamlink and dashdrm plugin"
LABEL org.opencontainers.image.licenses="GPL-3.0-or-later"
LABEL org.opencontainers.image.source="https://github.com/mmBesar/tvheadend-containers"

RUN apk add --no-cache \
      avahi \
      bzip2 \
      dbus-libs \
      ffmpeg \
      gnu-libiconv-libs \
      libcrypto3 \
      libdvbcsa \
      libssl3 \
      liburiparser \
      libva \
      mesa \
      pcre2 \
      perl-http-entity-parser \
      pngquant \
      py3-lxml \
      python3 \
      shadow \
      su-exec \
      tini \
      tzdata \
      xmltv \
      zlib \
 && if [ "$TARGETARCH" != "riscv64" ]; then \
      apk add --no-cache libhdhomerun-libs; \
    fi \
 && addgroup -S tvheadend \
 && adduser -D -G tvheadend -h /var/lib/tvheadend -s /bin/nologin -S tvheadend \
 && adduser tvheadend audio \
 && adduser tvheadend video \
 && install -d -m 775 -g tvheadend -o tvheadend /var/lib/tvheadend/recordings \
 && install -d -m 775 -g tvheadend -o tvheadend /var/log/tvheadend

# TVHeadend compiled binary + bundled web UI data
COPY --from=tvh-builder /tvheadend /

# Streamlink: copy snapshot into the correct versioned site-packages path.
COPY --from=streamlink-builder /export/site-packages/ /streamlink-pkgs/
COPY --from=streamlink-builder /export/bin/streamlink /usr/local/bin/streamlink

# Plugins go to the XDG system-wide sideload path — streamlink scans this
# directory automatically on every invocation, no --plugin-dir needed.
COPY --from=streamlink-builder /export/plugins/ /usr/local/share/streamlink/plugins/

# NOTE: streamlink config is written at runtime by container-entrypoint.sh
# to $HOME/.config/streamlink/config (the correct XDG path).
# /etc/streamlink/ is not a valid streamlink config location — ignored.

RUN SITE=$(python3 -c "import site; print(site.getsitepackages()[0])") \
 && cp -a /streamlink-pkgs/. "${SITE}/" \
 && rm -rf /streamlink-pkgs \
 && streamlink --version \
 && ls -la /usr/local/share/streamlink/plugins/ \
 && streamlink --can-handle-url "dashdrm://http://test.com/test.mpd" && echo "dashdrm OK" \
 && streamlink --can-handle-url "hlsdrm://http://test.com/test.m3u8" && echo "hlsdrm OK" \
 && echo "All OK"

# Entrypoint: PUID/PGID remapping, TZ, device groups, first-run ACL setup
COPY support/container-entrypoint.sh /init
RUN chmod +x /init

EXPOSE 9981 9982 9983

VOLUME /var/lib/tvheadend
VOLUME /var/lib/tvheadend/recordings

WORKDIR /var/lib/tvheadend

ENTRYPOINT ["/sbin/tini", "--", "/init"]
