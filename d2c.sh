#!/bin/bash

config_file_dir="/etc/d2c/"
cloudflare_base="https://api.cloudflare.com/client/v4"

# print usage text and exit
print_usage() {
    echo '
    d2c (Dynamic DNS Cloudflare): Dynamic IPv4/6 records for Cloudflare.

    Usage: d2c.sh

    `d2c` UPDATES existing records. Please, create them in Cloudflare Dashboard before running this script.

    By default, configuration files are read from `/etc/d2c/` directory. Use `--config <dir>` or `-c <dir>` to override.
    E.g., `d2c.sh --config /path/to/config/`.

    ```
    [api]
    zone-id = "<zone id>"
    api-key = "<api key>"

    [[dns]]
    name = "test.example.com"
    proxy = false

    [[dns]]
    name = "test2.example.com"
    proxy = true

    [[dns]]
    name = "test-ipv6.example.com"
    proxy = false
    ipv6 = true # Optional, for 'AAAA' records
    ```
'
}

# print usage if requested
if [ "$1" = "help" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    print_usage
    exit
fi

# override config dir if provided
if [ "$1" = "--config" ] || [ "$1" = "-c" ]; then
    config_file_dir="$2"
    if [ -z "$config_file_dir" ]; then
        config_file_dir="/etc/d2c/"
    fi
fi

# ensure yq is installed
if ! command -v yq > /dev/null 2>&1; then
    echo "Error: 'yq' required and not found."
    echo "Please install: https://github.com/mikefarah/yq."
    exit 1
fi

# ensure curl is installed
if ! command -v curl > /dev/null 2>&1; then
    echo "Error: 'curl' required and not found."
    echo "Please install: https://curl.se/download.html or through your package manager."
    exit 1
fi

# create config dir if not exists
if [ ! -d $config_file_dir ]; then
    sudo mkdir $config_file_dir
    echo "Created ${config_file_dir}. Please, fill the configuration files."
    exit 0
fi

# get my public IP
public_ipv4=$(curl --silent https://checkip.amazonaws.com/)
public_ipv6=$(curl --silent https://api6.ipify.org/)

# process each config file in sorted order
for config_file in $(ls ${config_file_dir}*.toml 2>/dev/null | sort -V); do
    echo "[d2c.sh] Processing ${config_file}..."

    # read zone-id and api-key from config file
    zone_id=$(yq '.api.zone-id' ${config_file})
    api_key=$(yq '.api.api-key' ${config_file})

    # read gotify config
    gotify_enabled=$(yq '.gotify.enabled' ${config_file})
    gotify_endpoint=$(yq '.gotify.endpoint' ${config_file})
    gotify_token=$(yq '.gotify.token' ${config_file})

    # read telegram config
    telegram_enabled=$(yq '.telegram.enabled' ${config_file})
    telegram_token=$(yq '.telegram.token' ${config_file})
    telegram_chat_id=$(yq '.telegram.chat_id' ${config_file})

    # get records from Cloudflare
    existing_records_raw=$(curl --silent --request GET \
        --url ${cloudflare_base}/zones/${zone_id}/dns_records \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer ${api_key}" \
        | yq -oj -I=0 '.result[] | select(.type == "A" or .type == "AAAA") | [.id, .name, .ttl, .content, .type]'
    )

    # get records defined in config file
    readarray config_records < <(yq -oj -I=0 '.dns[]' ${config_file})

    # iterate Cloudflare records
    # for each record, check if it exists in config file
    # if it does, update the record
    for record in ${existing_records_raw[@]}; do
        id=$(yq '.[0]' <<< "${record}")
        name=$(yq '.[1]' <<< "${record}")
        ttl=$(yq '.[2]' <<< "${record}")
        content=$(yq '.[3]' <<< "${record}")
        type=$(yq '.[4]' <<< "${record}")

        for c_record in ${config_records[@]}; do
            c_name=$(yq '.name' <<< ${c_record})
            c_proxy=$(yq '.proxy' <<< ${c_record})
            c_ipv6=$(yq '.ipv6' <<< ${c_record})

            if [ "$c_ipv6" = true ]; then
                c_type="AAAA"
                public_ip=$public_ipv6
            else
                c_type="A"
                public_ip=$public_ipv4
            fi

            # print warning if AAAA record is configured but no ipv6 is available
            if [ -z "$public_ipv6" ] && [ "$c_type" = "AAAA" ]; then
                echo "[d2c.sh] WARNING! AAAA records are configured, but no IPv6 address is available. Skipping."
                continue
            fi

            if [ "$name" = "$c_name" ] && [ "$type" = "$c_type" ]; then
                if [ "$public_ip" != "$content" ]; then
                    # update DNS
                    curl --silent --request PATCH \
                    --url "${cloudflare_base}/zones/${zone_id}/dns_records/${id}" \
                    --header 'Content-Type: application/json' \
                    --header "Authorization: Bearer ${api_key}" \
                    --data '{
                        "content": "'${public_ip}'",
                        "name": "'${name}'",
                        "proxied": '${c_proxy}',
                        "type": "'${c_type}'",
                        "comment": "Managed by d2c.sh",
                        "ttl": '${ttl}'
                    }' > /dev/null

                    echo "[d2c.sh] OK: ${name}"

                    # check if gotify is enabled
                    if [ "$gotify_enabled" = true ]; then
                        # send changed ip notification
                        status_code=$(curl --silent --output /dev/null --write-out "%{http_code}" "${gotify_endpoint}/message?token=${gotify_token}" -F "title=[d2c.sh] ${name} has changed" -F "message=Public IP for ${name} has changed (${public_ip})" -F "priority=5")

                        if [[ "$status_code" -ne 200 ]]; then
                            echo "[d2c.sh] Failed to send Gotify notification"
                        fi
                    fi

                    # check if Telegram is enabled
                    if [ "$telegram_enabled" = true ]; then
                        # send changed ip notification
                        status_code=$(curl --silent --output /dev/null --write-out "%{http_code}" https://api.telegram.org/bot"${telegram_token}"/sendMessage -d chat_id="${telegram_chat_id}" -d disable_web_page_preview=true -d text="[d2c.sh] Public IP for ${name} has changed (${public_ip})")

                        if [[ "$status_code" -ne 200 ]]; then
                            echo "[d2c.sh] Failed to send Telegram notification"
                        fi
                    fi
                else
                    echo "[d2c.sh] ${name} did not change"
                fi
            fi
        done
    done
done

echo "All files processed."
