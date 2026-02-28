# WordPress Database Prefix Changer

Readme: [BR](README-ptbr.md)

![License](https://img.shields.io/github/license/sr00t3d/wpchangeprefix)
![Shell Script](https://img.shields.io/badge/shell-script-green)

<img width="700" alt="BindFilter" src="wp-change-prefix-cover.webp" />

A powerful, safe, and automated Bash script to change the WordPress database table prefix. This tool handles the entire process: backing up the database, renaming tables, updating internal references (usermeta/options), and modifying `wp-config.php`.

## 🚀 Features

- **Auto-Discovery**: Automatically detects database credentials and the current prefix from wp-config.php.
- **Safety First**: Creates a full database backup (`.sql dump`) before applying any changes.
- **Deep Cleaning**: Not only renames tables but also updates critical rows in `_usermeta` and `_options` tables to prevent permission issues.
- **Config Update**: Automatically updates the `$table_prefix` variable in your `wp-config.php` file.
- **Self-Update**: Checks for the latest version of the script remotely.

## 📋 Prerequisites

To run this script, your environment must have:
- Linux/Unix OS (Ubuntu, Debian, CentOS, etc.)
- `bash` (shell)
- `mysql` and `mysqldump` (client tools)
- `grep`, `awk`
- `curl` or `wget` (for update checks)
- `Root/Sudo` access is recommended if file permissions are restricted, though not strictly required if the user owns the files.

## 📥 Installation

You can download the script directly to your WordPress root directory:

```bash
wget https://raw.githubusercontent.com/percioandrade/wpchangeprefix/refs/heads/main/wp-change-prefix.sh
chmod +x wp-change-prefix.sh
```

## ⚙️ Usage

**1. Navigate to your WordPress root directory (where wp-config.php is located).**

**2. Run the script:**

```bash
./wp-change-prefix.sh
```

**3. Follow the interactive prompts:**

- The script will verify credentials.
- It will show the current detected prefix.
- It will ask for the NEW prefix (alphanumeric only).
- Confirm the operation.

## Command Line Options

```bash
./wp-change-prefix.sh
```

`-s`, `--skip` Skip Backup: Executes the script without creating a database dump (Not recommended).

`-n`, `--noversion` No Version Check: Ignores remote checking for script updates.

`-h`, `--help` Displays the help menu.

**Example**

Table prefixes before modification:

```bash
mysql -u sql_wpdomain_com -p sql_wpdomain_com -e 'show tables;'

Enter password:
+------------------------------+
| Tables_in_sql_wpdomain_com |

+------------------------------+
| wp_8b7fba_commentmeta |

| wp_8b7fba_comments |

| wp_8b7fba_links |
| wp_8b7fba_options |
| wp_8b7fba_postmeta |
| wp_8b7fba_posts |
| wp_8b7fba_term_relationships |
| wp_8b7fba_term_taxonomy |
| wp_8b7fba_termmeta |
| wp_8b7fba_terms |
| wp_8b7fba_usermeta |
| wp_8b7fba_users |
+------------------------------+
```

Execution:

```bash
[root@evy wpdomain.com]# ./wpchange.sh
[!] Starting...
[+] Database credentials found:
------------------------
| DB: sql_wpdomain_com
| User: sql_wpdomain_com
| Host: localhost
------------------------
[+] Current prefix detected: 'wp_8b7fba_'
[!] Dumping database...
[+] Backup created at: /www/wwwroot/wpdomain.com/wp_8b7fba_db_backup_20260228003919.sql

Enter NEW prefix (e.g., 'newwp'): wpnew

[!] WARNING: This will change the prefix from 'wp_8b7fba_' to 'wpnew_'
Do you want to continue? (y/n): y
[+] Changing database tables...
[+] Renaming table: wp_8b7fba_commentmeta -> wpnew_commentmeta
[+] Renaming table: wp_8b7fba_comments -> wpnew_comments
[+] Renaming table: wp_8b7fba_links -> wpnew_links
[+] Renaming table: wp_8b7fba_options -> wpnew_options
[+] Renaming table: wp_8b7fba_postmeta -> wpnew_postmeta
[+] Renaming table: wp_8b7fba_posts -> wpnew_posts
[+] Renaming table: wp_8b7fba_term_relationships -> wpnew_term_relationships
[+] Renaming table: wp_8b7fba_term_taxonomy -> wpnew_term_taxonomy
[+] Renaming table: wp_8b7fba_termmeta -> wpnew_termmeta
[+] Renaming table: wp_8b7fba_terms -> wpnew_terms
[+] Renaming table: wp_8b7fba_usermeta -> wpnew_usermeta
[+] Renaming table: wp_8b7fba_users -> wpnew_users
[+] Updating internal rows (usermeta/options)...
[+] Updating $table_prefix variable in wp-config.php...
[+] Updating $table_prefix variable in wp-config.php...
--------------------------------------------------------
[+] Process completed successfully!
[+] New Prefix: wpnew_
[+] Database: sql_wpdomain_com
--------------------------------------------------------
```

Prefix after execution:

```bash
mysql -u sql_wpdomain_com -p sql_wpdomain_com -e 'show tables;'
Enter password:
+----------------------------+
| Tables_in_sql_wpdomain_com |
+----------------------------+
| wpnew_commentmeta |
| wpnew_comments |
| wpnew_links |
| wpnew_options |
| wpnew_postmeta |
| wpnew_posts |
| wpnew_term_relationships |
| wpnew_term_taxonomy |
| wpnew_termmeta |
| wpnew_terms |
| wpnew_usermeta |
| wpnew_users |
+----------------------------+
```

🛠️ How it Works

- **Validation**: Checks if `wp-config.php` exists and parses DB credentials.
- **Connection**: Tests connection to the MySQL server.
- **Detection**: Scans `information_schema` to find the active prefix (looking for `_usermeta` or `_options`).
- **Backup**: Runs `mysqldump` to save the current state.
- **Renaming**: Iterates through all tables matching the old prefix and renames them to the new prefix.
- **Data Patching**: Runs SQL updates to fix prefix references inside `usermeta` (keys like `wp_capabilities`) and options (keys `like wp_user_roles`).
- **Finalize**: Updates the PHP variable in the config file.

## ⚠️ Legal Notice

> [!WARNING]
> This software is provided "as is". Always ensure you have explicit permission before running. The author is not responsible for any misuse, legal consequences, or data impact caused by this tool.

## 📚 Detailed Tutorial

For a complete, step-by-step guide, check out my full article:

👉 [**Create modal popups in WHMCS**](https://perciocastelo.com.br/blog/change-wordpress-database-prefix.html)

## License 📄

This project is licensed under the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for more details.