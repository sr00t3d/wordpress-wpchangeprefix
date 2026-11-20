#!/usr/bin/env bash
# +============================================================================+
# | wp-change-prefix.sh                                                        |
# | WordPress Database Prefix Changer v2.0.0                                   |
# | Safely renames WordPress MySQL/MariaDB tables, updates internal options &  |
# | usermeta prefix references, creates chmod 600 SQL & wp-config.php backups, |
# | and patches $table_prefix atomically with table/JSON/CSV reporting.        |
# |                                                                            |
# | Author:  Percio Castelo                                                    |
# | Contact: percio@evolya.com.br | contato@perciocastelo.com.br               |
# | Web:     https://perciocastelo.com.br                                      |
# | Repo:    https://github.com/sr00t3d/wpchangeprefix                         |
# |                                                                            |
# | Copyright 2024-2026 Percio Castelo                                         |
# | SPDX-License-Identifier: Apache-2.0                                        |
# +============================================================================+

set -uo pipefail

readonly VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"

# ---- Defaults ---------------------------------------------------------------
CONFIG_FILE="wp-config.php"
NEW_PREFIX_RAW=""
RANDOM_PREFIX=0
BACKUP_DIR=""
SKIP_BACKUP=0
AUTO_YES=0
DRY_RUN=0
OUTPUT_FORMAT="table"
QUIET=0
NO_COLOR=0

MYSQL_CNF=""
cleanup() {
    if [[ -n "${MYSQL_CNF:-}" && -f "$MYSQL_CNF" ]]; then
        rm -f "$MYSQL_CNF"
    fi
}
trap cleanup EXIT INT TERM

# ---- Color helpers ----------------------------------------------------------
init_colors() {
    if [[ "$NO_COLOR" -eq 1 || ! -t 1 ]]; then
        C_RESET="" C_BOLD="" C_GREEN="" C_YELLOW="" C_RED="" C_CYAN=""
    else
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_GREEN=$'\033[32m'
        C_YELLOW=$'\033[33m'
        C_RED=$'\033[31m'
        C_CYAN=$'\033[36m'
    fi
}

# ---- Help & Version ---------------------------------------------------------
show_version() {
    echo "WordPress Database Prefix Changer v${VERSION}"
}

show_help() {
    cat <<EOF
WordPress Database Prefix Changer v${VERSION}
Safely renames WordPress database tables and updates wp-config.php.

Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
  -c, --config PATH       Path to wp-config.php (default: ./wp-config.php)
  -p, --new-prefix STR    New table prefix (alphanumeric/underscore, e.g. wp_7f3a_)
  --random                Auto-generate a random prefix (format: wp_<6hex>_)
  -b, --backup-dir DIR    Directory to save SQL dump and wp-config.php backup
  -s, --skip-backup       Skip creating SQL dump and wp-config.php backup
  -y, --yes               Skip interactive confirmation prompt
  --dry-run               Preview tables and changes without modifying DB or files
  -o, --output FORMAT     Output format: table (default), json, csv
  -q, --quiet             Suppress standard output (errors still go to stderr)
  --no-color              Disable ANSI colors
  -V, --version           Show version and exit
  -h, --help              Show this help and exit

Examples:
  ${SCRIPT_NAME} -c /var/www/html/wp-config.php --random --dry-run
  ${SCRIPT_NAME} -c /var/www/html/wp-config.php -p wp_sec9_ --yes
  ${SCRIPT_NAME} -c /var/www/html/wp-config.php --random --yes -b /root/wp-backups -o json
  ${SCRIPT_NAME} -c /var/www/html/wp-config.php -p wp_prod_ --yes -o csv
EOF
}

