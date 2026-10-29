#!/usr/bin/env bash
# Source: https://github.com/daniel3303/ClaudeCodeStatusLine
# Single line: Model | tokens | %used | %remain | think | 5h bar @reset | 7d bar @reset | extra

set -f  # disable globbing
VERSION="1.4.4"

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# ANSI colors — sourced from Noctalia's LIVE palette, so the status line
# follows the wallpaper-derived Material You colours like the rest of the
# desktop (gtk, ghostty, btop, starship, zellij…) instead of being pinned to
# whatever the palette looked like the day this was vendored.
#
# Source of truth is ~/.cache/noctalia/starship-palette.toml, written by
# Noctalia's builtin `starship` template and regenerated on every palette
# change. It carries Catppuccin-compatible named slots (text, subtext0,
# overlay0-2, surface0-2, base, plus blue/red/green/…), which map cleanly onto
# what this script needs.
#
# Deliberately NOT ~/.config/noctalia/colors.json — that is a stale v4
# artefact which Noctalia no longer writes.
#
# Everything degrades: if the file is missing (fresh $HOME, Noctalia not yet
# run, starship template disabled) each slot falls back to the neutral grey
# that was hardcoded here before, so the status line still renders.
noctalia_palette="${XDG_CACHE_HOME:-$HOME/.cache}/noctalia/starship-palette.toml"

