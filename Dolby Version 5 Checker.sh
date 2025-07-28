#!/bin/bash
DISCORD_WEBHOOK="Enter Discord Webhook URL Here"

# Set a specific directory to search (change this to your desired path)
SEARCH_DIR="${1:-"Enter Default Directory here"}"

# Set log directory
LOG_DIR="Enter Log Directory here"
mkdir -p "$LOG_DIR"

# Persistent log of scanned files
SCANNED_LOG="$LOG_DIR/scanned_files.log"
touch "$SCANNED_LOG"

# Variables for match log file
NEW_LOG=""
LOG_CREATED=false
FOUND=0

echo "🔍 Searching in: $SEARCH_DIR"
echo "🗂 Using scanned file log: $SCANNED_LOG"
echo

# Generate sorted file list
find "$SEARCH_DIR" -type f -iname "*.mkv" ! -path "/mnt/tank/media/trash/*" | sort > /tmp/dv5_filelist.txt

# Loop over files using redirection (not a subshell!)
while read -r file; do
    # Skip if already scanned
    if grep -Fxq "$file" "$SCANNED_LOG"; then
        continue
    fi

    # Show progress in terminal
    echo -ne "Checking: $file\r"

if ffprobe "$file" 2>&1 | grep -q "DOVI configuration record:.*profile: 5"; then
    # Matched file processing
    if [ "$LOG_CREATED" = false ]; then
        NEW_LOG="$LOG_DIR/dv5_mkv_log_$(date +'%Y-%m-%d_%H-%M-%S').log"
        touch "$NEW_LOG"
        LOG_CREATED=true
        echo "📝 Logging new matches to: $NEW_LOG"
    fi
    echo -ne "\r\033[K"
    echo "✔ Dolby Vision profile 5 found: $file"
    echo "$file" >> "$NEW_LOG"
    ((FOUND++))
else
    # Only log as scanned if no match
    echo "$file" >> "$SCANNED_LOG"
fi

done < /tmp/dv5_filelist.txt

rm -f /tmp/dv5_filelist.txt

# Clear the last line
echo -ne "\r\033[K"

# Final message
if [ "$FOUND" -gt 0 ]; then
    echo "✅ Done. $FOUND new matching file(s) written to: $NEW_LOG"

# Read all matched files (full paths), but only use filenames for Discord
MATCHED_FILES=$(cat "$NEW_LOG")
MAX_CHARS=1900
CHUNK=""
MESSAGE_COUNT=1
CHUNKS=()

while IFS= read -r fullpath; do
    filename=$(basename "$fullpath")
    if (( ${#CHUNK} + ${#filename} + 1 > MAX_CHARS )); then
        CHUNKS+=("$CHUNK")
        CHUNK=""
    fi
    CHUNK+="$filename"$'\n'
done <<< "$MATCHED_FILES"

# Add final chunk if any
if [[ -n "$CHUNK" ]]; then
    CHUNKS+=("$CHUNK")
fi

# Send all chunks
TOTAL_PARTS=${#CHUNKS[@]}
for i in "${!CHUNKS[@]}"; do
    part_num=$((i + 1))
    msg_header="🎬 Dolby Vision Profile 5"
    if [[ $TOTAL_PARTS -gt 1 ]]; then
        msg_header+=" (part $part_num)"
    fi
    payload=$(jq -nc --arg msg "$msg_header"$'\n```'"${CHUNKS[$i]}"$'```' '{content: $msg}')
    curl -s -H "Content-Type: application/json" \
         -X POST \
         -d "$payload" \
         "$DISCORD_WEBHOOK"
done

else
    echo "✅ Done. No new Dolby Vision profile 5 matches found."
fi