# ---- Argument Parser --------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            [[ $# -lt 2 ]] && { echo "ERROR: $1 requires a file path." >&2; exit 1; }
            CONFIG_FILE="$2"; shift 2 ;;
        -p|--new-prefix)
            [[ $# -lt 2 ]] && { echo "ERROR: $1 requires a prefix value." >&2; exit 1; }
            NEW_PREFIX_RAW="$2"; shift 2 ;;
        --random)
            RANDOM_PREFIX=1; shift ;;
        -b|--backup-dir)
            [[ $# -lt 2 ]] && { echo "ERROR: $1 requires a directory path." >&2; exit 1; }
            BACKUP_DIR="$2"; shift 2 ;;
        -s|--skip-backup|--skip)
            SKIP_BACKUP=1; shift ;;
        -y|--yes)
            AUTO_YES=1; shift ;;
        --dry-run)
            DRY_RUN=1; AUTO_YES=1; shift ;;
        -o|--output)
            [[ $# -lt 2 ]] && { echo "ERROR: $1 requires table, json, or csv." >&2; exit 1; }
            OUTPUT_FORMAT="$2"; shift 2 ;;
        -q|--quiet)
            QUIET=1; shift ;;
        --no-color)
            NO_COLOR=1; shift ;;
        -n|--noversion)
            shift ;; # backward-compatible no-op
        -V|--version)
            show_version; exit 0 ;;
        -h|--help)
            show_help; exit 0 ;;
        *)
            echo "ERROR: Unknown option: $1 (run with -h for usage)" >&2
            exit 1 ;;
    esac
done

init_colors

# ---- Validations ------------------------------------------------------------
case "$OUTPUT_FORMAT" in
    table|json|csv) ;;
    *)
        echo "${C_RED}ERROR: Invalid output format '${OUTPUT_FORMAT}'. Expected table, json, or csv.${C_RESET}" >&2
        exit 1 ;;
esac

for bin in mysql mysqldump; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "${C_RED}ERROR: Required MySQL/MariaDB client binary not found: ${bin}${C_RESET}" >&2
        exit 1
    fi
done

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "${C_RED}ERROR: wp-config.php not found: ${CONFIG_FILE}${C_RESET}" >&2
    exit 1
fi

CONFIG_ABS="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"
CONFIG_DIR="$(dirname "$CONFIG_ABS")"
TIMESTAMP_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TIMESTAMP_FILE="$(date -u +%Y%m%d_%H%M%S)"

# ---- Parse wp-config.php ----------------------------------------------------
extract_wp_define() {
    local key="$1"
    grep -E "define[[:space:]]*\([[:space:]]*['\"]${key}['\"][[:space:]]*," "$CONFIG_ABS" \
        | head -n 1 \
        | sed -E "s/.*define[[:space:]]*\([[:space:]]*['\"]${key}['\"][[:space:]]*,[[:space:]]*['\"]([^'\"]*)['\"].*/\1/"
}

DB_NAME="$(extract_wp_define "DB_NAME")"
DB_USER="$(extract_wp_define "DB_USER")"
DB_PASS="$(extract_wp_define "DB_PASSWORD")"
DB_HOST_RAW="$(extract_wp_define "DB_HOST")"
[[ -z "$DB_HOST_RAW" ]] && DB_HOST_RAW="localhost"

if [[ -z "$DB_NAME" || -z "$DB_USER" ]]; then
    echo "${C_RED}ERROR: Could not extract DB_NAME / DB_USER from ${CONFIG_ABS}.${C_RESET}" >&2
    exit 1
fi