# hex_to_ansi "#rrggbb" "fallback_r;g;b" -> SGR truecolour escape
hex_to_ansi() {
    local hex="${1#\#}" fallback="$2"
    if [ ${#hex} -ne 6 ]; then
        printf '\033[38;2;%sm' "$fallback"
        return
    fi
    printf '\033[38;2;%d;%d;%dm' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}" 2>/dev/null \
        || printf '\033[38;2;%sm' "$fallback"
}

# Read one named slot out of the palette file. Matches `name = "#rrggbb"`.
palette_slot() {
    [ -r "$noctalia_palette" ] || return 1
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\(#[0-9a-fA-F]\{6\}\)\".*/\1/p" \
        "$noctalia_palette" | head -1
}

# slot_or name fallback_rgb  -> escape from the palette, else the old grey
slot_or() {
    local hex
    hex=$(palette_slot "$1" 2>/dev/null)
    if [ -n "$hex" ]; then hex_to_ansi "$hex" "$2"; else printf '\033[38;2;%sm' "$2"; fi
}

# Role -> slot mapping. Fallbacks are the previous hardcoded mono values, so
# behaviour without Noctalia is identical to before this change.
# Slots are chosen for DISTINCTNESS, not for name. Noctalia's Material You
# palette collapses the Catppuccin slot names onto roughly eight real colours
# — green/lavender/mauve/pink are all one blue, and cyan/peach/teal/yellow are
# all one lighter blue. Mapping by name alone puts three of the four usage
# levels on the same two colours and the heat gradient stops meaning anything.
#
# So the gradient gets first claim on four visibly separate steps:
#   ok       subtext0  muted grey   — nothing to see
#   warning  teal      light blue
#   elevated sapphire  purple
#   critical red       salmon
# Other roles reuse those colours where a collision is harmless because the
# two never appear in the same position.
blue=$(slot_or   sapphire '204;204;204')  # model name, token ratio label
orange=$(slot_or sapphire '204;204;204')  # usage elevated (70–89%), med effort, CLI version
green=$(slot_or  subtext0 '93;93;93')     # usage ok (<50%), git branch/adds, low effort
cyan=$(slot_or   mauve    '170;170;170')  # directory name
red=$(slot_or    red      '221;221;221')  # usage critical (≥90%), git removals, max effort
yellow=$(slot_or teal     '170;170;170')  # usage warning (50–69%), high effort
purple=$(slot_or mauve    '204;204;204')  # xhigh effort
white=$(slot_or  text     '221;221;221')  # segment labels (5h, 7d, extra)
dim='\033[2m'
reset='\033[0m'

# Nerd Font glyphs (JetBrainsMono Nerd Font — set system-wide in
# configuration.nix and as ghostty's font-family, so these resolve in the
# terminal Claude Code runs in). All are Font Awesome / Devicons codepoints,
# present in every Nerd Font build rather than the patchier Material set.
#
# Set NOCTALIA_STATUSLINE_ICONS=0 to turn them off without editing the file —
# useful over SSH to a box with no patched font, where they'd render as
# tofu boxes.
if [ "${NOCTALIA_STATUSLINE_ICONS:-1}" = "0" ]; then
    # Icons off: blank the decorative ones, but keep a TEXT label for effort,
    # which otherwise loses its only marker and renders as a bare "med".
    i_model=""; i_dir=""; i_git=""; i_tok=""; i_clock=""; i_ver=""
    i_eff="effort: "
else
    i_model=$'\uf2db '   # microchip — model name
    i_dir=$'\uf07b '     # folder    — working directory
    i_git=$'\ue725 '     # branch    — git branch
    i_tok=$'\uf1c0 '     # database  — context window usage
    i_eff=$'\uf0e7 '     # bolt      — reasoning effort
    i_clock=$'\uf017 '   # clock     — 5h / 7d usage windows
    i_ver=$'\uf02b '     # tag       — CLI version
fi

# Format token counts (e.g., 50k / 200k)
format_tokens() {
    local num=$1
    if [ "$num" -ge 1000000 ]; then
        awk "BEGIN {v=sprintf(\"%.1f\",$num/1000000)+0; if(v==int(v)) printf \"%dm\",v; else printf \"%.1fm\",v}"
    elif [ "$num" -ge 1000 ]; then
        awk "BEGIN {printf \"%.0fk\", $num / 1000}"
    else
        printf "%d" "$num"
    fi
}

# Format number with commas (e.g., 134,938)
format_commas() {
    printf "%'d" "$1"
}

# Return color escape based on usage percentage
# Usage: usage_color <pct>
usage_color() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then echo "$red"
    elif [ "$pct" -ge 70 ]; then echo "$orange"
    elif [ "$pct" -ge 50 ]; then echo "$yellow"
    else echo "$green"
    fi
}

# Resolve config directory: CLAUDE_CONFIG_DIR (set by alias) or default ~/.claude
claude_config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Return 0 (true) if $1 > $2 using semantic versioning
version_gt() {
    local a="${1#v}" b="${2#v}"
    local IFS='.'
    read -r a1 a2 a3 <<< "$a"
    read -r b1 b2 b3 <<< "$b"
    a1=${a1:-0}; a2=${a2:-0}; a3=${a3:-0}
    b1=${b1:-0}; b2=${b2:-0}; b3=${b3:-0}
    [ "$a1" -gt "$b1" ] 2>/dev/null && return 0
    [ "$a1" -lt "$b1" ] 2>/dev/null && return 1
    [ "$a2" -gt "$b2" ] 2>/dev/null && return 0
    [ "$a2" -lt "$b2" ] 2>/dev/null && return 1
    [ "$a3" -gt "$b3" ] 2>/dev/null && return 0
    return 1
}
# ===== Extract data from JSON =====
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')
model_name=$(echo "$model_name" | sed 's/ *(\([0-9.]*[kKmM]*\) context)/ \1/')  # "(1M context)" → "1M"

# Context window
size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$size" -eq 0 ] 2>/dev/null && size=200000

# Token usage
input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
current=$(( input_tokens + cache_create + cache_read ))

used_tokens=$(format_tokens $current)
total_tokens=$(format_tokens $size)

if [ "$size" -gt 0 ]; then
    pct_used=$(( current * 100 / size ))
else
    pct_used=0
fi
pct_remain=$(( 100 - pct_used ))

used_comma=$(format_commas $current)
remain_comma=$(format_commas $(( size - current )))

settings_path="$claude_config_dir/settings.json"
effort_level=""
stdin_effort=$(echo "$input" | jq -r '.effort.level // empty' 2>/dev/null)
if [ -n "$stdin_effort" ]; then
    effort_level="$stdin_effort"
elif [ -n "$CLAUDE_CODE_EFFORT_LEVEL" ]; then
    effort_level="$CLAUDE_CODE_EFFORT_LEVEL"
elif [ -f "$settings_path" ]; then
    effort_val=$(jq -r '.effortLevel // empty' "$settings_path" 2>/dev/null)
    [ -n "$effort_val" ] && effort_level="$effort_val"
fi
[ -z "$effort_level" ] && effort_level="medium"

# ===== Claude CLI version (cached, 1h TTL) =====
cli_version_cache="/tmp/claude/statusline-cli-version"
cli_version=""
cli_version_max_age=3600

if [ -f "$cli_version_cache" ]; then
    cv_mtime=$(stat -c %Y "$cli_version_cache" 2>/dev/null || stat -f %m "$cli_version_cache" 2>/dev/null)
    cv_now=$(date +%s)
    cv_age=$(( cv_now - cv_mtime ))
    if [ "$cv_age" -lt "$cli_version_max_age" ]; then
        cli_version=$(cat "$cli_version_cache" 2>/dev/null)
    fi
fi

if [ -z "$cli_version" ]; then
    cli_version=$(claude --version 2>/dev/null | awk '{print $1}')
    if [ -n "$cli_version" ]; then
        mkdir -p /tmp/claude 2>/dev/null
        echo "$cli_version" > "$cli_version_cache"
    fi
fi

# ===== Build single-line output =====
out=""
out+="${blue}${i_model}${model_name}${reset}"

# Current working directory
cwd=$(echo "$input" | jq -r '.cwd // empty')
if [ -n "$cwd" ]; then
    display_dir="${cwd##*/}"
    git_branch=$(git -C "${cwd}" rev-parse --abbrev-ref HEAD 2>/dev/null)
    out+=" ${dim}|${reset} "
    out+="${cyan}${i_dir}${display_dir}${reset}"
    if [ -n "$git_branch" ]; then
        out+="${dim}@${reset}${green}${i_git}${git_branch}${reset}"
        git_stat=$(git -C "${cwd}" diff --numstat 2>/dev/null | awk '{a+=$1; d+=$2} END {if (a+d>0) printf "+%d -%d", a, d}')
        [ -n "$git_stat" ] && out+=" ${dim}(${reset}${green}${git_stat%% *}${reset} ${red}${git_stat##* }${reset}${dim})${reset}"
    fi
fi

out+=" ${dim}|${reset} "
token_color=$(usage_color "$pct_used")
out+="${blue}${i_tok}${used_tokens}/${total_tokens}${reset} ${dim}(${reset}${token_color}${pct_used}%${reset}${dim})${reset}"
out+=" ${dim}|${reset} "
# effort scale — a brightness ramp climbing into the accent colours:
#   low → med → high      overlay0 → overlay1 → text   (dim to bright)
#   xhigh → max           $purple → $red               (set with the others above)
# Same live-palette sourcing as the block near the top; fallbacks are the
# previous hardcoded greys so behaviour without Noctalia is unchanged.
faint_c=$(slot_or overlay0 '93;93;93')    # low
dim_c=$(slot_or   overlay1 '130;130;130') # medium
fg_c=$(slot_or    subtext1 '170;170;170') # high / unknown
out+="${dim}${i_eff}${reset}"
case "$effort_level" in
    low)    out+="${faint_c}${effort_level}${reset}" ;;
    medium) out+="${dim_c}med${reset}" ;;
    high)   out+="${fg_c}${effort_level}${reset}" ;;
    xhigh)  out+="${purple}${effort_level}${reset}" ;;
    max)    out+="${red}${effort_level}${reset}" ;;
    *)      out+="${fg_c}${effort_level}${reset}" ;;
