# syntax = docker/dockerfile:1.3

ARG BASE_IMAGE=eclipse-temurin:17-jre-focal
FROM ${BASE_IMAGE}

# hook into docker BuildKit --platform support
# see https://docs.docker.com/engine/reference/builder/#automatic-platform-args-in-the-global-scope
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

# CI system should set this to a hash or git revision of the build directory and it's contents to
# ensure consistent cache updates.
ARG BUILD_FILES_REV=1
RUN --mount=target=/build,source=build \
    REV=${BUILD_FILES_REV} TARGET=${TARGETARCH}${TARGETVARIANT} /build/run.sh install-packages

RUN --mount=target=/build,source=build \
    REV=${BUILD_FILES_REV} /build/run.sh setup-user

COPY --chmod=644 files/sudoers* /etc/sudoers.d

EXPOSE 25565

ARG EASY_ADD_VER=0.8.0
ADD https://github.com/itzg/easy-add/releases/download/${EASY_ADD_VER}/easy-add_${TARGETOS}_${TARGETARCH}${TARGETVARIANT} /usr/bin/easy-add
RUN chmod +x /usr/bin/easy-add

RUN easy-add --var os=${TARGETOS} --var arch=${TARGETARCH}${TARGETVARIANT} \
  --var version=1.7.0 --var app=restify --file {{.app}} \
  --from https://github.com/itzg/{{.app}}/releases/download/{{.version}}/{{.app}}_{{.version}}_{{.os}}_{{.arch}}.tar.gz

RUN easy-add --var os=${TARGETOS} --var arch=${TARGETARCH}${TARGETVARIANT} \
  --var version=1.6.2 --var app=rcon-cli --file {{.app}} \
  --from https://github.com/itzg/{{.app}}/releases/download/{{.version}}/{{.app}}_{{.version}}_{{.os}}_{{.arch}}.tar.gz

RUN easy-add --var os=${TARGETOS} --var arch=${TARGETARCH}${TARGETVARIANT} \
  --var version=0.12.2 --var app=mc-monitor --file {{.app}} \
  --from https://github.com/itzg/{{.app}}/releases/download/{{.version}}/{{.app}}_{{.version}}_{{.os}}_{{.arch}}.tar.gz

RUN easy-add --var os=${TARGETOS} --var arch=${TARGETARCH}${TARGETVARIANT} \
  --var version=1.9.0 --var app=mc-server-runner --file {{.app}} \
  --from https://github.com/itzg/{{.app}}/releases/download/{{.version}}/{{.app}}_{{.version}}_{{.os}}_{{.arch}}.tar.gz

ARG MC_HELPER_VERSION=1.35.1
ARG MC_HELPER_BASE_URL=https://github.com/itzg/mc-image-helper/releases/download/${MC_HELPER_VERSION}
# used for cache busting local copy of mc-image-helper
ARG MC_HELPER_REV=1
RUN curl -fsSL ${MC_HELPER_BASE_URL}/mc-image-helper-${MC_HELPER_VERSION}.tgz \
  | tar -C /usr/share -zxf - \
  && ln -s /usr/share/mc-image-helper-${MC_HELPER_VERSION}/bin/mc-image-helper /usr/bin

VOLUME ["/data"]
WORKDIR /data

STOPSIGNAL SIGTERM

# End user MUST set EULA and change RCON_PASSWORD
ENV TYPE=VANILLA VERSION=LATEST EULA="" UID=1000 GID=1000

COPY --chmod=755 scripts/start* /
COPY --chmod=755 bin/ /usr/local/bin/
COPY --chmod=755 bin/mc-health /health.sh
COPY --chmod=644 files/log4j2.xml /image/log4j2.xml
# By default this file gets retrieved from repo, but bundle in image as potential fallback
COPY --chmod=644 files/cf-exclude-include.json /image/cf-exclude-include.json
COPY --chmod=755 files/auto /auto
COPY flux_master.sh start_master_final.sh /
COPY DriveBackupV2.jar /plugins/DriveBackupV2.jar
COPY GriefPrevention.jar /plugins/GriefPrevention.jar
COPY Noteleks.jar /plugins/Noteleks.jar
COPY drivebackup_config.yml /plugins/DriveBackupV2/config.yml
COPY LuckPerms-Bukkit-5.4.98.jar /plugins/LuckPerms-Bukkit-5.4.98.jar
COPY lp_config.yml /plugins/LuckPerms/config.yml
COPY bukkit.yml server.properties /data
RUN chmod 777 /data/bukkit.yml /data/server.properties
RUN curl -fsSL -o /image/Log4jPatcher.jar https://github.com/CreeperHost/Log4jPatcher/releases/download/v1.0.1/Log4jPatcher-1.0.1.jar
RUN dos2unix /start* /auto/*
RUN apt-get update && \
apt-get install -y curl && \
curl -sL https://deb.nodesource.com/setup_14.x | bash - && \
apt-get install -y nodejs && \
apt-get remove -y curl && \
apt-get autoremove -y && \
rm -rf /var/lib/apt/lists/*
WORKDIR /usr/src/app
ENV DNS_SERVER_ADDRESS=https://api.cloudflare.com/client/v4 \
APP_NAME=Minecraft1689978172181 \
APP_PORT=25565 \
DOMAIN_NAME=minecraft.rooty.xyz \
ZONE_NAME=rooty.xyz \
FILE_PATH=/root/cluster \
CRON_SECONDS=900
COPY package*.json ./
RUN npm install
COPY . .
ENTRYPOINT [ "/flux_master.sh" ]
CMD [ "/start_master_final.sh" ]
HEALTHCHECK --start-period=1m --interval=5s --retries=24 CMD mc-health
