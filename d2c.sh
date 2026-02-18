#!/bin/bash

config_file_dir="/etc/d2c_dravee/"
cloudflare_base="https://api.cloudflare.com/client/v4"

print_usage() {
    echo '
    d2c (Dynamic DNS Cloudflare): Dynamic IPv4/6 records for Cloudflare.

    Usage: d2c.sh

    `d2c` UPDATES existing records. Please, create them in Cloudflare Dashboard before running this script.

    By default, configuration files are read from `/etc/d2c_dravee/` directory. Use `--config <dir>` or `-c <dir>` to override.
    E.g., `d2c.sh --config /path/to/config/`.

    Example config (JSON now):

    {
      "api": {
        "zone-id": "<zone id>",
        "api-key": "<api key>"
      },
      "dns": [
        {"name": "test.example.com", "proxy": false},
        {"name": "test2.example.com", "proxy": true},
        {"name": "test-ipv6.example.com", "proxy": false, "ipv6": true}
      ]
    }
'
}

# print usage if requested
if [[ "$1" =~ ^(-h|--help|help)$ ]]; then
    print_usage
    exit 0
fi

# override config dir
if [[ "$1" =~ ^(-c|--config)$ ]]; then
    config_file_dir="$2"
    [[ -z "$config_file_dir" ]] && config_file_dir="/etc/d2c_dravee/"
fi

# check dependencies
for cmd in curl jq; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "Error: '$cmd' is required." >&2
        exit 1
    fi
done

# create config dir if not exists
[[ ! -d "$config_file_dir" ]] && { sudo mkdir -p "$config_file_dir"; echo "Created ${config_file_dir}. Please fill config files."; exit 0; }

# get public IPs
public_ipv4=$(curl -s https://checkip.amazonaws.com/)
public_ipv6=$(curl -s https://api6.ipify.org/)

# process config files
for config_file in $(ls "${config_file_dir}"*.json 2>/dev/null | sort -V); do
    echo "[d2c.sh] Processing $config_file..."

    zone_id=$(jq -r '.api["zone-id"]' "$config_file")
    api_key=$(jq -r '.api["api-key"]' "$config_file")

    # get Cloudflare records
    existing_records=$(curl -s -X GET "$cloudflare_base/zones/$zone_id/dns_records" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        | jq -c '.result[] | select(.type=="A" or .type=="AAAA")')

    # read config DNS records
    config_records=$(jq -c '.dns[]' "$config_file")

    # iterate Cloudflare records
    while read -r record; do
        r_id=$(jq -r '.id' <<<"$record")
        r_name=$(jq -r '.name' <<<"$record")
        r_type=$(jq -r '.type' <<<"$record")
        r_content=$(jq -r '.content' <<<"$record")
        r_ttl=$(jq -r '.ttl' <<<"$record")

        while read -r c_record; do
            c_name=$(jq -r '.name' <<<"$c_record")
            c_proxy=$(jq -r '.proxy' <<<"$c_record")
            c_ipv6=$(jq -r '.ipv6 // false' <<<"$c_record")

            if $c_ipv6; then
                c_type="AAAA"
                public_ip=$public_ipv6
            else
                c_type="A"
                public_ip=$public_ipv4
            fi

            [[ -z "$public_ipv6" && "$c_type" == "AAAA" ]] && { echo "[d2c.sh] WARNING: No IPv6 for $c_name"; continue; }

            if [[ "$r_name" == "$c_name" && "$r_type" == "$c_type" ]]; then
                if [[ "$r_content" != "$public_ip" ]]; then
                    curl -s -X PATCH "$cloudflare_base/zones/$zone_id/dns_records/$r_id" \
                        -H "Authorization: Bearer $api_key" \
                        -H "Content-Type: application/json" \
                        --data "{\"content\":\"$public_ip\",\"name\":\"$c_name\",\"proxied\":$c_proxy,\"type\":\"$c_type\",\"comment\":\"Managed by d2c.sh\",\"ttl\":$r_ttl}" \
                        >/dev/null
                    echo "[d2c.sh] Updated: $c_name -> $public_ip"
                else
                    echo "[d2c.sh] No change: $c_name"
                fi
            fi
        done <<<"$config_records"
    done <<<"$existing_records"
done

echo "All files processed."
