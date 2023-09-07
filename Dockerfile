
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
