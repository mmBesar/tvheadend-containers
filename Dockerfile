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
# Official streamlink + dashdrm plugin from our `streamlink-drm` branch.
# The plugin is installed directly into streamlink's own plugins directory
# inside site-packages — streamlink finds it automatically with no flags.
# gcc + python3-dev present to compile pycryptodome on arches with no wheel.
# ─────────────────────────────────────────────────────────────────────────────
FROM alpine:${ALPINE_VERSION} AS streamlink-builder

ARG TARGETARCH
# Both args overridden at build time by container-build.yml.
# Defaults point at our repo + our streamlink-drm branch.
ARG DASHDRM_REPO="https://github.com/mmBesar/tvheadend-containers"
ARG DASHDRM_REF="streamlink-drm"

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

# Install pycryptodome (needed by dashdrm for ClearKey decryption).
# On riscv64 there is no PyPI wheel — try RISE pre-built index first,
# gcc compiles from source as fallback.
RUN if [ "$TARGETARCH" = "riscv64" ]; then \
      pip install --break-system-packages \
        --extra-index-url https://gitlab.com/api/v4/projects/56254198/packages/pypi/simple \
        pycryptodome; \
    else \
      pip install --break-system-packages pycryptodome; \
    fi

# Clone our streamlink-drm branch — split into separate RUN steps so each
# failure is immediately visible in the build log.

# Step 1: clone
RUN git clone "${DASHDRM_REPO}" /dashdrm

# Step 2: checkout the right ref (branch name or SHA both work)
RUN cd /dashdrm && git checkout "${DASHDRM_REF}"

# Step 3: show repo tree so we can see exact file structure if next step fails
RUN find /dashdrm -maxdepth 2 -type f -name "*.py"

# Step 4: install dashdrm.py into streamlink's site-packages plugins directory.
# It then auto-loads with no --plugin-dir flag needed.
RUN SITE=$(python3 -c "import site; print(site.getsitepackages()[0])") \
 && PLUGIN_DIR="${SITE}/streamlink/plugins" \
 && echo "Target: ${PLUGIN_DIR}" \
 && cp /dashdrm/dashdrm.py "${PLUGIN_DIR}/dashdrm.py" \
 && ls -la "${PLUGIN_DIR}/dashdrm.py" \
 && echo "dashdrm install OK"

# Snapshot packages and binary for the runner stage
RUN SITE=$(python3 -c "import site; print(site.getsitepackages()[0])") \
 && mkdir -p /export/site-packages /export/bin \
 && cp -a "${SITE}/." /export/site-packages/ \
 && cp "$(which streamlink)" /export/bin/streamlink \
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
# dashdrm.py is already inside site-packages/streamlink/plugins/ so it comes
# along automatically — no separate plugin copy step needed.
COPY --from=streamlink-builder /export/site-packages/ /streamlink-pkgs/
COPY --from=streamlink-builder /export/bin/streamlink /usr/local/bin/streamlink

RUN SITE=$(python3 -c "import site; print(site.getsitepackages()[0])") \
 && cp -a /streamlink-pkgs/. "${SITE}/" \
 && rm -rf /streamlink-pkgs \
 # Verify streamlink runs and dashdrm.py landed in the right place
 && streamlink --version \
 && ls -la "${SITE}/streamlink/plugins/dashdrm.py" \
 && echo "All OK"

# Entrypoint: PUID/PGID remapping, TZ, device groups, first-run ACL setup
COPY support/container-entrypoint.sh /init
RUN chmod +x /init

EXPOSE 9981 9982 9983

VOLUME /var/lib/tvheadend
VOLUME /var/lib/tvheadend/recordings

WORKDIR /var/lib/tvheadend

ENTRYPOINT ["/sbin/tini", "--", "/init"]
