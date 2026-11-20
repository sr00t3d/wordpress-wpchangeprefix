# WordPress Database Prefix Changer

Readme: [EN](README.md)

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.0.0-green.svg)](https://github.com/sr00t3d/wpchangeprefix/releases)
[![Shell](https://img.shields.io/badge/bash-4.0+-blue.svg)](https://www.gnu.org/software/bash/)

<img width="700" src="wp-change-prefix-cover.webp" alt="WordPress Database Prefix Changer" />

**WordPress Database Prefix Changer v2.0.0** e um utilitario CLI em Bash para hardening de instalacoes WordPress que renomeia todas as tabelas MySQL/MariaDB do prefixo padrao `wp_` para um prefixo customizado ou aleatorio, atualiza referencias internas em `options` e `usermeta`, ajusta `$table_prefix` no `wp-config.php` e gera backups `chmod 600` automaticamente.

---

## Funcionalidades

- **Zero Exposicao de Senha no `ps aux`**: autentica no `mysql` e `mysqldump` via arquivo temporario `--defaults-extra-file` (`chmod 600`, com suporte seguro a senhas contendo `#` ou `;`) removido automaticamente via `trap`
- **Backups Automaticos (`chmod 600`)**: gera dump SQL com `--single-transaction` e copia `wp-config.php.bak.*` com timestamp antes de alterar qualquer tabela
- **Patch Interno Completo**: atualiza `*_user_roles` em `options` e todas as chaves com prefixo (`*_capabilities`, `*_user_level`, `*_user-settings`, etc.) em `usermeta`
- **Gerador de Prefixo Aleatorio (`--random`)**: cria prefixos criptograficamente aleatorios (`wp_<6hex>_`) a partir de `/dev/urandom`
- **Simulacao Dry-Run (`--dry-run`)**: lista todas as tabelas a renomear sem alterar banco nem `wp-config.php`
- **Relatorios Multi-Formato (`-o table|json|csv`)**: tabela ASCII, JSON para pipelines ou CSV para trilhas de auditoria
- **Validacao Estrita de Prefixo**: rejeita caracteres invalidos ou prefixo identico ao atual antes de executar SQL

---

## Requisitos

- Linux com Bash 4+
- Clientes `mysql` e `mysqldump`
- Permissao de leitura/escrita no `wp-config.php` e privilegios `ALTER`/`UPDATE` no banco WordPress

---

## Instalacao

```bash
curl -fsSLO https://raw.githubusercontent.com/sr00t3d/wpchangeprefix/main/wp-change-prefix.sh
chmod +x wp-change-prefix.sh
```

---

## Uso

```bash
./wp-change-prefix.sh [OPCOES]

Opcoes:
  -c, --config PATH       Caminho para o wp-config.php (padrao: ./wp-config.php)
  -p, --new-prefix STR    Novo prefixo de tabelas (alfanumerico/underscore, ex: wp_sec9_)
  --random                Gera prefixo aleatorio automaticamente (formato: wp_<6hex>_)
  -b, --backup-dir DIR    Diretorio para salvar dump SQL e backup do wp-config.php
  -s, --skip-backup       Ignora criacao de dump SQL e backup do wp-config.php
  -y, --yes               Pula confirmacao interativa
  --dry-run               Simula renomeio sem alterar banco ou arquivos
  -o, --output FORMATO    Formato de saida: table (padrao), json, csv
  -q, --quiet             Suprime saida padrao (mantem erros em stderr)
  --no-color              Desativa cores ANSI
  -V, --version           Exibe a versao e encerra
  -h, --help              Exibe a ajuda e encerra
```

### Exemplos

```bash
# Simular renomeio de tabelas sem aplicar alteracoes
./wp-change-prefix.sh -c /var/www/html/wp-config.php -p wp_sec9_ --dry-run

# Renomear tabelas com backup automatico de SQL e wp-config.php
./wp-change-prefix.sh -c /var/www/html/wp-config.php -p wp_sec9_ --yes

# Gerar prefixo aleatorio com saida JSON
./wp-change-prefix.sh -c /var/www/html/wp-config.php --random --yes -b /root/wp-backups -o json

# Execucao nao-interativa com saida CSV de auditoria
./wp-change-prefix.sh -c /var/www/html/wp-config.php -p wp_prod_ --yes -o csv
```

---

## Exemplo de Saida Real

Capturado em servidor AlmaLinux 8.10 com cPanel/WHM e MariaDB:

### Saida em tabela (padrao)

```text
$ ./wp-change-prefix.sh -c /tmp/wp-prefix-e2e/wp-config.php -p wp_sec9_ --yes --no-color

WordPress Database Prefix Changer v2.0.0
Config     : /tmp/wp-prefix-e2e/wp-config.php
Database   : wp_prefix_e2e (localhost)
Prefix     : wp_ -> wp_sec9_
SQL Backup : /tmp/wp-prefix-e2e/wp_prefix_e2e_wp_backup_20261120_054308.sql
Cfg Backup : /tmp/wp-prefix-e2e/wp-config.php.bak.20261120_054308
Dry-Run    : no
Status     : SUCCESS
Timestamp  : 2026-11-20T05:43:08Z

+------------------------------+------------------------------+--------------+
| Old Table                    | New Table                    | Status       |
+------------------------------+------------------------------+--------------+
| wp_options                   | wp_sec9_options              | RENAMED      |
| wp_postmeta                  | wp_sec9_postmeta             | RENAMED      |
| wp_posts                     | wp_sec9_posts                | RENAMED      |
| wp_usermeta                  | wp_sec9_usermeta             | RENAMED      |
| wp_users                     | wp_sec9_users                | RENAMED      |
+------------------------------+------------------------------+--------------+
Summary    : 5 tables | options patched: 1 | usermeta patched: 3 | wp-config updated: true
```

### Simulacao Dry-Run (`--dry-run`)

```text
$ ./wp-change-prefix.sh -c /tmp/wp-prefix-e2e/wp-config.php -p wp_sec9_ --dry-run --no-color

WordPress Database Prefix Changer v2.0.0
Config     : /tmp/wp-prefix-e2e/wp-config.php
Database   : wp_prefix_e2e (localhost)
Prefix     : wp_ -> wp_sec9_
SQL Backup : none
Cfg Backup : none
Dry-Run    : yes
Status     : DRY_RUN
Timestamp  : 2026-11-20T05:43:08Z

+------------------------------+------------------------------+--------------+
| Old Table                    | New Table                    | Status       |
+------------------------------+------------------------------+--------------+
| wp_options                   | wp_sec9_options              | WOULD_RENAME |
| wp_postmeta                  | wp_sec9_postmeta             | WOULD_RENAME |
| wp_posts                     | wp_sec9_posts                | WOULD_RENAME |
| wp_usermeta                  | wp_sec9_usermeta             | WOULD_RENAME |
| wp_users                     | wp_sec9_users                | WOULD_RENAME |
+------------------------------+------------------------------+--------------+
Summary    : 5 tables | options patched: 0 | usermeta patched: 0 | wp-config updated: false
```

### Saida JSON com prefixo aleatorio (`--random -o json`)

```json
{
  "version": "2.0.0",
  "status": "SUCCESS",
  "config_path": "/tmp/wp-prefix-e2e/wp-config.php",
  "database": "wp_prefix_e2e",
  "old_prefix": "wp_sec9_",
  "new_prefix": "wp_aff74d_",
  "tables_count": 5,
  "options_rows_updated": 1,
  "usermeta_rows_updated": 3,
  "config_updated": true,
  "sql_backup": "none",
  "config_backup": "none",
  "dry_run": false,
  "timestamp": "2026-11-20T05:43:09Z",
  "tables": [
    {"old": "wp_sec9_options", "new": "wp_aff74d_options", "status": "RENAMED"},
    {"old": "wp_sec9_postmeta", "new": "wp_aff74d_postmeta", "status": "RENAMED"},
    {"old": "wp_sec9_posts", "new": "wp_aff74d_posts", "status": "RENAMED"},
    {"old": "wp_sec9_usermeta", "new": "wp_aff74d_usermeta", "status": "RENAMED"},
    {"old": "wp_sec9_users", "new": "wp_aff74d_users", "status": "RENAMED"}
  ]
}
```

### Saida CSV (`-o csv`)

```csv
timestamp,database,old_prefix,new_prefix,dry_run,old_table,new_table,status
2026-11-20T05:43:09Z,"wp_prefix_e2e","wp_aff74d_","wp_prod_",false,"wp_aff74d_options","wp_prod_options",RENAMED
2026-11-20T05:43:09Z,"wp_prefix_e2e","wp_aff74d_","wp_prod_",false,"wp_aff74d_postmeta","wp_prod_postmeta",RENAMED
2026-11-20T05:43:09Z,"wp_prefix_e2e","wp_aff74d_","wp_prod_",false,"wp_aff74d_posts","wp_prod_posts",RENAMED
2026-11-20T05:43:09Z,"wp_prefix_e2e","wp_aff74d_","wp_prod_",false,"wp_aff74d_usermeta","wp_prod_usermeta",RENAMED
2026-11-20T05:43:09Z,"wp_prefix_e2e","wp_aff74d_","wp_prod_",false,"wp_aff74d_users","wp_prod_users",RENAMED
```

---

## Licenca

Apache-2.0. Consulte [LICENSE](LICENSE) para detalhes.

## Autor

[Percio Castelo](https://perciocastelo.com.br)
