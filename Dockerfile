# SPDX-License-Identifier: GPL-3.0-or-later
#
# TVHeadend — built from source on Alpine Linux
# Supports: linux/amd64, linux/arm64, linux/riscv64
#
# Runtime env vars:
#   PUID  — UID to run tvheadend as (default: 1000)
#   PGID  — GID to run tvheadend as (default: 1000)
#   TZ    — timezone, e.g. Africa/Cairo (default: UTC)

ARG ALPINE_VERSION="edge"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: builder — compile TVHeadend from source
# ─────────────────────────────────────────────────────────────────────────────
FROM alpine:${ALPINE_VERSION} AS builder

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
# Installs into system Python paths directly (no --prefix tricks).
# Then snapshots everything into /export with known paths so the runner
# stage can COPY without any version-specific glob guessing.
# gcc + python3-dev present to compile pycryptodome from source on riscv64.
# ─────────────────────────────────────────────────────────────────────────────
FROM alpine:${ALPINE_VERSION} AS streamlink-builder

ARG TARGETARCH

RUN apk add --no-cache \
      gcc \
      git \
      musl-dev \
      py3-lxml \
      py3-pip \
      python3 \
      python3-dev

# Step 1: streamlink-drm installs itself as 'streamlink 0.0.0+unknown'
#         --no-deps skips the incompatible lxml<5 constraint
RUN pip install --break-system-packages --no-deps \
      "git+https://github.com/ImAleeexx/streamlink-drm"

# Step 2: runtime deps for streamlink-drm
#         pycryptodome has no riscv64 wheel on PyPI — try RISE pre-built index
#         first, gcc compiles it from source as fallback
RUN if [ "$TARGETARCH" = "riscv64" ]; then \
      pip install --break-system-packages \
        --extra-index-url https://gitlab.com/api/v4/projects/56254198/packages/pypi/simple \
        certifi isodate pycountry pycryptodome PySocks requests urllib3 websocket-client; \
    else \
      pip install --break-system-packages \
        certifi isodate pycountry pycryptodome PySocks requests urllib3 websocket-client; \
    fi

# Step 3: save the drm entry point BEFORE pip uninstalls it in the next step
RUN cp "$(which streamlink)" /usr/local/bin/streamlink-drm

# Step 4: install official streamlink — pip uninstalls the drm version first
#         (expected), then installs the real one. drm binary already saved.
RUN pip install --break-system-packages --upgrade streamlink

# Step 5: snapshot installed packages and binaries into /export with stable paths
#         python3 tells us the real versioned site-packages path at build time
RUN SITE=$(python3 -c "import site; print(site.getsitepackages()[0])") \
 && mkdir -p /export/site-packages /export/bin \
 && cp -a "${SITE}/." /export/site-packages/ \
 && cp "$(which streamlink)"          /export/bin/streamlink \
 && cp /usr/local/bin/streamlink-drm  /export/bin/streamlink-drm \
 # Verify both work before we export
 && echo "streamlink:     $(streamlink --version)" \
 && python3 -c "import streamlink_cli; print('streamlink_cli importable OK')" \
 && echo "streamlink-drm: present at /export/bin/streamlink-drm"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3: runner — minimal runtime image
# ─────────────────────────────────────────────────────────────────────────────
FROM alpine:${ALPINE_VERSION} AS runner

ARG TARGETARCH

LABEL org.opencontainers.image.title="TVHeadend + Streamlink"
LABEL org.opencontainers.image.description="TVHeadend built from source on Alpine with streamlink and streamlink-drm"
LABEL org.opencontainers.image.licenses="GPL-3.0-or-later"

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
COPY --from=builder /tvheadend /

# Streamlink: copy the snapshotted packages into the system site-packages path,
# and the binaries into /usr/local/bin — both are on Python's and $PATH by default.
RUN SITE=$(python3 -c "import site; print(site.getsitepackages()[0])") \
 && echo "Runner site-packages: ${SITE}" \
 && mkdir -p "${SITE}"
COPY --from=streamlink-builder /export/site-packages/ /streamlink-pkgs/
COPY --from=streamlink-builder /export/bin/streamlink      /usr/local/bin/streamlink
COPY --from=streamlink-builder /export/bin/streamlink-drm  /usr/local/bin/streamlink-drm

# Move packages into the correct versioned site-packages path at build time
RUN SITE=$(python3 -c "import site; print(site.getsitepackages()[0])") \
 && cp -a /streamlink-pkgs/. "${SITE}/" \
 && rm -rf /streamlink-pkgs \
 # Final verification that modules are importable in the runner
 && python3 -c "import streamlink_cli; print('streamlink_cli OK')" \
 && streamlink --version \
 && echo "streamlink-drm binary OK"

# Entrypoint: PUID/PGID remapping, TZ, device groups, first-run --noacl
COPY support/container-entrypoint.sh /init
RUN chmod +x /init

EXPOSE 9981 9982 9983

VOLUME /var/lib/tvheadend
VOLUME /var/lib/tvheadend/recordings

WORKDIR /var/lib/tvheadend

ENTRYPOINT ["/sbin/tini", "--", "/init"]
