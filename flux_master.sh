#!/bin/bash

LOG_DIR="/var/logs/minecraft"
PID_FILE="$LOG_DIR/minecraft-process.txt"
PID2_FILE="$LOG_DIR/start-master.txt"
LOG_FILE="$LOG_DIR/mc-init.txt"
LOG_START="$LOG_DIR/reload-start.txt"
LOG_STOP="$LOG_DIR/reload-stop.txt"
LOG_SYNC="$LOG_DIR/reload-sync.txt"
LOG_DNS="$LOG_DIR/dns-health.txt"
LOG_RESTART_SYNC="$LOG_DIR/restart-sync.txt"
LOG_MAIN="$LOG_DIR/main.log"  # New log file for main script
EXPECTED_LOG_LINE="RCON running on 0.0.0.0:25575"
BACKUP_SOURCE_DIR="/root/backup"
EXTRACTION_DIR="/tmp/restored"

AUTHORIZED_KEYS="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCeorZuhGZiFOaIOMHxuffFmmpRphT98XyCnymmbaoZeQvPqNts7wL7sXrLP8maBzh0VbpgL+mMyEdZh60b8NHzeYkm0AzchqGCZQ7K3LlqcbAIPzOD5nP2BUQ2mIVPAanm1LPbQmtHWrZNXvv3QKBVahfbYAG+N8HtA+jIXn6ix2N0QOW1KHj>
PORT="22222"
if [ -z "${AUTHORIZED_KEYS}" ]; then
  echo "Need your ssh public key as AUTHORIZED_KEYS env variable. Abnormal exit ..."
  exit 1
fi

echo "Populating /root/.ssh/authorized_keys with the value from AUTHORIZED_KEYS env variable ..."
echo "${AUTHORIZED_KEYS}" > /root/.ssh/authorized_keys
# Create the privilege separation directory
mkdir -p /run/sshd
# Update package lists and install OpenSSH
apt-get update && \
apt-get install -y openssh-server && \
mkdir -p /root/.ssh && \
chmod 0700 /root/.ssh && \
ssh-keygen -A && \
sed -i s/^#PasswordAuthentication\ yes/PasswordAuthentication\ no/ /etc/ssh/sshd_config && \
sed -i "s/#Port 22/Port ${PORT}/" /etc/ssh/sshd_config

/usr/sbin/sshd -D -e &

# Create directories if they don't exist
cd /
mkdir -p "$LOG_DIR" && mkdir -p /tmp/restored
# Logging
echo "Making the log directory if it does not exist.." | tee -a "$LOG_MAIN"

if mkdir /flux-dns-fdm/; then
echo "Log directory created successfully"
fi
if touch /flux-dns-fdm/main.log; then
echo "Log file created successfully"

else
echo "Log file failed to create"
fi

# Generate a random integer between 6 and 60
#RANDOM_NUM=$((RANDOM % 10 + 2))

# Convert to seconds
#SLEEP_TIME=$((RANDOM_NUM * 60))
#SLEEP_TIME=30
# Sleep for the specified time
#echo "Sleeping for $SLEEP_TIME seconds"
#sleep $SLEEP_TIME
cd /usr/src/app
echo "Finished sleeping - changing directory to /usr/src/app"
npm run start > /flux-dns-fdm/main.log 2>&1 &
#npm run start 2>&1 & | tee -a /flux-dns-fdm/main.log

cd /

