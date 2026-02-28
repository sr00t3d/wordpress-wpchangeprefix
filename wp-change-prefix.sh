#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║                                                                           ║
# ║   WordPress Change Prefix v1.1.0                                          ║
# ║                                                                           ║
# ╠═══════════════════════════════════════════════════════════════════════════╣
# ║   Autor:   Percio Castelo                                                 ║
# ║   Contato: percio@evolya.com.br | contato@perciocastelo.com.br            ║
# ║   Web:     https://perciocastelo.com.br                                   ║
# ║                                                                           ║
# ║   Função:  Safely change WP database prefix, update                       ║
# ║            tables and wp-config.php.                                      ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

# --- CONFIGURATION ---
VERSION='1.1.0'
UPDATE_URL='https://raw.githubusercontent.com/percioandrade/wpchangeprefix/refs/heads/main/wpchange_prefix.sh'
CONFIG_FILE="wp-config.php"
# ---------------------

# Detect System Language
SYSTEM_LANG="${LANG:0:2}"

if [[ "$SYSTEM_LANG" == "pt" ]]; then
    # Portuguese Strings
    MSG_USAGE="Uso: $0 [-s|--skip] [-n|--noversion]"
    MSG_OPT_VER="Pular verificação de versão"
    MSG_OPT_SKIP="Pular backup do banco de dados"
    MSG_START="[!] Iniciando..."
    MSG_ERR_FILE="[!] Arquivo wp-config.php não encontrado, saindo..."
    MSG_FILE_FOUND="[+] Arquivo wp-config.php encontrado."
    MSG_ERR_VALUES="[!] Valores de conexão vazios, saindo..."
    MSG_DB_FOUND="[+] Credenciais do banco encontradas:"
    MSG_CHECK_PREFIX="[!] Verificando prefixo atual..."
    MSG_CONN_WAIT="[!] Tentando conectar ao banco, aguarde..."
    MSG_ERR_CONN="[!] Falha na conexão MySQL. Verifique credenciais."
    MSG_ERR_PREFIX="[!] Não foi possível determinar o prefixo atual."
    MSG_CUR_PREFIX="[+] Prefixo atual detectado:"
    MSG_SKIP_BACKUP="[!] Opção --skip usada. Backup ignorado."
    MSG_DUMPING="[!] Gerando dump do banco..."
    MSG_DUMP_OK="[+] Backup criado em:"
    MSG_INPUT_NEW="Digite o NOVO prefixo (ex: 'newwp'): "
    MSG_ERR_INVALID="[!] Prefixo inválido. Use apenas letras e números."
    MSG_WARN_CHANGE="[!] ATENÇÃO: Isso alterará o prefixo de"
    MSG_TO="para"
    MSG_CONFIRM="Deseja continuar? (y/n): "
    MSG_EXIT="Saindo..."
    MSG_CHANGING="[+] Alterando tabelas no banco de dados..."
    MSG_RENAMING="[+] Renomeando tabela:"
    MSG_UPDATING_ROWS="[+] Atualizando registros internos (usermeta/options)..."
    MSG_UPDATE_CONFIG="[+] Atualizando variável \$table_prefix no wp-config.php..."
    MSG_DONE="[+] Processo concluído com sucesso!"
    MSG_EMPTY_NEW="[!] Novo prefixo vazio. Nada feito."