esac

# ===== Cross-platform OAuth token resolution (from statusline.sh) =====
# Tries credential sources in order: env var → macOS Keychain → Linux creds file → GNOME Keyring
get_oauth_token() {
    local token=""

    # 1. Explicit env var override
    if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        echo "$CLAUDE_CODE_OAUTH_TOKEN"
        return 0
    fi

    # 2. macOS Keychain (Claude Code appends a SHA256 hash of CLAUDE_CONFIG_DIR to the service name)
    if command -v security >/dev/null 2>&1; then
        local keychain_svc="Claude Code-credentials"
        if [ -n "$CLAUDE_CONFIG_DIR" ]; then
            local dir_hash
            dir_hash=$(echo -n "$CLAUDE_CONFIG_DIR" | shasum -a 256 | cut -c1-8)
            keychain_svc="Claude Code-credentials-${dir_hash}"
        fi
        local blob
        blob=$(security find-generic-password -s "$keychain_svc" -w 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    # 3. Linux credentials file
    local creds_file="${claude_config_dir}/.credentials.json"
    if [ -f "$creds_file" ]; then
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
        if [ -n "$token" ] && [ "$token" != "null" ]; then
            echo "$token"
            return 0
        fi
    fi

    # 4. GNOME Keyring via secret-tool
    if command -v secret-tool >/dev/null 2>&1; then
        local blob
        blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    echo ""
}

# ===== LINE 2 & 3: Usage limits with progress bars =====
# First, try to use rate_limits data provided directly by Claude Code in the JSON input.
# This is the most reliable source — no OAuth token or API call required.
builtin_five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
builtin_five_hour_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
builtin_seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
builtin_seven_day_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

use_builtin=false
if [ -n "$builtin_five_hour_pct" ] || [ -n "$builtin_seven_day_pct" ]; then
    use_builtin=true
fi

# Cache setup — shared across all Claude Code instances to avoid rate limits
claude_config_dir_hash=$(echo -n "$claude_config_dir" | shasum -a 256 2>/dev/null || echo -n "$claude_config_dir" | sha256sum 2>/dev/null)
claude_config_dir_hash=$(echo "$claude_config_dir_hash" | cut -c1-8)
cache_file="/tmp/claude/statusline-usage-cache-${claude_config_dir_hash}.json"
cache_max_age=60  # seconds between API calls
mkdir -p /tmp/claude

needs_refresh=true
usage_data=""

# Always load cache — used as primary source for API path, and as fallback when builtin reports zero
if [ -f "$cache_file" ] && [ -s "$cache_file" ]; then
    cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
    now=$(date +%s)
    cache_age=$(( now - cache_mtime ))
    if [ "$cache_age" -lt "$cache_max_age" ]; then
        needs_refresh=false
    fi
    usage_data=$(cat "$cache_file" 2>/dev/null)
fi

# When builtin values are all zero AND reset timestamps are missing, it likely indicates
# an API failure on Claude's side — fall through to cached data instead of displaying
# misleading 0%. Genuine zero responses (after a billing reset) still include valid
# resets_at timestamps, so we trust those.
effective_builtin=false
if $use_builtin; then
    # Trust builtin if any percentage is non-zero
    if { [ -n "$builtin_five_hour_pct" ] && [ "$(printf '%.0f' "$builtin_five_hour_pct" 2>/dev/null)" != "0" ]; } || \
       { [ -n "$builtin_seven_day_pct" ] && [ "$(printf '%.0f' "$builtin_seven_day_pct" 2>/dev/null)" != "0" ]; }; then
        effective_builtin=true
    fi
    # Also trust if reset timestamps are present — genuine zero responses include valid reset times
    if ! $effective_builtin; then
        if { [ -n "$builtin_five_hour_reset" ] && [ "$builtin_five_hour_reset" != "null" ] && [ "$builtin_five_hour_reset" != "0" ]; } || \
           { [ -n "$builtin_seven_day_reset" ] && [ "$builtin_seven_day_reset" != "null" ] && [ "$builtin_seven_day_reset" != "0" ]; }; then
            effective_builtin=true
        fi
    fi
fi

# Refresh API cache when stale — runs regardless of builtin rate_limits because
# extra_usage is only exposed through the OAuth usage endpoint (not stdin JSON).
# Throttled to cache_max_age and stampede-locked via touch for shared panes.
if $needs_refresh; then
    touch "$cache_file"  # stampede lock: prevent parallel panes from fetching simultaneously
    token=$(get_oauth_token)
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        response=$(curl -s --max-time 10 \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            -H "User-Agent: claude-code/2.1.34" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        # Only cache valid usage responses (not error/rate-limit JSON)
        if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
            usage_data="$response"
            echo "$response" > "$cache_file"
        fi
    fi
    # Remove the stampede sentinel if the fetch failed to produce valid JSON —
    # otherwise an empty cache file would suppress retries for a full cache_max_age window.
    [ -f "$cache_file" ] && [ ! -s "$cache_file" ] && rm -f "$cache_file"
fi

# Cross-platform ISO to epoch conversion
# Converts ISO 8601 timestamp (e.g. "2025-06-15T12:30:00Z" or "2025-06-15T12:30:00.123+00:00") to epoch seconds.
# Properly handles UTC timestamps and converts to local time.
iso_to_epoch() {
    local iso_str="$1"

    # Try GNU date first (Linux) — handles ISO 8601 format automatically
    local epoch
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    # BSD date (macOS) - handle various ISO 8601 formats
    local stripped="${iso_str%%.*}"          # Remove fractional seconds (.123456)
    stripped="${stripped%%Z}"                 # Remove trailing Z
    stripped="${stripped%%+*}"               # Remove timezone offset (+00:00)
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"  # Remove negative timezone offset

    # Check if timestamp is UTC (has Z or +00:00 or -00:00)
    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]] || [[ "$iso_str" == *"-00:00"* ]]; then
        # For UTC timestamps, parse with timezone set to UTC
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    fi

    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    return 1
}

