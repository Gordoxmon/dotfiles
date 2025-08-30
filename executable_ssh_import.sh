#!/usr/bin/env bash
set -e

# Unlock Bitwarden if necessary
if [ -z "$BW_SESSION" ]; then
    export BW_SESSION=$(bw unlock --raw)
fi

SSH_DIR="$HOME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Loading animation function
loading_animation() {
    local pid=$1
    local message=$2
    local delay=0.1
    local spinstr='|/-\\'
    while kill -0 $pid 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r%s %s" "${spinstr:i:1}" "$message"
            sleep $delay
        done
    done
    printf "\r"  # Clear line after done
}

# Run bw list items in background and capture output
TMPFILE=$(mktemp)
(
    bw list items | jq -r '.[] | select(.type == 5 and .sshKey.privateKey != null) | .id + "|" + .name'
) > "$TMPFILE" &
PID=$!
loading_animation $PID "Listing SSH keys..."
wait $PID

LIST_OUTPUT=$(<"$TMPFILE")
rm -f "$TMPFILE"

# Convert to array safely
readarray -t ITEMS <<< "$LIST_OUTPUT"

# Show options to the user
echo -e "\nSelect SSH keys to import (e.g., 1,3,5 or 2-4 or A for all):"
echo "[A] All"
for i in "${!ITEMS[@]}"; do
    NAME=$(echo "${ITEMS[$i]}" | cut -d'|' -f2)
    echo "[$((i+1))] $NAME"
done

# Read user selection with 30s timeout; if invalid or empty, use All
read -t 30 -rp "Choice: " SELECTION || SELECTION="A"
if [[ -z "$SELECTION" ]]; then SELECTION="A"; fi

SELECTED_ITEMS=()
if [[ "$SELECTION" =~ ^[Aa]$ ]]; then
    SELECTED_ITEMS=(${ITEMS[@]})
else
    TOKENS=(${SELECTION//,/ })
    for TOKEN in "${TOKENS[@]}"; do
        if [[ $TOKEN =~ - ]]; then
            START=${TOKEN%-*}
            END=${TOKEN#*-}
            if (( START < 1 || END > ${#ITEMS[@]} || START > END )); then
                echo "Invalid selection, importing all keys."
                SELECTED_ITEMS=(${ITEMS[@]})
                break
            fi
            for ((i=START; i<=END; i++)); do
                SELECTED_ITEMS+=(${ITEMS[$((i-1))]})
            done
        else
            if (( TOKEN < 1 || TOKEN > ${#ITEMS[@]} )); then
                echo "Invalid selection, importing all keys."
                SELECTED_ITEMS=(${ITEMS[@]})
                break
            fi
            SELECTED_ITEMS+=(${ITEMS[$((TOKEN-1))]})
        fi
    done
fi

# Remove duplicates
SELECTED_ITEMS=($(echo "${SELECTED_ITEMS[@]}" | tr ' ' '\n' | awk '!seen[$0]++' | tr '\n' ' '))

# Extract selected keys with loading animation and newline after each
for ITEM in "${SELECTED_ITEMS[@]}"; do
    ID=$(echo "$ITEM" | cut -d'|' -f1)
    NAME=$(echo "$ITEM" | cut -d'|' -f2)
    (
        PRIVATE_KEY=$(bw get item "$ID" | jq -r '.sshKey.privateKey // empty')
        if [ -n "$PRIVATE_KEY" ]; then
            FILE="$SSH_DIR/$NAME"
            echo "$PRIVATE_KEY" > "$FILE"
            chmod 600 "$FILE"
        fi
    ) &
    PID=$!
    loading_animation $PID "Extracting $NAME..."
    wait $PID
    echo  # newline after each key extraction to prevent overlap
 done

echo -e "\nSelected SSH keys have been extracted to $SSH_DIR!"
