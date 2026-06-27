#!/usr/bin/env bash

# ============================
# Configurable parameters
# ============================

SUBNET="192.168.1"
START=50
END=130
LOGFILE="/tmp/network_inventory.log"
STATIC_MAP="$HOME/static_ip_map.csv"
VENDOR_MAP="$HOME/mac_prefixes.csv"

# ============================
# Init
# ============================

: > "$LOGFILE"

declare -A static_hostname
declare -A static_mac
declare -A vendor_map

# ============================
# Load static IP map
# Format: IP,Hostname,MAC
# ============================

if [[ -f "$STATIC_MAP" ]]; then
    while IFS=',' read -r ip name mac; do
        if [[ -n "$ip" ]]; then
            static_hostname["$ip"]="$name"
            static_mac["$ip"]="$mac"
        fi
    done < <(grep -v '^#' "$STATIC_MAP")
fi

# ============================
# Load vendor map
# Format: PREFIX,Vendor Name
# PREFIX like: AA:BB:CC
# ============================

if [[ -f "$VENDOR_MAP" ]]; then
    while IFS=',' read -r prefix name; do
        if [[ -n "$prefix" ]]; then
            upper_prefix="${prefix^^}"
            vendor_map["$upper_prefix"]="$name"
        fi
    done < <(grep -v '^#' "$VENDOR_MAP")
fi

# ============================
# Helper: resolve hostname
# ============================

resolve_hostname() {
    local ip host

    ip="$1"
    host=$(dig -x "$ip" +short 2>/dev/null | sed 's/\.$//' | head -n1)
    if [[ -n "$host" ]]; then
        echo "$host"
        return
    fi

    host=$(avahi-resolve-address "$ip" 2>/dev/null | awk '{print $2}')
    if [[ -n "$host" ]]; then
        echo "$host"
        return
    fi

    host=$(getent hosts "$ip" 2>/dev/null | awk '{print $2}')
    if [[ -n "$host" ]]; then
        echo "$host"
        return
    fi

    host=$(host "$ip" 2>/dev/null | awk '/pointer/ {print $NF}' | sed 's/\.$//')
    if [[ -n "$host" ]]; then
        echo "$host"
        return
    fi

    echo ""
}

# ============================
# Helper: resolve NetBIOS
# ============================

resolve_netbios() {
    local ip nb

    ip="$1"
    nb=$(nmblookup -A "$ip" 2>/dev/null | awk '/<00> -/ && $1!="WORKGROUP" {print $1; exit}')
    if [[ -n "$nb" ]]; then
        echo "$nb"
    else
        echo ""
    fi
}

# ============================
# Helper: resolve MAC
# (no local special-case; your ARP works)
# ============================

resolve_mac() {
    local ip mac local_ip

    ip="$1"
    local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    if [[ "$ip" == "$local_ip" ]]; then
        # Local machine: ARP will not contain our own MAC
        mac=$(ip link show 2>/dev/null | awk '/ether/ {print $2; exit}')
    else
        mac=$(ip neigh show "$ip" 2>/dev/null | awk '{print $5}')
    fi

    mac=$(echo "$mac" | tr -d '\r\n')

    if [[ -z "$mac" || "$mac" == "incomplete" ]]; then
        mac="N/A"
    fi

    echo "$mac"
}

# ============================
# Helper: resolve vendor
# ============================

resolve_vendor() {
    local mac prefix upper_prefix vendor

    mac="$1"
    if [[ "$mac" == "N/A" ]]; then
        echo "Unknown"
        return
    fi

    prefix="${mac:0:8}"
    upper_prefix="${prefix^^}"
    vendor="${vendor_map[$upper_prefix]}"

    if [[ -z "$vendor" ]]; then
        echo "Unknown"
    else
        echo "$vendor"
    fi
}

fallback_hostname_from_mac() {
    case "$1" in
        ac:ee:9e:6a:d9:a6) echo "Galaxy-Tab-A" ;;
        0c:2f:b0:15:31:a0) echo "Igor" ;;
        *) echo "$HOST" ;;
    esac
}

# ============================
# Scan
# ============================

echo "🔍 Scanning $SUBNET.$START to $SUBNET.$END..." | tee -a "$LOGFILE"
set +m

TIMEFORMAT=$'\n⏱️ Elapsed: %3lR  # network inventory'
time {
MAX_JOBS=20
job_count=0

for ((i = START; i <= END; i++)); do
    IP="$SUBNET.$i"

    scan_host() {
        if ping -c 1 -W 1 "$IP" &>/dev/null; then
            sleep 1

            MAC=$(resolve_mac "$IP")

            NETBIOS=$(resolve_netbios "$IP")
            if [[ -z "$NETBIOS" ]]; then
                NETBIOS="N/A"
            fi

            HOST=$(resolve_hostname "$IP")
            if [[ -z "$HOST" ]]; then
                if [[ "$NETBIOS" != "N/A" ]]; then
                    HOST="$NETBIOS (NetBIOS)"
                else
                    HOST="N/A"
                fi
            fi

            if [[ "$HOST" == "N/A" ]]; then
                if [[ -z "$HOST" ]]; then
                    HOST="N/A"
                fi
            fi
            HOST=$(fallback_hostname_from_mac "$MAC")

            VENDOR=$(resolve_vendor "$MAC")

            printf '✅ %s is active\n' "$IP" | tee -a "$LOGFILE"
            printf '   ↪ %-9s %s\n' "Hostname:" "$HOST"    | tee -a "$LOGFILE"
            printf '   ↪ %-9s %s\n' "NetBIOS:"  "$NETBIOS" | tee -a "$LOGFILE"
            printf '   ↪ %-9s %s\n' "MAC:"      "$MAC"     | tee -a "$LOGFILE"
            printf '   ↪ %-9s %s\n' "Vendor:"   "$VENDOR"  | tee -a "$LOGFILE"

            expected_host="${static_hostname[$IP]}"
            expected_mac="${static_mac[$IP]}"

            if [[ -n "$expected_host" ]]; then
                shopt -s nocasematch
                if [[ "${HOST,,}" != "${expected_host,,}" ]]; then
                    echo "   ⚠️ Hostname mismatch: expected $expected_host" | tee -a "$LOGFILE"
                fi
                shopt -u nocasematch
            fi

            if [[ -n "$expected_mac" && "$MAC" != "$expected_mac" ]]; then
                echo "   ⚠️ MAC mismatch: expected $expected_mac" | tee -a "$LOGFILE"
            fi
        fi
    }

    scan_host &

    job_count=$((job_count + 1))
    if [[ $job_count -ge $MAX_JOBS ]]; then
        wait -n
        job_count=$((job_count - 1))
    fi
done

wait
}

printf '\n📄 Inventory saved to %s\n' "$LOGFILE"
