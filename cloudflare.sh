#!/bin/bash

zoneId=$1
cfToken=$2

curl -s --request POST \
    --url https://api.cloudflare.com/client/v4/zones/${zoneId}/purge_cache \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer ${cfToken}" \
    --data '{"purge_everything": true}'
~
