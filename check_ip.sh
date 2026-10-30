#!/bin/bash

set -euo pipefail

# colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

declare -A results

# utils
http_check() {
    local name=$1 url=$2 expected=${3:-200} timeout=10
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$timeout" -A "Mozilla/5.0" "$url" 2>/dev/null || echo "000")
    if [[ "$code" == "$expected" ]]; then
        results[$name]="${GREEN}Available${NC}"
    elif [[ "$code" == "403" || "$code" == "429" || "$code" == "503" ]]; then
        results[$name]="${YELLOW}Captcha/Block${NC}"
    else
        results[$name]="${RED}Unavailable ($code)${NC}"
    fi
}

dns_check() {
    local name=$1 host=$2
    if dig +short +time=5 "$host" @1.1.1.1 | grep -qE '^[0-9]+\.'; then
        results[$name]="${GREEN}Available${NC}"
    else
        results[$name]="${RED}Unavailable${NC}"
    fi
}

# ip
echo "Detecting IP..."
IP=$(curl -s --max-time 10 https://api.ipify.org || echo "Undetermined")
COUNTRY=$(curl -s --max-time 10 "https://ipapi.co/${IP}/country_name" 2>/dev/null || echo "?")
ASN=$(curl -s --max-time 10 "https://ipapi.co/${IP}/org" 2>/dev/null || echo "?")
echo -e "IP: ${GREEN}$IP${NC} | Country: $COUNTRY | ASN: $ASN"

# speedtest
echo "Running speed test..."
if command -v speedtest-cli &>/dev/null; then
    speedtest-cli --simple --timeout 30 2>/dev/null | sed 's/^/  /'
elif command -v fast &>/dev/null; then
    fast 2>/dev/null | sed 's/^/  /'
else
    # fallbacks
    DL=$(curl -s -o /dev/null -w "%{speed_download}" --max-time 20 https://speed.cloudflare.com/__down?bytes=10485760 2>/dev/null || echo 0)
    UL=$(curl -s -o /dev/null -w "%{speed_upload}" --max-time 20 -T /dev/zero https://speed.cloudflare.com/__up 2>/dev/null || echo 0)
    printf "  Download: %.2f Mbps\n" "$(echo "$DL*8/1000000" | bc -l)"
    printf "  Upload:   %.2f Mbps\n" "$(echo "$UL*8/1000000" | bc -l)"
fi

# check
echo "Checking services..."

# AI
http_check "Grok (x.ai)" "https://api.x.ai/v1/models" 200
http_check "Anthropic" "https://api.anthropic.com/v1/messages" 401  # 401 = API works, key required
http_check "Gemini" "https://generativelanguage.googleapis.com/v1beta/models" 200
http_check "Perplexity" "https://api.perplexity.ai/models" 401
http_check "ChatGPT" "https://api.openai.com/v1/models" 401

# social
http_check "Instagram" "https://www.instagram.com/" 200
http_check "Twitter/X" "https://x.com/" 200
http_check "Reddit" "https://www.reddit.com/" 200
http_check "Spotify" "https://open.spotify.com/" 200

# dev / tools
http_check "GitHub" "https://github.com/" 200
http_check "GitLab" "https://gitlab.com/" 200
http_check "Cloudflare Challenge" "https://challenges.cloudflare.com/cdn-cgi/trace" 200
http_check "IPQualityScore" "https://www.ipqualityscore.com/api/json/ip/$(curl -s ipinfo.io/ip 2>/dev/null)/check" 200
http_check "MaxMind GeoIP" "https://geoip.maxmind.com/geoip/v2.1/country/me" 401  # 401 = works, license key required

# google ecosystem
http_check "Google Search" "https://www.google.com/" 200
http_check "YouTube" "https://www.youtube.com/" 200
http_check "Gmail" "https://mail.google.com/" 200

# DNS checks
dns_check "Google DNS" "google.com"
dns_check "Cloudflare DNS" "cloudflare.com"

# table
print_table() {
    local col1=30 col2=20
    printf "\n%*s | %*s\n" "$col1" "Service" "$col2" "Status"
    printf "%*s-+-%*s\n" "$col1" "" "$col2" "" | tr ' ' '-'
    for k in "${!results[@]}"; do
        printf "%*s | %b\n" "$col1" "$k" "${results[$k]}"
    done
    echo
}
print_table

# --- Summary ---
blocked=0
captcha=0
for v in "${results[@]}"; do
    [[ "$v" == *"Unavailable"* ]] && ((blocked++))
    [[ "$v" == *"Captcha"* ]] && ((captcha++))
done
echo "Summary: Blocked: $blocked | Captcha/Restrictions: $captcha | Total checks: ${#results[@]}"
[[ $blocked -gt 0 || $captcha -gt 0 ]] && echo -e "${YELLOW}⚠ IP likely in blocklists / needs review${NC}" || echo -e "${GREEN}✓ IP looks clean${NC}"