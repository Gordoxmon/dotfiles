#!/bin/bash

IP=$(curl -s https://api.ipify.org)
ITEM_ID=$(bw list items --search "HomeIP" | jq -r '.[0].id')

bw get item $ITEM_ID | \
jq --arg ip "$IP" '.notes = $ip' | \
bw encode | \
bw edit item $ITEM_ID