# Parse host[:port|/socket]
DB_HOST="$DB_HOST_RAW"
DB_PORT=""
DB_SOCKET=""
if [[ "$DB_HOST_RAW" == *:* ]]; then
    DB_HOST="${DB_HOST_RAW%%:*}"
    local_rest="${DB_HOST_RAW#*:}"
    if [[ "$local_rest" == /* ]]; then
        DB_SOCKET="$local_rest"
    elif [[ "$local_rest" =~ ^[0-9]+$ ]]; then
        DB_PORT="$local_rest"
    fi
fi

# Build temporary chmod 600 MySQL credentials file (never leaks password to ps aux)
# Double-quote values so '#' or ';' inside passwords are not treated as comments.
cnf_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
MYSQL_CNF="$(mktemp /tmp/wp_prefix_my.XXXXXX.cnf)"
chmod 600 "$MYSQL_CNF"
{
    echo "[client]"
    printf 'user="%s"\n' "$(cnf_escape "$DB_USER")"
    printf 'password="%s"\n' "$(cnf_escape "$DB_PASS")"
    [[ -n "$DB_HOST" ]] && printf 'host="%s"\n' "$(cnf_escape "$DB_HOST")"
    [[ -n "$DB_PORT" ]] && printf 'port=%s\n' "$DB_PORT"
    [[ -n "$DB_SOCKET" ]] && printf 'socket="%s"\n' "$(cnf_escape "$DB_SOCKET")"
} > "$MYSQL_CNF"

# ---- Detect Current Prefix --------------------------------------------------
DETECTED_OPTIONS="$(mysql --defaults-extra-file="$MYSQL_CNF" -N -s "$DB_NAME" -e "SHOW TABLES LIKE '%options';" 2>/dev/null | head -n 1 || true)"
if [[ -z "$DETECTED_OPTIONS" ]]; then
    echo "${C_RED}ERROR: Failed to connect to MySQL database '${DB_NAME}' or no '*options' table found.${C_RESET}" >&2
    exit 2
fi
CURRENT_PREFIX="${DETECTED_OPTIONS%options}"

# ---- Determine & Validate New Prefix ----------------------------------------
if [[ "$RANDOM_PREFIX" -eq 1 ]]; then
    RAND_HEX="$(od -An -tx1 -N3 /dev/urandom | tr -d ' \n')"
    NEW_PREFIX_RAW="wp_${RAND_HEX}_"
elif [[ -z "$NEW_PREFIX_RAW" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Enter new prefix (e.g. wp_sec9_): " NEW_PREFIX_RAW
    else
        echo "${C_RED}ERROR: --new-prefix or --random is required in non-interactive mode.${C_RESET}" >&2
        exit 1
    fi
fi

NEW_PREFIX="${NEW_PREFIX_RAW%_}_"

if ! [[ "$NEW_PREFIX" =~ ^[a-zA-Z][a-zA-Z0-9_]{1,19}_$ ]]; then
    echo "${C_RED}ERROR: Invalid prefix '${NEW_PREFIX}'. Must start with a letter and contain only [a-zA-Z0-9_] (max 20 chars).${C_RESET}" >&2
    exit 1
fi

if [[ "$NEW_PREFIX" == "$CURRENT_PREFIX" ]]; then
    echo "${C_RED}ERROR: New prefix '${NEW_PREFIX}' is identical to current prefix '${CURRENT_PREFIX}'.${C_RESET}" >&2
    exit 1
fi

# ---- Discover Tables --------------------------------------------------------
mapfile -t TABLES < <(
    mysql --defaults-extra-file="$MYSQL_CNF" -N -B "$DB_NAME" \
        -e "SHOW TABLES LIKE '${CURRENT_PREFIX}%';" 2>/dev/null
)

if [[ "${#TABLES[@]}" -eq 0 ]]; then
    echo "${C_RED}ERROR: No tables found matching prefix '${CURRENT_PREFIX}'.${C_RESET}" >&2
    exit 2
fi

# ---- Confirmation (Interactive Only) ----------------------------------------
if [[ "$AUTO_YES" -eq 0 && -t 0 ]]; then
    echo "Database: ${DB_NAME} | Tables: ${#TABLES[@]} | Prefix: '${CURRENT_PREFIX}' -> '${NEW_PREFIX}'"
    read -r -p "Proceed with rename? (y/N): " CONFIRM
    if [[ "${CONFIRM,,}" != "y" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# ---- Execute or Simulate ----------------------------------------------------
DUMP_PATH=""
CONFIG_BAK_PATH=""
CONFIG_UPDATED="false"
OPTIONS_UPDATED=0
USERMETA_UPDATED=0
OVERALL_STATUS="SUCCESS"

declare -a OLD_T=()
declare -a NEW_T=()
declare -a T_STATUS=()

if [[ "$DRY_RUN" -eq 1 ]]; then
    OVERALL_STATUS="DRY_RUN"
    for tbl in "${TABLES[@]}"; do
        suffix="${tbl#"$CURRENT_PREFIX"}"
        OLD_T+=("$tbl")
        NEW_T+=("${NEW_PREFIX}${suffix}")
        T_STATUS+=("WOULD_RENAME")
    done
else
    # 1. Backups
    if [[ "$SKIP_BACKUP" -eq 0 ]]; then
        TARGET_BKP_DIR="${BACKUP_DIR:-$CONFIG_DIR}"
        mkdir -p "$TARGET_BKP_DIR"
        DUMP_PATH="${TARGET_BKP_DIR}/${DB_NAME}_${CURRENT_PREFIX}backup_${TIMESTAMP_FILE}.sql"
        CONFIG_BAK_PATH="${TARGET_BKP_DIR}/wp-config.php.bak.${TIMESTAMP_FILE}"

        if ! mysqldump --defaults-extra-file="$MYSQL_CNF" --single-transaction --quick "$DB_NAME" > "$DUMP_PATH" 2>/dev/null; then
            echo "${C_RED}ERROR: mysqldump failed. Aborting before any changes.${C_RESET}" >&2
            rm -f "$DUMP_PATH"
            exit 3
        fi
        chmod 600 "$DUMP_PATH"

        cp -p "$CONFIG_ABS" "$CONFIG_BAK_PATH"
        chmod 600 "$CONFIG_BAK_PATH"
    fi

    # 2. Rename Tables
    for tbl in "${TABLES[@]}"; do
        suffix="${tbl#"$CURRENT_PREFIX"}"
        new_tbl="${NEW_PREFIX}${suffix}"
        OLD_T+=("$tbl")
        NEW_T+=("$new_tbl")
        if mysql --defaults-extra-file="$MYSQL_CNF" "$DB_NAME" \
            -e "RENAME TABLE \`${tbl}\` TO \`${new_tbl}\`;" 2>/dev/null; then
            T_STATUS+=("RENAMED")
        else
            T_STATUS+=("FAILED")
            OVERALL_STATUS="PARTIAL"
        fi
    done

    # 3. Patch internal WordPress prefix references (options + usermeta)
    OPTIONS_UPDATED="$(mysql --defaults-extra-file="$MYSQL_CNF" -N -s "$DB_NAME" -e "
        UPDATE \`${NEW_PREFIX}options\`
        SET option_name = '${NEW_PREFIX}user_roles'
        WHERE option_name = '${CURRENT_PREFIX}user_roles';
        SELECT ROW_COUNT();
    " 2>/dev/null | tail -n 1 || echo 0)"

    USERMETA_UPDATED="$(mysql --defaults-extra-file="$MYSQL_CNF" -N -s "$DB_NAME" -e "
        UPDATE \`${NEW_PREFIX}usermeta\`
        SET meta_key = CONCAT('${NEW_PREFIX}', SUBSTRING(meta_key, CHAR_LENGTH('${CURRENT_PREFIX}') + 1))
        WHERE meta_key LIKE '${CURRENT_PREFIX}%';
        SELECT ROW_COUNT();
    " 2>/dev/null | tail -n 1 || echo 0)"

    # 4. Update $table_prefix in wp-config.php preserving permissions
    sed -i -E "s/(\\\$table_prefix[[:space:]]*=[[:space:]]*)['\"][^'\"]*['\"][[:space:]]*;/\1'${NEW_PREFIX}';/" "$CONFIG_ABS"
    if grep -qE "\\\$table_prefix[[:space:]]*=[[:space:]]*'${NEW_PREFIX}';" "$CONFIG_ABS"; then
        CONFIG_UPDATED="true"
    else
        CONFIG_UPDATED="false"
        OVERALL_STATUS="PARTIAL"
    fi
fi

# ---- Reporting --------------------------------------------------------------
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

if [[ "$QUIET" -eq 0 ]]; then
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        printf '{\n'
        printf '  "version": "%s",\n' "$VERSION"
        printf '  "status": "%s",\n' "$OVERALL_STATUS"
        printf '  "config_path": "%s",\n' "$(json_escape "$CONFIG_ABS")"
        printf '  "database": "%s",\n' "$(json_escape "$DB_NAME")"
        printf '  "old_prefix": "%s",\n' "$(json_escape "$CURRENT_PREFIX")"
        printf '  "new_prefix": "%s",\n' "$(json_escape "$NEW_PREFIX")"
        printf '  "tables_count": %d,\n' "${#OLD_T[@]}"
        printf '  "options_rows_updated": %d,\n' "${OPTIONS_UPDATED:-0}"
        printf '  "usermeta_rows_updated": %d,\n' "${USERMETA_UPDATED:-0}"
        printf '  "config_updated": %s,\n' "$CONFIG_UPDATED"
        printf '  "sql_backup": "%s",\n' "$(json_escape "${DUMP_PATH:-none}")"
        printf '  "config_backup": "%s",\n' "$(json_escape "${CONFIG_BAK_PATH:-none}")"
        printf '  "dry_run": %s,\n' "$([[ "$DRY_RUN" -eq 1 ]] && echo true || echo false)"
        printf '  "timestamp": "%s",\n' "$TIMESTAMP_ISO"
        printf '  "tables": [\n'
        for i in "${!OLD_T[@]}"; do
            comma=","
            [[ "$i" -eq $((${#OLD_T[@]} - 1)) ]] && comma=""
            printf '    {"old": "%s", "new": "%s", "status": "%s"}%s\n' \
                "$(json_escape "${OLD_T[$i]}")" \
                "$(json_escape "${NEW_T[$i]}")" \
                "${T_STATUS[$i]}" \
                "$comma"
        done
        printf '  ]\n'
        printf '}\n'

    elif [[ "$OUTPUT_FORMAT" == "csv" ]]; then
        echo "timestamp,database,old_prefix,new_prefix,dry_run,old_table,new_table,status"
        for i in "${!OLD_T[@]}"; do
            printf '%s,"%s","%s","%s",%s,"%s","%s",%s\n' \
                "$TIMESTAMP_ISO" "$DB_NAME" "$CURRENT_PREFIX" "$NEW_PREFIX" \
                "$([[ "$DRY_RUN" -eq 1 ]] && echo true || echo false)" \
                "${OLD_T[$i]}" "${NEW_T[$i]}" "${T_STATUS[$i]}"
        done

    else
        BORDER="+------------------------------+------------------------------+--------------+"
        echo ""
        echo "${C_BOLD}WordPress Database Prefix Changer v${VERSION}${C_RESET}"
        echo "Config     : ${CONFIG_ABS}"
        echo "Database   : ${DB_NAME} (${DB_HOST_RAW})"
        echo "Prefix     : ${CURRENT_PREFIX} -> ${NEW_PREFIX}"
        echo "SQL Backup : ${DUMP_PATH:-none}"
        echo "Cfg Backup : ${CONFIG_BAK_PATH:-none}"
        echo "Dry-Run    : $([[ "$DRY_RUN" -eq 1 ]] && echo yes || echo no)"
        echo "Status     : ${OVERALL_STATUS}"
        echo "Timestamp  : ${TIMESTAMP_ISO}"
        echo ""
        echo "$BORDER"
        printf "| %-28s | %-28s | %-12s |\n" "Old Table" "New Table" "Status"
        echo "$BORDER"
        for i in "${!OLD_T[@]}"; do
            printf "| %-28s | %-28s | %-12s |\n" "${OLD_T[$i]}" "${NEW_T[$i]}" "${T_STATUS[$i]}"
        done
        echo "$BORDER"
        echo "Summary    : ${#OLD_T[@]} tables | options patched: ${OPTIONS_UPDATED} | usermeta patched: ${USERMETA_UPDATED} | wp-config updated: ${CONFIG_UPDATED}"
        echo ""
    fi
fi

[[ "$OVERALL_STATUS" == "PARTIAL" ]] && exit 4
exit 0
