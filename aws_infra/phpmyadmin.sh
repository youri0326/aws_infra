#!/bin/bash
# --------------------------------------------------
# 1. Webサーバーおよびデータベース管理ツールの導入
# --------------------------------------------------
sudo apt-get update -y
sudo apt-get install -y apache2 php libapache2-mod-php php-mysql php-mbstring wget unzip

# 管理ツールの取得と配置
sudo wget https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.zip -O /tmp/pma.zip
sudo unzip /tmp/pma.zip -d /var/www/html/
sudo mv /var/www/html/phpMyAdmin-5.2.1-all-languages /var/www/html/phpmyadmin
sudo rm /tmp/pma.zip

# 所有権およびアクセスの権限設定
sudo chown -R www-data:www-data /var/www/html/phpmyadmin
sudo chmod -R 755 /var/www/html/phpmyadmin

# Webサーバーの再起動と自動起動有効化
sudo systemctl restart apache2
sudo systemctl enable apache2


# --------------------------------------------------
# 2. データベース接続設定ファイルの配置
# --------------------------------------------------
# /var/www/html/phpmyadmin/config.inc.php を作成し、以下を記述します

<?php
$i = 0;
$i++;

/* 接続先データベースサーバーの設定 */
$cfg['Servers'][$i]['host'] = '<データベースのホスト名またはエンドポイント>';
$cfg['Servers'][$i]['port'] = '';
$cfg['Servers'][$i]['socket'] = '';
$cfg['Servers'][$i]['user'] = 'root';
$cfg['Servers'][$i]['password'] = 'root1234';
$cfg['Servers'][$i]['auth_type'] = 'config';

$cfg['Servers'][$i]['compress'] = false;
$cfg['Servers'][$i]['AllowNoPassword'] = false;

$cfg['UploadDir'] = '';
$cfg['SaveDir'] = '';
?>

# --------------------------------------------------
# 3. 設定ファイルの権限設定とサービスの更新
# --------------------------------------------------
sudo chown www-data:www-data /var/www/html/phpmyadmin/config.inc.php
sudo chmod 640 /var/www/html/phpmyadmin/config.inc.php

# Webサーバーの設定反映
sudo systemctl restart apache2
sudo systemctl enable apache2