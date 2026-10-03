#!/bin/bash
# --------------------------------------------------
# 1. Webサーバーおよびデータベース管理ツールの導入
# --------------------------------------------------
# パッケージの更新
sudo dnf update -y

# Apache、PHPおよび拡張モジュールのインストール
sudo dnf install -y httpd php php-cli php-common php-mbstring php-xml php-pdo php-mysqlnd wget unzip

# 管理ツール (phpMyAdmin) の取得と配置
sudo wget https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.zip -O /tmp/pma.zip
sudo unzip /tmp/pma.zip -d /var/www/html/
sudo mv /var/www/html/phpMyAdmin-5.2.1-all-languages /var/www/html/phpmyadmin
sudo rm -f /tmp/pma.zip

# 所有権およびアクセスの権限設定（Amazon Linux の Apache 実行ユーザーは apache）
sudo chown -R apache:apache /var/www/html/phpmyadmin
sudo chmod -R 755 /var/www/html/phpmyadmin

# Webサーバーの起動と自動起動有効化
sudo systemctl start httpd
sudo systemctl enable httpd


# --------------------------------------------------
# 2. データベース接続設定ファイルの配置
# --------------------------------------------------
# 以下を実行して config.inc.php を直接作成・配置します
# ※ <RDSエンドポイント> の部分は実際のRDSエンドポイント（xxx.rds.amazonaws.com）に置き換えてください

sudo bash -c 'cat << "EOF" > /var/www/html/phpmyadmin/config.inc.php
<?php
$i = 0;
$i++;

/* 接続先データベースサーバーの設定 */
$cfg["Servers"][$i]["host"] = "<RDSエンドポイント>";
$cfg["Servers"][$i]["port"] = "";
$cfg["Servers"][$i]["socket"] = "";
$cfg["Servers"][$i]["user"] = "root";
$cfg["Servers"][$i]["password"] = "root1234";
$cfg["Servers"][$i]["auth_type"] = "config";

$cfg["Servers"][$i]["compress"] = false;
$cfg["Servers"][$i]["AllowNoPassword"] = false;

$cfg["UploadDir"] = "";
$cfg["SaveDir"] = "";
?>
EOF'


# --------------------------------------------------
# 3. 設定ファイルの権限設定とサービスの更新
# --------------------------------------------------
# 所有者と権限の設定
sudo chown apache:apache /var/www/html/phpmyadmin/config.inc.php
sudo chmod 640 /var/www/html/phpmyadmin/config.inc.php

# Webサーバーの設定反映
sudo systemctl restart httpd