# Format ISO reset time to compact local time
# Usage: format_reset_time <iso_string> <style: time|datetime|date>
format_reset_time() {
    local iso_str="$1"
    local style="$2"
    { [ -z "$iso_str" ] || [ "$iso_str" = "null" ]; } && return

    # Parse ISO datetime and convert to local time (cross-platform)
    local epoch
    epoch=$(iso_to_epoch "$iso_str")
    [ -z "$epoch" ] && return

    # Format based on style
    # Try GNU date first (Linux), then BSD date (macOS)
    # Previous implementation piped BSD date through sed/tr, which always returned
    # exit code 0 from the last pipe stage, preventing the GNU date fallback from
    # ever executing on Linux.
    local formatted=""
    case "$style" in
        time)
            formatted=$(date -d "@$epoch" +"%H:%M" 2>/dev/null) || \
            formatted=$(date -j -r "$epoch" +"%H:%M" 2>/dev/null)
            ;;
        datetime)
            formatted=$(date -d "@$epoch" +"%a %b %-d, %H:%M" 2>/dev/null) || \
            formatted=$(date -j -r "$epoch" +"%a %b %-d, %H:%M" 2>/dev/null)
            ;;
        *)
            formatted=$(date -d "@$epoch" +"%b %-d" 2>/dev/null) || \
            formatted=$(date -j -r "$epoch" +"%b %-d" 2>/dev/null)
            ;;
    esac
    [ -n "$formatted" ] && echo "$formatted"
}

