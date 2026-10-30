cat > check_ip.sh << 'EOF'
#!/bin/bash
# Не используем set -e, чтобы не падать на любом ненулевом коде curl

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONNECT_TIMEOUT=5
MAX_TIMEOUT=10
RESULTS=()

log() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERR]${NC} $*"; }

add_result() { RESULTS+=("$1|$2|$3"); }

check_http() {
    local name="$1" url="$2"
    local code body
    code=$(curl -sS -o /dev/null -w "%{http_code}" \
        --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIMEOUT" \
        -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
        -L "$url" 2>/dev/null) || code="000"

    case "$code" in
        2[0-9][0-9]|3[0-9][0-9])
            add_result "$name" "доступен" "HTTP $code";;
        401|403)
            body=$(curl -sS --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIMEOUT" \
                -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
                -L "$url" 2>/dev/null | head -c 300)
            if echo "$body" | grep -qi "cloudflare\|challenge\|ray id\|checking your browser"; then
                add_result "$name" "капча/блок" "HTTP $code (Cloudflare)"
            else
                add_result "$name" "доступен" "HTTP $code (auth/forbidden)"
            fi;;
        429)
            add_result "$name" "капча/лимит" "HTTP 429";;
        000)
            add_result "$name" "недоступен" "Timeout/Connection failed";;
        *)
            add_result "$name" "недоступен" "HTTP $code";;
    esac
    return 0
}

get_public_ip() {
    log "Определение публичного IP..."
    curl -sS --max-time 5 https://api.ipify.org 2>/dev/null || \
    curl -sS --max-time 5 https://ifconfig.me 2>/dev/null || \
    echo "unknown"
}

check_speed_cloudflare() {
    log "Проверка скорости (Cloudflare)..."
    local size_mb=5
    local url="https://speed.cloudflare.com/__down?bytes=${size_mb}000000"
    local start end duration mbps
    start=$(date +%s.%N)
    curl -sS -o /dev/null --max-time "$MAX_TIMEOUT" "$url" 2>/dev/null || true
    end=$(date +%s.%N)
    duration=$(awk "BEGIN {print $end - $start}")
    if awk "BEGIN {exit !($duration > 0)}"; then
        mbps=$(awk "BEGIN {printf \"%.2f\", ($size_mb * 8) / $duration}")
        ok "Скорость: ~${mbps} Mbps"
        add_result "Speedtest (Cloudflare)" "доступен" "${mbps} Mbps"
    else
        warn "Не удалось измерить скорость"
        add_result "Speedtest (Cloudflare)" "недоступен" "Failed"
    fi
}

check_ai() {
    log "Проверка AI..."
    check_http "Grok (x.ai)" "https://api.x.ai/v1/models" || true
    check_http "Anthropic" "https://api.anthropic.com/v1/messages" || true
    check_http "Gemini" "https://generativelanguage.googleapis.com/v1beta/models" || true
    check_http "ChatGPT (OpenAI)" "https://api.openai.com/v1/models" || true
}

check_social() {
    log "Проверка соцсетей..."
    check_http "Instagram" "https://www.instagram.com/" || true
    check_http "Twitter/X" "https://x.com/" || true
    check_http "Reddit" "https://www.reddit.com/" || true
    check_http "Spotify" "https://www.spotify.com/" || true
}

check_dev() {
    log "Проверка Dev / Cloudflare / IPQuality..."
    check_http "GitHub" "https://github.com/" || true
    check_http "GitLab" "https://gitlab.com/" || true
    check_http "Cloudflare" "https://cloudflare.com/" || true
    check_http "MaxMind API" "https://geoip.maxmind.com/geoip/v2.1/city/me" || true
}

check_google() {
    log "Проверка Google..."
    check_http "Google Search" "https://www.google.com/" || true
    check_http "YouTube" "https://www.youtube.com/" || true
    check_http "Gmail" "https://mail.google.com/" || true
    check_http "Google Drive" "https://drive.google.com/" || true
}

print_table() {
    echo
    echo "═══════════════════════════════════════════════════════════════════"
    echo "                    IP QUALITY CHECK REPORT"
    echo "═══════════════════════════════════════════════════════════════════"
    printf "  IP: %s\n" "$PUBLIC_IP"
    printf "  Время: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    echo "──────────────────────────────────────────────────────────────────"
    printf "  %-30s  %-14s  %s\n" "СЕРВИС" "СТАТУС" "ДЕТАЛИ"
    echo "──────────────────────────────────────────────────────────────────"
    for row in "${RESULTS[@]}"; do
        IFS='|' read -r name status details <<< "$row"
        local c="$NC"
        case "$status" in
            "доступен") c="$GREEN";;
            "капча/"*) c="$YELLOW";;
            "недоступен") c="$RED";;
        esac
        printf "  %-30s  ${c}%-14s${NC}  %s\n" "$name" "$status" "$details"
    done
    echo "──────────────────────────────────────────────────────────────────"
    local total=${#RESULTS[@]} ok=0 warn=0 fail=0
    for row in "${RESULTS[@]}"; do
        IFS='|' read -r _ s _ <<< "$row"
        case "$s" in
            "доступен") ((ok++));;
            "капча/"*) ((warn++));;
            "недоступен") ((fail++));;
        esac
    done
    printf "  Итого: ${GREEN}%d доступно${NC}, ${YELLOW}%d капча/лимит${NC}, ${RED}%d недоступно${NC} (из %d)\n" "$ok" "$warn" "$fail" "$total"
    echo "═══════════════════════════════════════════════════════════════════"
}

main() {
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    IP QUALITY CHECKER v1.0                       ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    PUBLIC_IP=$(get_public_ip)
    log "Публичный IP: $PUBLIC_IP"
    check_speed_cloudflare
    check_ai
    check_social
    check_dev
    check_google
    print_table
    for row in "${RESULTS[@]}"; do
        IFS='|' read -r _ s _ <<< "$row"
        if [[ "$s" == "недоступен" || "$s" == "капча/"* ]]; then exit 1; fi
    done
    exit 0
}

for cmd in curl awk; do command -v "$cmd" >/dev/null 2>&1 || { err "Нужен $cmd"; exit 1; }; done
main "$@"
EOF
chmod +x check_ip.sh
./check_ip.sh
