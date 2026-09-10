#!/bin/bash

# =====================================================
# 1. 共通環境変数の定義
# =====================================================
REGION="ap-northeast-1"
KEY_NAME="app-prod-key"


# =====================================================
# 2. ネットワーク（VPC / インターネットゲートウェイ）
# =====================================================
aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=Prod-VPC}]"

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=Prod-VPC" --query "Vpcs[0].VpcId" --output text)

aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support "{\"Value\":true}"
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames "{\"Value\":true}"

aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=Main-IGW}]"

IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=Main-IGW" --query "InternetGateways[0].InternetGatewayId" --output text)

aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID


# =====================================================
# 3. サブネットの構築（パブリック / プライベート）
# =====================================================
aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone ${REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Public-Subnet-1A}]"
aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone ${REGION}c \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Public-Subnet-1C}]"

aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.11.0/24 --availability-zone ${REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Private-Subnet-1A}]"
aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.12.0/24 --availability-zone ${REGION}c \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Private-Subnet-1C}]"

PUBA_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Public-Subnet-1A" --query "Subnets[0].SubnetId" --output text)
PUBB_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Public-Subnet-1C" --query "Subnets[0].SubnetId" --output text)
PRIVA_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Private-Subnet-1A" --query "Subnets[0].SubnetId" --output text)
PRIVB_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Private-Subnet-1C" --query "Subnets[0].SubnetId" --output text)


# =====================================================
# 4. パブリックルーティングの設定
# =====================================================
aws ec2 create-route-table --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=Public-RouteTable}]"

PUB_RT=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Public-RouteTable" --query "RouteTables[0].RouteTableId" --output text)

aws ec2 create-route --route-table-id $PUB_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID

aws ec2 associate-route-table --subnet-id $PUBA_ID --route-table-id $PUB_RT
aws ec2 associate-route-table --subnet-id $PUBB_ID --route-table-id $PUB_RT


# =====================================================
# 5. NAT ゲートウェイの構築
# =====================================================
EIP_ALLOC=$(aws ec2 allocate-address --domain vpc --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=NatGateway-EIP}]" --query 'AllocationId' --output text)

aws ec2 create-nat-gateway --subnet-id $PUBA_ID --allocation-id $EIP_ALLOC \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=Egress-NAT-Gateway}]"
aws ec2 wait nat-gateway-available --nat-gateway-ids $(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=Egress-NAT-Gateway" --query "NatGateways[0].NatGatewayId" --output text)

NAT_ID=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=Egress-NAT-Gateway" --query "NatGateways[0].NatGatewayId" --output text)


# =====================================================
# 6. プライベートルーティングの設定
# =====================================================
aws ec2 create-route-table --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=Private-RouteTable}]"

PRIV_RT=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Private-RouteTable" --query "RouteTables[0].RouteTableId" --output text)

aws ec2 create-route --route-table-id $PRIV_RT --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_ID

aws ec2 associate-route-table --subnet-id $PRIVA_ID --route-table-id $PRIV_RT
aws ec2 associate-route-table --subnet-id $PRIVB_ID --route-table-id $PRIV_RT


# =====================================================
# 7. セキュリティグループの設定（3階層＋統合管理ホスト）
# =====================================================
aws ec2 create-security-group --group-name "sg_alb" --description "Security Group for Application Load Balancer" --vpc-id $VPC_ID
aws ec2 create-security-group --group-name "sg_bastion_phpmyadmin" --description "Security Group for Bastion Host and phpMyAdmin" --vpc-id $VPC_ID
aws ec2 create-security-group --group-name "sg_web" --description "Security Group for Web App Servers" --vpc-id $VPC_ID
aws ec2 create-security-group --group-name "sg_db" --description "Security Group for Relational Database" --vpc-id $VPC_ID

ALB_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=sg_alb" --query "SecurityGroups[0].GroupId" --output text)
BastionMyAdmin_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=sg_bastion_phpmyadmin" --query "SecurityGroups[0].GroupId" --output text)
EC2_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=sg_web" --query "SecurityGroups[0].GroupId" --output text)
DB_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=sg_db" --query "SecurityGroups[0].GroupId" --output text)

aws ec2 create-tags --resources $ALB_SG --tags Key=Name,Value="ALB-SG"
aws ec2 create-tags --resources $BastionMyAdmin_SG --tags Key=Name,Value="Bastion-phpMyAdmin-SG"
aws ec2 create-tags --resources $EC2_SG --tags Key=Name,Value="Web-SG"
aws ec2 create-tags --resources $DB_SG --tags Key=Name,Value="Database-SG"

# インバウンドルール
aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $BastionMyAdmin_SG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $BastionMyAdmin_SG --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $EC2_SG --protocol tcp --port 80 --source-group $ALB_SG
aws ec2 authorize-security-group-ingress --group-id $EC2_SG --protocol tcp --port 22 --source-group $BastionMyAdmin_SG
aws ec2 authorize-security-group-ingress --group-id $DB_SG --protocol tcp --port 3306 --source-group $EC2_SG
aws ec2 authorize-security-group-ingress --group-id $DB_SG --protocol tcp --port 3306 --source-group $BastionMyAdmin_SG

