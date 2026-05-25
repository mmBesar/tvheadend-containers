# SPDX-License-Identifier: GPL-3.0-or-later
#
# TVHeadend — built from source on Alpine Linux edge
# Supports: linux/amd64, linux/arm64, linux/riscv64
#
# Runtime env vars:
#   PUID  — UID to run tvheadend as (default: 1000)
#   PGID  — GID to run tvheadend as (default: 1000)
#   TZ    — timezone, e.g. Africa/Cairo (default: UTC)

ARG ALPINE_VERSION="edge"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: TVHeadend — compile from our upstream branch
# ─────────────────────────────────────────────────────────────────────────────
FROM alpine:${ALPINE_VERSION} AS tvh-builder

ARG TVH_REPO="https://github.com/tvheadend/tvheadend"
ARG TVH_REF="master"
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

RUN git clone --depth 1 --branch "${TVH_REF}" "${TVH_REPO}" /src \
 || git clone "${TVH_REPO}" /src \
 && cd /src \
 && git fetch origin "${TVH_REF}" \
 && git checkout FETCH_HEAD \
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
# Uses official streamlink + streamlink-plugin-dashdrm (a proper plugin,
# not a fork). No lxml conflicts, no version collisions, no --no-deps hacks.
# gcc + python3-dev present to compile pycryptodome on arches with no wheel.
# ─────────────────────────────────────────────────────────────────────────────
FROM alpine:${ALPINE_VERSION} AS streamlink-builder

ARG TARGETARCH
ARG DASHDRM_REPO="https://github.com/mmBesar/streamlink-drm"
ARG DASHDRM_REF="master"

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

# Install pycryptodome (needed by dashdrm for ClearKey decryption)
# On riscv64 there is no PyPI wheel — try RISE pre-built index first,
# gcc compiles from source as fallback.
RUN if [ "$TARGETARCH" = "riscv64" ]; then \
      pip install --break-system-packages \
        --extra-index-url https://gitlab.com/api/v4/projects/56254198/packages/pypi/simple \
        pycryptodome; \
    else \
      pip install --break-system-packages pycryptodome; \
    fi

# Clone our mirror of streamlink-drm plugin and install it as a sideloaded plugin.
# streamlink looks for plugins in ~/.local/share/streamlink/plugins/ by default,
# but we install to /usr/local/share/streamlink/plugins/ so it's system-wide.
RUN git clone "${DASHDRM_REPO}" /dashdrm \
 && cd /dashdrm \
 && git checkout "${DASHDRM_REF}" \
 && mkdir -p /usr/local/share/streamlink/plugins \
 && cp /dashdrm/dashdrm/*.py /usr/local/share/streamlink/plugins/

# Snapshot everything for the runner stage
RUN SITE=$(python3 -c "import site; print(site.getsitepackages()[0])") \
 && mkdir -p /export/site-packages /export/bin /export/plugins \
 && cp -a "${SITE}/." /export/site-packages/ \
 && cp "$(which streamlink)" /export/bin/streamlink \
 && cp /usr/local/share/streamlink/plugins/*.py /export/plugins/ \
 && echo "streamlink: $(streamlink --version)" \
 && python3 -c "import streamlink; print('streamlink importable OK')"

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

# Streamlink: copy snapshot into correct versioned site-packages path
COPY --from=streamlink-builder /export/site-packages/ /streamlink-pkgs/
COPY --from=streamlink-builder /export/bin/streamlink /usr/local/bin/streamlink
COPY --from=streamlink-builder /export/plugins/       /usr/local/share/streamlink/plugins/

RUN SITE=$(python3 -c "import site; print(site.getsitepackages()[0])") \
 && cp -a /streamlink-pkgs/. "${SITE}/" \
 && rm -rf /streamlink-pkgs \
 && python3 -c "import streamlink; print('streamlink OK')" \
 && streamlink --version \
 && echo "dashdrm plugin installed at /usr/local/share/streamlink/plugins/"

# Entrypoint: PUID/PGID/TZ/device-groups/first-run --noacl
COPY support/container-entrypoint.sh /init
RUN chmod +x /init

EXPOSE 9981 9982 9983

VOLUME /var/lib/tvheadend
VOLUME /var/lib/tvheadend/recordings

WORKDIR /var/lib/tvheadend

ENTRYPOINT ["/sbin/tini", "--", "/init"]