else
    # English Strings (Default)
    MSG_USAGE="Usage: $0 [-s|--skip] [-n|--noversion]"
    MSG_OPT_VER="Skip version check"
    MSG_OPT_SKIP="Skip database dump creation"
    MSG_START="[!] Starting..."
    MSG_ERR_FILE="[!] File wp-config.php not found, exiting..."
    MSG_FILE_FOUND="[+] File wp-config.php was found."
    MSG_ERR_VALUES="[!] Empty connection values, exiting..."
    MSG_DB_FOUND="[+] Database credentials found:"
    MSG_CHECK_PREFIX="[!] Checking current prefix..."
    MSG_CONN_WAIT="[!] Trying to establish connection, please wait..."
    MSG_ERR_CONN="[!] MySQL connection failed. Check credentials."
    MSG_ERR_PREFIX="[!] Unable to determine current prefix."
    MSG_CUR_PREFIX="[+] Current prefix detected:"
    MSG_SKIP_BACKUP="[!] Skip option used. No backup generated."
    MSG_DUMPING="[!] Dumping database..."
    MSG_DUMP_OK="[+] Backup created at:"
    MSG_INPUT_NEW="Enter NEW prefix (e.g., 'newwp'): "
    MSG_ERR_INVALID="[!] Invalid prefix. Use only letters and numbers."
    MSG_WARN_CHANGE="[!] WARNING: This will change the prefix from"
    MSG_TO="to"
    MSG_CONFIRM="Do you want to continue? (y/n): "
    MSG_EXIT="Exiting..."
    MSG_CHANGING="[+] Changing database tables..."
    MSG_RENAMING="[+] Renaming table:"
    MSG_UPDATING_ROWS="[+] Updating internal rows (usermeta/options)..."
    MSG_UPDATE_CONFIG="[+] Updating \$table_prefix variable in wp-config.php..."
    MSG_DONE="[+] Process completed successfully!"
    MSG_EMPTY_NEW="[!] New prefix is empty. No changes made."
fi

# Function to display help
display_help() {
    cat <<-EOF
    $MSG_USAGE

    Options:
        -n, --noversion    $MSG_OPT_VER
        -s, --skip         $MSG_OPT_SKIP
EOF
}

if [[ $1 == "-h" ]] || [[ $1 == "--help" ]]; then
    display_help
    exit 0
fi

# Version Check logic
if [[ " $* " != *" -n "* && " $* " != *" --noversion "* ]]; then
    if command -v curl &> /dev/null; then
        V_REMOTE=$(curl -s "$UPDATE_URL" | grep -m1 "VERSION=" | cut -d "'" -f2)
        if [[ -z "$V_REMOTE" ]]; then V_REMOTE=$(curl -s "$UPDATE_URL" | grep -m1 "V=" | cut -d "'" -f2); fi
    fi
    if [[ -n "$V_REMOTE" && "$V_REMOTE" != "$VERSION" ]]; then
        echo "[!] Update available: $V_REMOTE (Current: $VERSION)"
    fi
fi

echo "$MSG_START"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "$MSG_ERR_FILE"
    exit 1
fi

get_db_value() {
    local key="$1"
    grep -E "define\s*\(\s*['\"]$key['\"]\s*," "$CONFIG_FILE" | awk -F "['\"]" '{print $4}'
}

DB_NAME=$(get_db_value "DB_NAME")
DB_USER=$(get_db_value "DB_USER")
DB_PASS=$(get_db_value "DB_PASSWORD")
DB_HOST=$(get_db_value "DB_HOST")

if [[ -z "${DB_NAME}" || -z "${DB_USER}" || -z "${DB_PASS}" || -z "${DB_HOST}" ]]; then
    echo "$MSG_ERR_VALUES"
    exit 1
fi

echo "$MSG_DB_FOUND"
echo "------------------------"
echo "| DB:   ${DB_NAME}"
echo "| User: ${DB_USER}"
echo "| Host: ${DB_HOST}"
echo "------------------------"

# Detect Prefix
DETECTED_TABLE=$(mysql -N -s -u "${DB_USER}" -p"${DB_PASS}" -h "${DB_HOST}" "${DB_NAME}" -e "SHOW TABLES LIKE '%options';" 2>/dev/null | head -n 1)
if [[ $? -ne 0 || -z "$DETECTED_TABLE" ]]; then
    echo "$MSG_ERR_CONN"
    exit 1
fi

CURRENT_PREFIX="${DETECTED_TABLE%options}"
echo "$MSG_CUR_PREFIX '$CURRENT_PREFIX'"

# Backup Logic
if [[ " $* " == *" -s "* || " $* " == *" --skip "* ]]; then
    echo "$MSG_SKIP_BACKUP"
else
    DUMP_FILE="${CURRENT_PREFIX}db_backup_$(date +%Y%m%d%H%M%S).sql"
    echo "$MSG_DUMPING"
    mysqldump -u "${DB_USER}" -p"${DB_PASS}" -h "${DB_HOST}" "${DB_NAME}" > "${DUMP_FILE}"
    echo "$MSG_DUMP_OK $(pwd)/${DUMP_FILE}"