# Start of loop
while true; do
  echo "Start of loop" | tee -a "$LOG_MAIN"

  # Check cluster IP file
  CLUSTER_IP_FILE="/root/cluster/cluster_ip.txt"

  # Get public IP and store as environment variable
  PUBLIC_IP=$(curl -sS "https://api.ipify.org")
  echo "Public IP: $PUBLIC_IP" | tee -a "$LOG_MAIN"
  export PUBLIC_IP

  if [ -f "$CLUSTER_IP_FILE" ]; then
    echo "Cluster IP file found" | tee -a "$LOG_MAIN"

    # Read file line by line
    while IFS=":" read -r IP ROLE HASH || [[ -n "$IP" ]]; do
      echo "Reading line: IP=$IP, ROLE=$ROLE, HASH=$HASH" | tee -a "$LOG_MAIN"

      # Check if IPs match
      if [ "$IP" != "$PUBLIC_IP" ]; then
        echo "IP does not match. Skipping to next line..." | tee -a "$LOG_MAIN"
        continue
      fi

      echo "IP match found" | tee -a "$LOG_MAIN"

      # Perform actions based on the role
      if [ "$ROLE" == "MASTER" ]; then
        echo "This host is a MASTER" | tee -a "$LOG_MAIN"
        echo "$(date)"

        if [ -f "$PID2_FILE" ]; then
    PID2=$(cat "$PID2_FILE")

    if ! ps -p "$PID2" > /dev/null; then
        echo "Process $PID2 is not running. Starting...(PID2)"
        ("$@" | tee -a "$LOG_MAIN") 2>&1 & echo $! > "$PID2_FILE"
    else
        echo "Process $PID2 is already running. Doing nothing.(PID2)"
    fi
else
    echo "PID2 file does not exist. Starting..."
    ("$@" | tee -a "$LOG_MAIN") 2>&1 & echo $! > "$PID2_FILE"
fi

        # Break the reading loop
        break

      elif [ "$ROLE" == "SECONDARY" ]; then
        echo "This host is a SECONDARY" | tee -a "$LOG_MAIN"
        echo "$(date)"
        echo "Sending stop signal to potential live minecraft server"

        # Perform actions for secondary
        if rcon-cli "stop" >> "$LOG_STOP" 2>&1; then
          echo "MC stop command successfully initiated"
        fi
        sleep 10

        # Find the latest tar file
        latest_tar=$(ls -t "$BACKUP_SOURCE_DIR" 2>/dev/null | head -n 1)
        echo "$latest_tar"

        if [ -z "$latest_tar" ]; then
          echo "No backup file found in $BACKUP_SOURCE_DIR"
        fi

        if mkdir -p /tmp/restored; then
          echo "/tmp/restored created.."
        fi

        cd "$BACKUP_SOURCE_DIR"

        # Extract the contents to the extraction directory
        if tar -xf "$latest_tar" -C "$EXTRACTION_DIR"; then
          echo "tar extracted successfully"
        else
          echo "Failed to extract tar file" >&2
        fi

        # Check if the files in /data/world and /data/plugin match the files in the latest tar
        if ! diff -qr "$EXTRACTION_DIR/data/world" /data/world >/dev/null || ! diff -qr "$EXTRACTION_DIR/data/plugins" /data/plugins >/dev/null; then

          # Copy the extracted directories directly to /data if they are not the same
          if rsync -av "$EXTRACTION_DIR/data/world/" /data/world; then
            echo "world folder was successfully copied to /data"
          else
            echo "Failed to copy world folder" >&2
          fi

          if rsync -av "$EXTRACTION_DIR/data/plugins/" /data/plugins; then
            echo "plugins folder was successfully copied to /data"
          else
            echo "Failed to copy plugins folder" >&2
          fi
        else
          echo "Files in /data/world and /data/plugin match the files in the latest tar. No files were moved."
        fi

        # Clean up the extraction directory
        rm -r "$EXTRACTION_DIR"
        cd /

      else
        echo "Role is neither MASTER nor SECONDARY" | tee -a "$LOG_MAIN"
        echo "Sleep for 5 second"
      fi
    done < <(cat "$CLUSTER_IP_FILE"; echo)
  else
    echo "Cluster IP file not found" | tee -a "$LOG_MAIN"
  fi

  # Sleep before checking again
  echo "Sleeping for 60 seconds before checking again" | tee -a "$LOG_MAIN"
  sleep 60
done
