#!/bin/bash
# -------------------------------
# 1. Apache, PHPのインストール
# -------------------------------
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y apache2 php libapache2-mod-php php-mysql

sudo apache2 -v
sudo php -v

# -------------------------------
# 2. Apacheの起動と自動起動設定
# -------------------------------
sudo systemctl restart apache2
sudo systemctl enable apache2

# -------------------------------
# 3. 動作確認ファイルの作成（index.php）
# -------------------------------
# cat << 'EOF' を使うことで vi の代わりに自動でファイル作成・全置換します
sudo cat << 'EOF' | sudo tee /var/www/html/index.php > /dev/null
<?php
$host = '実際のrdsのエンドポイントを指定ください。';
$db   = 'awspracticedb';
$user = 'root';
$pass = 'root1234';

try {
    $pdo = new PDO("mysql:host=$host;dbname=$db;charset=utf8", $user, $pass);
    echo "DB接続成功！<br>";
    $stmt = $pdo->query("SELECT * FROM users");
    while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        echo $row['id'] . ": " . $row['name'] . "<br>";
    }
} catch (PDOException $e) {
    echo "DB接続失敗: " . $e->getMessage();
}
?>
EOF

# 既存のindex.htmlがあれば削除（index.phpを優先表示させるため）
sudo rm -f /var/www/html/index.html

# -------------------------------
# 4. 権限設定
# -------------------------------
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html