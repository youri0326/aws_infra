#!/bin/bash
# -------------------------------
# 1. Apache, PHPのインストール
# -------------------------------
sudo dnf update -y
sudo dnf install -y httpd php php-cli php-common php-pdo php-mysqlnd

httpd -v
php -v

# -------------------------------
# 2. Apacheの起動と自動起動設定
# -------------------------------
sudo systemctl restart httpd
sudo systemctl enable httpd

# -------------------------------
# 3. 動作確認ファイルの作成（index.php）
# -------------------------------
# ※ $host には実際のRDSエンドポイントを指定してください
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
sudo chown -R apache:apache /var/www/html
sudo chmod -R 755 /var/www/html
