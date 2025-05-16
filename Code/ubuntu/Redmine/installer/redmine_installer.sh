#!/bin/bash

# Redmineのインストール
# 参考URL：https://blog.redmine.jp/articles/6_0/install/ubuntu24/
# 5/16 1
# 概要：Redmineのインストールを行うスクリプト
#
# 注意：このスクリプトはUbuntu 24.04 LTSで動作確認済みですが、他のバージョンでも動作する可能性があります。
#       ただし、他のバージョンでの動作は保証されていません
#       sudo apt update
#       sudo apt upgrade -y
#       以上の操作後は、必ず再起動してください。

# ###################################################################################
# 定　義
# ###################################################################################
#　url:https://www.ruby-lang.org/ja/downloads/
RUBY_VERSION="ruby-3.3.8"
#　https://svn.redmine.org/redmine/branches/6.0-stable /var/lib/redmine
REDMINE_VERSION="6.0-stable " # ←Redmineのバージョンを指定(注意：stableの後にスペースが必要)

# データベースの設定
DB_NAME="redmine"
DB_USER="redmine"
DB_PASS="testpass"
DB_HOST="localhost"
DB_CODE="UTF-8"
DB_LANG="ja_JP.UTF-8"
DB_TEMPLATE="template0"

# smtpの設定
SMTP_HOST="localhost"
SMTP_PORT="25"
SMTP_DOMAIN="example.com"

# 接続を許可するサブネットの設定
# 例）
# SUBNET="192.168.0.0/24"
# SUBNET="10.0.0.0/8"
# SUBNET="0.0.0.0/0"
SUBNET="192.168.5.0/24"

# domainの設定
# 例）
# WEB_DOMAIN="example.com"
# WEB_DOMAIN="redmine.example.com"
WEB_DOMAIN="redmine.example.com"

#　サーバーアドミン
SERVER_ADMIN="webmaster@localhost"


# ###################################################################################
# インストール作業
# ###################################################################################
#　必要なパッケージをインストール
sudo apt install curl -y

#　ja_JP.UTF-8ロケールの作成
sudo apt install -y language-pack-ja
sudo locale-gen ja_JP.UTF-8
localectl list-locales

#　念のためUPDATE
sudo apt update

#　RubyとPassengerのビルドに必要な開発ツールやヘッダファイルのインストール
sudo apt install -y build-essential zlib1g-dev libssl-dev libreadline-dev libyaml-dev libcurl4-openssl-dev libffi-dev

# PostgreSQLとヘッダファイルのインストール
sudo apt install -y postgresql libpq-dev

# Apacheとヘッダファイルのインストール
sudo apt install -y apache2 apache2-dev

# 日本語フォントのインストール
sudo apt install -y imagemagick fonts-takao-pgothic

# そのほかのツールのインストール
sudo apt install -y subversion git

# ここから3.x系のRubyインストール url:https://www.ruby-lang.org/ja/downloads/ 
#　Rubyのインストール
curl -O https://cache.ruby-lang.org/pub/ruby/3.3/${RUBY_VERSION}.tar.gz
tar xvf ${RUBY_VERSION}.tar.gz
cd ${RUBY_VERSION}
./configure --disable-install-doc
make
sudo make install
cd ..

# Rubyの余計なファイルの削除
rm -rf ./${RUBY_VERSION}
rm -rf ./${RUBY_VERSION}.tar.gz

#　Rubyのバージョン確認
ruby -v

#　PostgreSQLの設定
#　Redmine用ユーザーの作成
sudo -i -u postgres psql -c "CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASS}'"
sudo -i -u postgres createdb -E $DB_CODE -l $DB_LANG -O $DB_USER -T $DB_TEMPLATE $DB_NAME

# redmineのファイルを配置するディレクトリを作成
sudo mkdir /var/lib/redmine
sudo chown www-data /var/lib/redmine
sudo -u www-data svn co https://svn.redmine.org/redmine/branches/${REDMINE_VERSION}/var/lib/redmine

