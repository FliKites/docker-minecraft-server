#!/bin/bash
LOG_DIR="/var/logs/minecraft"
PID_FILE="$LOG_DIR/minecraft-process.txt"
LOG_FILE="$LOG_DIR/mc-init.txt"
LOG_STOP="$LOG_DIR/master-reload-stop.txt"
EXPECTED_LOG_LINE="RCON running on 0.0.0.0:25575"
BACKUP_INTERVAL_MINUTES=${BACKUP_INTERVAL:=5} # default to 1 minute if not set
BACKUP_INTERVAL_SECONDS=$((BACKUP_INTERVAL_MINUTES * 60))
FILE="/data/bukkit.yml"
BACKUP_SOURCE_DIR="/root/backup"
# Create directories if they don't exist
mkdir -p $LOG_DIR && mkdir -p /tmp/restored
# Logging
touch /mc-init.txt
cd /

mkdir -p /root/backup
#sleep 10
EXTRACTION_DIR="/tmp/restored"

# Find the latest tar file
latest_tar=$(ls -t $BACKUP_SOURCE_DIR 2>/dev/null | head -n 1)
echo "$latest_tar"

if [ -z "$latest_tar" ]; then
    echo "No backup file found in $BACKUP_SOURCE_DIR"
fi

if  mkdir -p $EXTRACTION_DIR; then
             echo "$EXTRACTION_DIR created.."
fi

cd $BACKUP_SOURCE_DIR

# Extract the contents to the extraction directory
if tar -xf "$latest_tar" -C $EXTRACTION_DIR; then
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

            # Stop the minecraft server
        #if rcon-cli "stop" >> "$LOG_STOP" 2>&1; then
        #  echo "MC stop command successfully initiated"
        #fi

    sleep 10
    if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")

            if ! ps -p "$PID" > /dev/null; then
              echo "Process $PID is not running. Starting...(PID)"
              /start > "$LOG_FILE" 2>&1 & echo $! > "$PID_FILE"
            else
              echo "Process $PID is already running. Doing nothing. (PID)"

            fi
          else
            echo "PID file does not exist. Starting..."
            /start > "$LOG_FILE" 2>&1 & echo $! > "$PID_FILE"
          fi

else
    echo "Files in /data/world and /data/plugin match the files in the latest tar. No files were moved."
    echo "Checking Minecraft Process to see if it is running..."
    if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")

            if ! ps -p "$PID" > /dev/null; then
              echo "Process $PID is not running. Starting...(PID)"
              /start > "$LOG_FILE" 2>&1 & echo $! > "$PID_FILE"
            else
              echo "Process $PID is already running. Doing nothing. (PID)"
            fi
          else
            echo "PID file does not exist. Starting..."
            /start > "$LOG_FILE" 2>&1 & echo $! > "$PID_FILE"
          fi

fi

# Clean up the extraction directory
rm -r "$EXTRACTION_DIR"

cd /

# Wait for Minecraft to start
while true; do
    # Get the last line of the log file
    last_line=$(tail -n 30 "$LOG_FILE")

    # Check if the last line contains the expected log line
    if [[ $last_line == *"$EXPECTED_LOG_LINE"* ]]; then
        echo "Last line of log file contains the expected log line."
        break
    fi

    # Wait for a moment before the next check
    sleep 5
done
# Get the line containing rcon.password
password_line=$(grep "rcon.password=" /data/server.properties)

# Extract the password value
password=${password_line#*=}

# Replace the content of /root/.rcon-cli.env with the extracted password
echo "password=$password" > /root/.rcon-cli.env

echo "Password updated in /root/.rcon-cli.env"
# Command to execute
COMMAND="lp user $MINECRAFT_USERNAME permission set luckperms.* true"
COMMAND2="lp user $MINECRAFT_USERNAME permission set drivebackup.* true"
COMMAND3="lp user $MINECRAFT_USERNAME permission set noteleks.* true"
COMMAND4="op $MINECRAFT_USERNAME"
# Connect to RCON and execute the command
if echo "$COMMAND" | rcon-cli; then
echo "LuckPerms permissions were set"
else
echo "LuckPerms permissions not set"
fi
# Connect to RCON and execute the command
if echo "$COMMAND2" | rcon-cli; then
echo "DriveBackupV2 permissions were set"
else
echo "DriveBackupV2 permissions not set"
fi
# Connect to RCON and execute the command
if echo "$COMMAND3" | rcon-cli; then
echo "Noteleks permissions were set"
else
echo "Noteleks permissions not set"
fi
if echo "$COMMAND4" | rcon-cli; then	
echo "User set as operator"	
else	
echo "User NOT set as operator"	
fi

BACKUP_DIR="/root/backup"
#MINECRAFT_DIR="/data"
MINECRAFT_DIR="/data/world /data/plugins"
#SERVER_PROPERTIES=/data/server.properties
MAX_BACKUP_SIZE_GB=${MAX_BACKUP_SIZE_GB:-3} # default to 1GB if not set
MAX_BACKUP_SIZE_BYTES=$((MAX_BACKUP_SIZE_GB * 1024 * 1024 * 1024))
SOURCE_DIR=/data
#DESTINATION_DIR=/root/backup

while true; do
# Get the line containing rcon.password
password_line=$(grep "rcon.password=" /data/server.properties)

# Extract the password value
password=${password_line#*=}

# Replace the content of /root/.rcon-cli.env with the extracted password
echo "password=$password" > /root/.rcon-cli.env

echo "Password updated in /root/.rcon-cli.env"

if rcon-cli "save-off"; then
  echo "Successfully executed save-off command"
else
  echo "Failed to execute save-off command" >&2
fi

if rcon-cli "save-all"; then
  echo "Successfully executed save-all command"
else
  echo "Failed to execute save-all command" >&2
fi

sleep 10
# Delete old backups if total size exceeds the max size
TOTAL_SIZE=0
for FILENAME in $(ls -t $BACKUP_DIR/*.tar.gz); do
    FILESIZE=$(stat -c %s "$FILENAME")
    NEW_TOTAL_SIZE=$((TOTAL_SIZE + FILESIZE))

    if (( NEW_TOTAL_SIZE >= MAX_BACKUP_SIZE_BYTES )); then
        echo "Deleting $FILENAME"
        rm "$FILENAME"
    else
        TOTAL_SIZE=$NEW_TOTAL_SIZE
    fi
done

# Create backup
if tar -czf "$BACKUP_DIR/minecraft_backup_$(date +%Y%m%d%H%M).tar.gz" $MINECRAFT_DIR; then
echo "Backup was successfully created in $BACKUP_DIR"
rcon-cli say "Backup successfully created in $BACKUP_DIR"
else
echo "Failed to create backup in /$BACKUP_DIR/backup"
rcon-cli say "Failed to create backup - check flux logs"
fi

#if rsync -au "$SOURCE_DIR" "$DESTINATION_DIR"; then
#    echo "Move latest direcotry - rsync completed successfully."
#else
#    echo "rsync failed. Check the error message for details." >&2
#fi
if rcon-cli "save-on"; then
  echo "Successfully executed save-on command"
  else
  echo "Failed to execute save-on command" >&2
fi
# Wait for the interval specified by the environment variable
echo "The backup loop will execute again in "$BACKUP_INTERVAL_SECONDS" seconds.."
sleep $BACKUP_INTERVAL_SECONDS

done