fi

# New Prefix Input
read -p "$MSG_INPUT_NEW" RAW_NEW_PREFIX
if [[ -z "$RAW_NEW_PREFIX" ]]; then
    echo "$MSG_EMPTY_NEW"
    exit 1
fi

# Ensure it ends with underscore
NEW_PREFIX="${RAW_NEW_PREFIX%_}_"

echo -e "\n$MSG_WARN_CHANGE '$CURRENT_PREFIX' $MSG_TO '$NEW_PREFIX'"
read -p "$MSG_CONFIRM" CONFIRM
if [[ "${CONFIRM,,}" != "y" ]]; then
    echo "$MSG_EXIT"
    exit 0
fi

# Execute Database Changes
echo "$MSG_CHANGING"
TABLES=$(mysql -u "${DB_USER}" -p"${DB_PASS}" -h "${DB_HOST}" "${DB_NAME}" -N -B -e "SHOW TABLES LIKE '${CURRENT_PREFIX}%';")

for table in $TABLES; do
    suffix="${table#$CURRENT_PREFIX}"
    new_table_name="${NEW_PREFIX}${suffix}"
    echo "$MSG_RENAMING $table -> $new_table_name"
    mysql -u "${DB_USER}" -p"${DB_PASS}" -h "${DB_HOST}" "${DB_NAME}" -e "RENAME TABLE \`$table\` TO \`$new_table_name\`;"
done

echo "$MSG_UPDATING_ROWS"
mysql -u "${DB_USER}" -p"${DB_PASS}" -h "${DB_HOST}" "${DB_NAME}" -e "
    UPDATE \`${NEW_PREFIX}options\` SET option_name = '${NEW_PREFIX}user_roles' WHERE option_name = '${CURRENT_PREFIX}user_roles';
    UPDATE \`${NEW_PREFIX}usermeta\` SET meta_key = '${NEW_PREFIX}capabilities' WHERE meta_key = '${CURRENT_PREFIX}capabilities';
    UPDATE \`${NEW_PREFIX}usermeta\` SET meta_key = '${NEW_PREFIX}user_level' WHERE meta_key = '${CURRENT_PREFIX}user_level';
    UPDATE \`${NEW_PREFIX}usermeta\` SET meta_key = '${NEW_PREFIX}autosave_draft_ids' WHERE meta_key = '${CURRENT_PREFIX}autosave_draft_ids';
"

# Update wp-config.php
echo "$MSG_UPDATE_CONFIG"
sed -i "s/\$table_prefix = '[^']*';/\$table_prefix = '${NEW_PREFIX}';/g" "$CONFIG_FILE"
sed -i "s/\$table_prefix = \"[^\"]*\";/\$table_prefix = \"${NEW_PREFIX}\";/g" "$CONFIG_FILE"

# Final check on wp-config.php to confirm the change
CONFIRM_CONFIG=$(grep "table_prefix" "$CONFIG_FILE" | awk -F "['\"]" '{print $2}')

if [[ "$CONFIRM_CONFIG" == "$NEW_PREFIX" ]]; then
    echo "$MSG_UPDATE_CONFIG"
else
    # If sed fails for some permission reason or unexpected syntax
    echo "[!] Erro ao atualizar wp-config.php automaticamente."
    echo "[!] Por favor, altere manualmente a linha \$table_prefix para: '$NEW_PREFIX'"
fi

echo "--------------------------------------------------------"
echo "$MSG_DONE"
echo "[+] Novo Prefixo: $NEW_PREFIX"
echo "[+] Database: $DB_NAME"
echo "--------------------------------------------------------"

# Optional: Cache clearing suggestion if WP-CLI is available
if command -v wp &> /dev/null; then
    echo "[?] WP-CLI detectado. Deseja limpar o cache do site? (y/n)"
    read -r CLEAN_CACHE
    if [[ "${CLEAN_CACHE,,}" == "y" ]]; then
        wp cache flush
        echo "[+] Cache limpo!"
    fi
fi

exit 0