#　Redmineのデータベースのコンフィグ設定ファイルを作成
sudo tee /var/lib/redmine/config/database.yml > /dev/null <<EOF
production:
  adapter: postgresql
  database: ${DB_NAME}
  host: ${DB_HOST}
  username: ${DB_USER}
  password: ${DB_PASS}
  encoding: utf8
EOF

#　RedmineのSMTPのコンフィグ設定ファイルを作成
sudo tee /var/lib/redmine/config/configuration.yml > /dev/null <<EOF
production:
  email_delivery:
    delivery_method: :smtp
    smtp_settings:
      address: "${SMTP_HOST}"
      port: ${SMTP_PORT}
      domain: "${SMTP_DOMAIN}"

  rmagick_font_path: /usr/share/fonts/truetype/takao-gothic/TakaoPGothic.ttf
EOF

#　RedmineのGemのインストール
cd /var/lib/redmine
sudo bundle config set --local without 'development test'
sudo bundle install

#Redmineの初期設定
sudo -u www-data bin/rake generate_secret_token
#データベースのテーブル作成
sudo -u www-data bin/rake db:migrate RAILS_ENV="production"

#PassengerのApache用モジュールのインストール
sudo gem install passenger -N
sudo passenger-install-apache2-module --auto --languages ruby

SNIPPET=$(passenger-install-apache2-module --snippet)
if [ -z "$SNIPPET" ]; then
    echo "Error: Failed to retrieve Passenger snippet."
    exit 1
fi

#1秒待機
sleep 1

#　Apacheの設定
#　PassengerのモジュールをApacheに組み込むための設定ファイルを作成
sudo tee /etc/apache2/conf-available/redmine.conf > /dev/null <<EOF
# Redmineの画像ファイル・CSSファイル等へのアクセスを許可する設定。
# Apache 2.4のデフォルトではサーバ上の全ファイルへのアクセスが禁止されている。


# Passengerの基本設定。
# passenger-install-apache2-module --snippet で表示された設定を記述。
# 環境によって設定値が異なるため以下の5行はそのまま転記せず、必ず
# passenger-install-apache2-module --snippet で表示されたものを使用すること。
#
$SNIPPET

# 必要に応じてPassengerのチューニングのための設定を追加（任意）。
# 詳しくは Configuration reference - Passenger + Apache (https://www.phusionpassenger.com/docs/references/config_reference/apache/) 参照。
PassengerMaxPoolSize 20
PassengerMaxInstancesPerApp 4
PassengerPoolIdleTime 864000
PassengerStatThrottleRate 10

# Redmineのインストールディレクトリへのアクセスを許可
<Directory /var/lib/redmine/public>
    Require ip ${SUBNET}
    Options -MultiViews -Indexes
    #AllowOverride all
    #Require all granted
</Directory>
EOF

# apacheのファイアーウォールの設定
#　アパッチのサービスポートを開放
#IPV6の無効化
sudo sed -i "s|IPV6=yes|IPV6=no|" "/etc/default/ufw"
# apacheのポートを開放
sudo ufw allow apache
# apacheの更新
sudo ufw reload

# Apacheのコンフィグ設定
# 000-default.confの設定を変更
#　アクセス許可のサブネットの設定
# ドメインの設定
sudo sed -i "s|^\s*#ServerAdmin .*|        ServerAdmin ${SERVER_ADMIN}|" "/etc/apache2/sites-enabled/000-default.conf"
# ドメインの設定
sudo sed -i "s|^\s*#ServerName .*|        ServerName ${WEB_DOMAIN}|" "/etc/apache2/sites-enabled/000-default.conf"
#　Apacheの設定を有効化
sudo a2enconf redmine
#　Apacheの設定を確認
apache2ctl configtest
#　Apacheの設定を再起動
sudo systemctl reload apache2

#　apt upgradeの実行
sudo apt update
sudo apt upgrade -y
sudo reboot
