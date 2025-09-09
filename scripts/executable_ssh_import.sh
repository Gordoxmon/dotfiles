#!/usr/bin/env bash
set -euo pipefail

# Unlock Bitwarden if necessary
if [ -z "${BW_SESSION:-}" ]; then
    export BW_SESSION="$(bw unlock --raw)"
fi

SSH_DIR="$HOME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Loading animation function
loading_animation() {
    local pid="$1"
    local message="$2"
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 "$pid" 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r%s %s" "${spinstr:i:1}" "$message"
            sleep "$delay"
        done
    done
    printf "\r"
}

# Run bw list items in background and capture output
TMPFILE="$(mktemp)"
(
    # Include items that have either a public or private SSH key
    bw list items \
    | jq -r '.[] | select(.type == 5 and (.sshKey.publicKey != null or .sshKey.privateKey != null)) | .id + "|" + .name'
) > "$TMPFILE" &
PID=$!
loading_animation $PID "Listing SSH keys..."
wait $PID

LIST_OUTPUT="$(<"$TMPFILE")"
rm -f "$TMPFILE"

# Convert to array safely
readarray -t ITEMS <<< "$LIST_OUTPUT"

# If no items, exit early
if (( ${#ITEMS[@]} == 0 )); then
    echo "No SSH key items found in Bitwarden."
    exit 0
fi

# Show options to the user
echo -e "\nSelect SSH keys to import (e.g., 1,3,5 or 2-4 or A for all):"
echo "[A] All"
for i in "${!ITEMS[@]}"; do
    NAME="$(echo "${ITEMS[$i]}" | cut -d'|' -f2)"
    echo "[$((i+1))] $NAME"
done

# Read user selection with 30s timeout; if invalid or empty, use All
SELECTION=""
read -t 30 -rp "Choice: " SELECTION || SELECTION="A"
if [[ -z "$SELECTION" ]]; then SELECTION="A"; fi

SELECTED_ITEMS=()
if [[ "$SELECTION" =~ ^[Aa]$ ]]; then
    SELECTED_ITEMS=("${ITEMS[@]}")
else
    IFS=',' read -r -a TOKENS <<< "$SELECTION"
    for TOKEN in "${TOKENS[@]}"; do
        TOKEN="$(echo "$TOKEN" | xargs)" # trim
        if [[ "$TOKEN" =~ - ]]; then
            START=${TOKEN%-*}
            END=${TOKEN#*-}
            if ! [[ "$START" =~ ^[0-9]+$ && "$END" =~ ^[0-9]+$ ]] || (( START < 1 || END > ${#ITEMS[@]} || START > END )); then
                echo "Invalid selection, importing all keys."
                SELECTED_ITEMS=("${ITEMS[@]}")
                break
            fi
            for ((i=START; i<=END; i++)); do
                SELECTED_ITEMS+=("${ITEMS[$((i-1))]}")
            done
        else
            if ! [[ "$TOKEN" =~ ^[0-9]+$ ]] || (( TOKEN < 1 || TOKEN > ${#ITEMS[@]} )); then
                echo "Invalid selection, importing all keys."
                SELECTED_ITEMS=("${ITEMS[@]}")
                break
            fi
            SELECTED_ITEMS+=("${ITEMS[$((TOKEN-1))]}")
        fi
    done
fi

# Remove duplicates
mapfile -t SELECTED_ITEMS < <(printf "%s\n" "${SELECTED_ITEMS[@]}" | awk '!seen[$0]++')

# Extract selected keys with loading animation and newline after each
for ITEM in "${SELECTED_ITEMS[@]}"; do
    ID="$(echo "$ITEM" | cut -d'|' -f1)"
    NAME="$(echo "$ITEM" | cut -d'|' -f2)"

    # Optionally sanitize the filename (spaces -> underscores)
    SAFE_NAME="${NAME// /_}"

    (
        JSON="$(bw get item "$ID")"

        PUBLIC_KEY="$(jq -r '.sshKey.publicKey // empty' <<< "$JSON")"
        PRIVATE_KEY="$(jq -r '.sshKey.privateKey // empty' <<< "$JSON")"

        # Write private key if present
        if [ -n "$PRIVATE_KEY" ]; then
            PRIV_FILE="$SSH_DIR/$SAFE_NAME"
            printf "%s\n" "$PRIVATE_KEY" > "$PRIV_FILE"
            chmod 600 "$PRIV_FILE"
        fi

        # Write public key if present
        if [ -n "$PUBLIC_KEY" ]; then
            PUB_FILE="$SSH_DIR/$SAFE_NAME.pub"
            printf "%s\n" "$PUBLIC_KEY" > "$PUB_FILE"
            chmod 644 "$PUB_FILE"
        fi
    ) &
    PID=$!
    loading_animation $PID "Extracting $NAME..."
    wait $PID
    echo
done

echo -e "\nSelected SSH keys have been extracted to $SSH_DIR!"
echo "• Private keys saved as ~/.ssh/<name> (chmod 600)"
echo "• Public keys saved as  ~/.ssh/<name>.pub (chmod 644)"