# =====================================================
# 8. データベース（マネージド型DB）の構築
# =====================================================
aws rds create-db-subnet-group --db-subnet-group-name "db-private-subnet-group" --db-subnet-group-description "Private Subnet Group for Database" --subnet-ids $PRIVA_ID $PRIVB_ID

aws rds create-db-parameter-group \
    --db-parameter-group-name "mariadb-custom-params" \
    --db-parameter-group-family mariadb10.11 \
    --description "Custom configuration group for MariaDB"

aws rds modify-db-parameter-group \
    --db-parameter-group-name "mariadb-custom-params" \
    --parameters \
    "ParameterName=require_secure_transport,ParameterValue=OFF,ApplyMethod=immediate" \
    "ParameterName=max_connect_errors,ParameterValue=10000,ApplyMethod=immediate"

aws rds create-db-instance --db-instance-identifier "relational-db-master" --db-instance-class db.t3.micro \
  --engine mariadb --engine-version "10.11" \
  --master-username root --master-user-password root1234 --allocated-storage 20 \
  --vpc-security-group-ids $DB_SG --db-subnet-group-name "db-private-subnet-group" \
  --db-parameter-group-name "mariadb-custom-params" \
  --no-publicly-accessible --backup-retention-period 0 \
  --tags Key=Name,Value="Primary-Database"


# =====================================================
# 9. 仮想サーバー（EC2）の構築（計3台）
# =====================================================
aws ec2 create-key-pair --key-name $KEY_NAME --query "KeyMaterial" --output text > $KEY_NAME.pem
chmod 400 $KEY_NAME.pem

# Amazon Linux 2023 最新AMI IDの取得
AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query "Parameter.Value" \
  --output text \
  --region ap-northeast-1)

# ① Web App Server 01（プライベート配置）
aws ec2 run-instances --image-id $AMI_ID --count 1 --instance-type t2.micro --key-name $KEY_NAME \
  --security-group-ids $EC2_SG --subnet-id $PRIVA_ID \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=App-Server-01}]"

# ② Web App Server 02（プライベート配置）
aws ec2 run-instances --image-id $AMI_ID --count 1 --instance-type t2.micro --key-name $KEY_NAME \
  --security-group-ids $EC2_SG --subnet-id $PRIVB_ID \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=App-Server-02}]"

# ③ Bastion & phpMyAdmin Server（パブリック配置）
aws ec2 run-instances --image-id $AMI_ID --count 1 --instance-type t2.micro --key-name $KEY_NAME \
  --security-group-ids $BastionMyAdmin_SG --subnet-id $PUBA_ID --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Bastion-phpMyAdmin-Server}]"

WebServerA=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=App-Server-01" --query "Reservations[0].Instances[0].InstanceId" --output text)
WebServerB=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=App-Server-02" --query "Reservations[0].Instances[0].InstanceId" --output text)
BastionMyAdminInstance=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=Bastion-phpMyAdmin-Server" --query "Reservations[0].Instances[0].InstanceId" --output text)


# =====================================================
# 10. ロードバランサー（ALB）の構築
# =====================================================
aws elbv2 create-target-group --name "web-app-tg" --protocol HTTP --port 80 --vpc-id $VPC_ID --target-type instance

TG_ARN=$(aws elbv2 describe-target-groups --names "web-app-tg" --query "TargetGroups[0].TargetGroupArn" --output text)

aws elbv2 register-targets --target-group-arn $TG_ARN --targets Id=$WebServerA
aws elbv2 register-targets --target-group-arn $TG_ARN --targets Id=$WebServerB

aws elbv2 create-load-balancer --name "web-app-alb" --subnets $PUBA_ID $PUBB_ID --security-groups $ALB_SG --scheme internet-facing

ALB_ARN=$(aws elbv2 describe-load-balancers --names "web-app-alb" --query "LoadBalancers[0].LoadBalancerArn" --output text)

aws elbv2 create-listener --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$TG_ARN




# =====================================================
# 11. 接続情報の出力
# =====================================================
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier "relational-db-master" --query "DBInstances[0].Endpoint.Address" --output text)
echo "DB Endpoint: ${RDS_ENDPOINT}"

BASTION_MYADMIN_IP=$(aws ec2 describe-instances --instance-ids $BastionMyAdminInstance --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
echo "Bastion / phpMyAdmin Public IP: ${BASTION_MYADMIN_IP}"

WEBA_PRIV_IP=$(aws ec2 describe-instances --instance-ids $WebServerA --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)
echo "App Server 01 Private IP: ${WEBA_PRIV_IP}"

WEBB_PRIV_IP=$(aws ec2 describe-instances --instance-ids $WebServerB --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)
echo "App Server 02 Private IP: ${WEBB_PRIV_IP}"