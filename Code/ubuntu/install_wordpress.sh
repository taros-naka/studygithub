#!/usr/bin/env bash
# ファイル名: install_wordpress.sh
# Ubuntu 22.04 LTS / Apache 2.4 / MySQL 8.0 / PHP 8.1 で動作確認
set -euo pipefail

###############################################################################
# 0. 前提チェック
###############################################################################
[[ $EUID -eq 0 ]] || { echo "root で実行してください"; exit 1; }

###############################################################################
# 1. 変数定義 – ここだけ書き換えれば OK
###############################################################################
SQL_ROOT_PASSWORD="my_password"
WP_DB_NAME="wordpress"
WP_DB_USER="wordpressuser"
WP_DB_PASSWORD="Sql_Wp@Test1234"

DB_HOST="localhost"
DB_CHARSET="utf8mb4"

WP_PATH="/var/www/html/wordpress"   # インストール先
WP_SITE_TITLE="My WordPress Site"   # 後段の CLI で使う場合用

###############################################################################
# 2. パッケージ更新 & 必須ソフトウェア
###############################################################################
echo "=== パッケージ更新 ==="
apt update -qq
apt upgrade -y -qq

echo "=== 必要パッケージをインストール ==="
apt install -y -qq wget curl unzip ufw \
  apache2 \
  mysql-server \
  php libapache2-mod-php \
  php-mysql \
  php-{curl,gd,mbstring,xml,xmlrpc,soap,intl,zip,imagick}

###############################################################################
# 3. Apache 初期設定
###############################################################################
echo "=== Apache を有効化 ==="
systemctl enable --now apache2

# ドキュメントルート変更
sed -i "s|DocumentRoot /var/www/html|DocumentRoot ${WP_PATH}|g" \
  /etc/apache2/sites-available/000-default.conf

# .htaccess を使えるように
if ! grep -q "${WP_PATH}" /etc/apache2/apache2.conf; then
  cat >> /etc/apache2/apache2.conf <<EOF

<Directory ${WP_PATH}>
    AllowOverride All
</Directory>
EOF
fi

a2enmod rewrite
systemctl reload apache2

###############################################################################
# 4. UFW (ファイアウォール)
###############################################################################
echo "=== UFW (Apache Full) を許可 ==="
ufw allow 'Apache Full' >/dev/null 2>&1 || true   # UFW 無効なら無視

###############################################################################
# 5. MySQL セキュア設定 & WordPress 用 DB 作成
###############################################################################
echo "=== MySQL を有効化 ==="
systemctl enable --now mysql

echo "=== MySQL 初期セキュリティ強化 & WordPress DB 作成 ==="
mysql <<SQL
-- root パスワード設定
ALTER USER 'root'@'localhost'
  IDENTIFIED WITH mysql_native_password BY '${SQL_ROOT_PASSWORD}';

-- 不要ユーザー/DB 削除
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db IN ('test','test_%');

-- WordPress 用 DB・ユーザー
CREATE DATABASE IF NOT EXISTS ${WP_DB_NAME}
  DEFAULT CHARACTER SET ${DB_CHARSET} COLLATE ${DB_CHARSET}_general_ci;

CREATE USER IF NOT EXISTS '${WP_DB_USER}'@'${DB_HOST}'
  IDENTIFIED BY '${WP_DB_PASSWORD}';

GRANT ALL PRIVILEGES ON ${WP_DB_NAME}.* TO '${WP_DB_USER}'@'${DB_HOST}';
FLUSH PRIVILEGES;
SQL

###############################################################################
# 6. WordPress 本体の取得
###############################################################################
echo "=== WordPress を取得 ==="
install -d -m 0755 "${WP_PATH%/*}"
cd /tmp
wget -q https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
rm -f latest.tar.gz
mv wordpress "${WP_PATH}"

chown -R www-data:www-data "${WP_PATH}"
chmod -R 755 "${WP_PATH}"

###############################################################################
# 7. wp-config.php 生成
###############################################################################
echo "=== wp-config.php を生成 ==="
# SALT キー（失敗時はプレースホルダー）
SALT_KEYS="$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ || true)"
if [[ -z "$SALT_KEYS" ]]; then
  SALT_KEYS=$(yes "define('DUMMY','put your unique phrase here');" | head -n 8)
fi

cat > "${WP_PATH}/wp-config.php" <<EOF
<?php
/* WordPress 基本設定 */

define( 'DB_NAME', '${WP_DB_NAME}' );
define( 'DB_USER', '${WP_DB_USER}' );
define( 'DB_PASSWORD', '${WP_DB_PASSWORD}' );
define( 'DB_HOST', '${DB_HOST}' );
define( 'DB_CHARSET', '${DB_CHARSET}' );
define( 'DB_COLLATE', '' );

${SALT_KEYS}

\$table_prefix = 'wp_';
define( 'WP_DEBUG', false );

/* 編集終了 — "Happy publishing!" */
if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOF

###############################################################################
# 8. サービス再起動 & 完了
###############################################################################
echo "=== Apache をリロード ==="
systemctl reload apache2

echo "=============================================================="
echo "✔ WordPress インストール完了"
echo "  URL:  http://<サーバIP>/  （数分キャッシュが残る場合あり）"
echo "  初回セットアップ画面が表示されたらサイト情報を入力してください"
echo "=============================================================="