sep=" ${dim}|${reset} "

# Render extra_usage segment from API usage data (not available via stdin rate_limits).
# Appends to the global $out. No-op when data is missing or is_enabled is false.
render_extra_usage() {
    local data="$1"
    [ -z "$data" ] && return
    local enabled
    enabled=$(echo "$data" | jq -r '.extra_usage.is_enabled // false' 2>/dev/null)
    [ "$enabled" != "true" ] && return

    local pct used limit
    pct=$(echo "$data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
    used=$(echo "$data" | jq -r '.extra_usage.used_credits // 0' | LC_NUMERIC=C awk '{printf "%.2f", $1/100}')
    limit=$(echo "$data" | jq -r '.extra_usage.monthly_limit // 0' | LC_NUMERIC=C awk '{printf "%.2f", $1/100}')

    if [ -n "$used" ] && [ -n "$limit" ] && [[ "$used" != *'$'* ]] && [[ "$limit" != *'$'* ]]; then
        local color
        color=$(usage_color "$pct")
        out+="${sep}${white}extra${reset} ${color}\$${used}/\$${limit}${reset}"
    else
        out+="${sep}${white}extra${reset} ${green}enabled${reset}"
    fi
}

if $effective_builtin; then
    # ---- Use rate_limits data provided directly by Claude Code in JSON input ----
    # resets_at values are Unix epoch integers in this source
    if [ -n "$builtin_five_hour_pct" ]; then
        five_hour_pct=$(printf "%.0f" "$builtin_five_hour_pct")
        five_hour_color=$(usage_color "$five_hour_pct")
        out+="${sep}${white}${i_clock}5h${reset} ${five_hour_color}${five_hour_pct}%${reset}"
        if [ -n "$builtin_five_hour_reset" ] && [ "$builtin_five_hour_reset" != "null" ]; then
            five_hour_reset=$(date -j -r "$builtin_five_hour_reset" +"%H:%M" 2>/dev/null || date -d "@$builtin_five_hour_reset" +"%H:%M" 2>/dev/null)
            [ -n "$five_hour_reset" ] && out+=" ${dim}@${five_hour_reset}${reset}"
        fi
    fi

    if [ -n "$builtin_seven_day_pct" ]; then
        seven_day_pct=$(printf "%.0f" "$builtin_seven_day_pct")
        seven_day_color=$(usage_color "$seven_day_pct")
        out+="${sep}${white}${i_clock}7d${reset} ${seven_day_color}${seven_day_pct}%${reset}"
        if [ -n "$builtin_seven_day_reset" ] && [ "$builtin_seven_day_reset" != "null" ]; then
            seven_day_reset=$(date -j -r "$builtin_seven_day_reset" +"%a %b %-d, %H:%M" 2>/dev/null || date -d "@$builtin_seven_day_reset" +"%a %b %-d, %H:%M" 2>/dev/null)
            [ -n "$seven_day_reset" ] && out+=" ${dim}@${seven_day_reset}${reset}"
        fi
    fi

    # Render extra_usage from API cache (stdin rate_limits doesn't expose it)
    render_extra_usage "$usage_data"

    # Cache builtin values so they're available as fallback when API is unavailable.
    # Convert epoch resets_at to ISO 8601 for compatibility with the API-format cache parser.
    # Preserve extra_usage from prior API response so we don't clobber it.
    _fh_reset_json="null"
    if [ -n "$builtin_five_hour_reset" ] && [ "$builtin_five_hour_reset" != "null" ] && [ "$builtin_five_hour_reset" != "0" ]; then
        _fh_iso=$(date -u -r "$builtin_five_hour_reset" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                  date -u -d "@$builtin_five_hour_reset" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
        [ -n "$_fh_iso" ] && _fh_reset_json="\"$_fh_iso\""
    fi
    _sd_reset_json="null"
    if [ -n "$builtin_seven_day_reset" ] && [ "$builtin_seven_day_reset" != "null" ] && [ "$builtin_seven_day_reset" != "0" ]; then
        _sd_iso=$(date -u -r "$builtin_seven_day_reset" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                  date -u -d "@$builtin_seven_day_reset" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
        [ -n "$_sd_iso" ] && _sd_reset_json="\"$_sd_iso\""
    fi
    _extra_json=$(echo "$usage_data" | jq -c '.extra_usage // null' 2>/dev/null)
    [ -z "$_extra_json" ] && _extra_json="null"
    printf '{"five_hour":{"utilization":%s,"resets_at":%s},"seven_day":{"utilization":%s,"resets_at":%s},"extra_usage":%s}' \
        "${builtin_five_hour_pct:-0}" "$_fh_reset_json" \
        "${builtin_seven_day_pct:-0}" "$_sd_reset_json" \
        "$_extra_json" > "$cache_file" 2>/dev/null
elif [ -n "$usage_data" ] && echo "$usage_data" | jq -e '.five_hour' >/dev/null 2>&1; then
    # ---- Fall back: API-fetched usage data ----
    # ---- 5-hour (current) ----
    five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
    five_hour_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
    five_hour_reset=$(format_reset_time "$five_hour_reset_iso" "time")
    five_hour_color=$(usage_color "$five_hour_pct")

    out+="${sep}${white}${i_clock}5h${reset} ${five_hour_color}${five_hour_pct}%${reset}"
    [ -n "$five_hour_reset" ] && out+=" ${dim}@${five_hour_reset}${reset}"

    # ---- 7-day (weekly) ----
    seven_day_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
    seven_day_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
    seven_day_reset=$(format_reset_time "$seven_day_reset_iso" "datetime")
    seven_day_color=$(usage_color "$seven_day_pct")

    out+="${sep}${white}${i_clock}7d${reset} ${seven_day_color}${seven_day_pct}%${reset}"
    [ -n "$seven_day_reset" ] && out+=" ${dim}@${seven_day_reset}${reset}"

    render_extra_usage "$usage_data"
else
    # No valid usage data — show placeholders
    out+="${sep}${white}${i_clock}5h${reset} ${dim}-${reset}"
    out+="${sep}${white}${i_clock}7d${reset} ${dim}-${reset}"
fi

# ===== Update check (cached, 24h TTL) =====
# Set STATUSLINE_CHECK_UPDATES=false to disable the update check (no network calls).
update_line=""
if [ "${STATUSLINE_CHECK_UPDATES:-true}" != "false" ]; then
    version_cache_file="/tmp/claude/statusline-version-cache.json"
    version_cache_max_age=86400  # 24 hours

    version_needs_refresh=true
    version_data=""

    if [ -f "$version_cache_file" ]; then
        vc_mtime=$(stat -c %Y "$version_cache_file" 2>/dev/null || stat -f %m "$version_cache_file" 2>/dev/null)
        vc_now=$(date +%s)
        vc_age=$(( vc_now - vc_mtime ))
        if [ "$vc_age" -lt "$version_cache_max_age" ]; then
            version_needs_refresh=false
        fi
        version_data=$(cat "$version_cache_file" 2>/dev/null)
    fi

    if $version_needs_refresh; then
        touch "$version_cache_file" 2>/dev/null
        vc_response=$(curl -s --max-time 5 \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/daniel3303/ClaudeCodeStatusLine/releases/latest" 2>/dev/null)
        if [ -n "$vc_response" ] && echo "$vc_response" | jq -e '.tag_name' >/dev/null 2>&1; then
            version_data="$vc_response"
            echo "$vc_response" > "$version_cache_file"
        elif [ ! -s "$version_cache_file" ]; then
            rm -f "$version_cache_file" 2>/dev/null
        fi
    fi

    if [ -n "$version_data" ]; then
        latest_tag=$(echo "$version_data" | jq -r '.tag_name // empty')
        if [ -n "$latest_tag" ] && version_gt "$latest_tag" "$VERSION"; then
            update_line="\n${dim}Update available: ${latest_tag} → Tell Claude: \"Find my installed status bar and update it\"${reset}"
        fi
    fi
fi

# Append CLI version as last segment
if [ -n "$cli_version" ]; then
    out+=" ${dim}|${reset} ${orange}${i_ver}v${cli_version}${reset}"
fi

# Output
printf "%b" "$out$update_line"

exit 0
