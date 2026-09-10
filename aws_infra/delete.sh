# =====================================================
# 1. 共通環境変数の設定
# =====================================================
REGION="ap-northeast-1"
KEY_NAME="app-prod-key"


# =====================================================
# 2. ロードバランサー (ALB) およびターゲットグループの削除
# =====================================================
# ALB ARNの取得
ALB_ARN=$(aws elbv2 describe-load-balancers --names "web-app-alb" --query "LoadBalancers[0].LoadBalancerArn" --output text)

# ALBの削除
aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN

# ALB削除完了の待機
aws elbv2 wait load-balancers-deleted --load-balancer-arns $ALB_ARN

# ターゲットグループARNの取得と削除
TG_ARN=$(aws elbv2 describe-target-groups --names "web-app-tg" --query "TargetGroups[0].TargetGroupArn" --output text)
aws elbv2 delete-target-group --target-group-arn $TG_ARN


# =====================================================
# 3. EC2 インスタンスの削除 (全3台)
# =====================================================
# インスタンスIDの一括取得
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=App-Server-01,App-Server-02,Bastion-phpMyAdmin-Server" "Name=instance-state-name,Values=running,pending,stopped,stopping" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text)

# インスタンスの削除 (終了)
aws ec2 terminate-instances --instance-ids $INSTANCE_IDS

# インスタンス完全削除の待機
aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS


# =====================================================
# 4. RDS データベースの削除
# =====================================================
# DBインスタンスの削除 (スナップショットなし)
aws rds delete-db-instance \
  --db-instance-identifier "relational-db-master" \
  --skip-final-snapshot

# RDS削除完了の待機 (数分かかります)
aws rds wait db-instance-deleted --db-instance-identifier "relational-db-master"

# DBパラメータグループおよびサブネットグループの削除
aws rds delete-db-parameter-group --db-parameter-group-name "mariadb-custom-params"
aws rds delete-db-subnet-group --db-subnet-group-name "db-private-subnet-group"


# =====================================================
# 5. NAT ゲートウェイおよび Elastic IP の削除
# =====================================================
# NATゲートウェイIDの取得
NAT_ID=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=Egress-NAT-Gateway" "Name=state,Values=available" --query "NatGateways[0].NatGatewayId" --output text)

# NATゲートウェイの削除
aws ec2 delete-nat-gateway --nat-gateway-id $NAT_ID

# NATゲートウェイ削除完了の待機
aws ec2 wait nat-gateway-deleted --nat-gateway-ids $NAT_ID

# Elastic IPの解放 (Allocation ID取得後に解放)
EIP_ALLOC=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=NatGateway-EIP" --query "Addresses[0].AllocationId" --output text)
aws ec2 release-address --allocation-id $EIP_ALLOC


# =====================================================
# 6. セキュリティグループの削除
# =====================================================
# VPC IDの取得
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=Prod-VPC" --query "Vpcs[0].VpcId" --output text)

# セキュリティグループIDの取得
DB_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=sg_db" "Name=vpc-id,Values=${VPC_ID}" --query "SecurityGroups[0].GroupId" --output text)
WEB_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=sg_web" "Name=vpc-id,Values=${VPC_ID}" --query "SecurityGroups[0].GroupId" --output text)
BASTION_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=sg_bastion_phpmyadmin" "Name=vpc-id,Values=${VPC_ID}" --query "SecurityGroups[0].GroupId" --output text)
ALB_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=sg_alb" "Name=vpc-id,Values=${VPC_ID}" --query "SecurityGroups[0].GroupId" --output text)

# 依存関係の順序に従って削除
aws ec2 delete-security-group --group-id $DB_SG_ID
aws ec2 delete-security-group --group-id $WEB_SG_ID
aws ec2 delete-security-group --group-id $BASTION_SG_ID
aws ec2 delete-security-group --group-id $ALB_SG_ID


# =====================================================
# 7. ルートテーブル・サブネット・IGW・VPC の削除
# =====================================================
# パブリック・プライベートルートテーブルのID取得
PUB_RT_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Public-RouteTable" --query "RouteTables[0].RouteTableId" --output text)
PRIV_RT_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Private-RouteTable" --query "RouteTables[0].RouteTableId" --output text)

# ルートテーブルのサブネット関連付け解除 (Association IDを取得して解除)
PUB_ASSOC_IDS=$(aws ec2 describe-route-tables --route-table-ids $PUB_RT_ID --query "RouteTables[0].Associations[?!Main].RouteTableAssociationId" --output text)
for ASSOC_ID in $PUB_ASSOC_IDS; do aws ec2 disassociate-route-table --association-id $ASSOC_ID; done

PRIV_ASSOC_IDS=$(aws ec2 describe-route-tables --route-table-ids $PRIV_RT_ID --query "RouteTables[0].Associations[?!Main].RouteTableAssociationId" --output text)
for ASSOC_ID in $PRIV_ASSOC_IDS; do aws ec2 disassociate-route-table --association-id $ASSOC_ID; done

# ルートテーブルの削除
aws ec2 delete-route-table --route-table-id $PUB_RT_ID
aws ec2 delete-route-table --route-table-id $PRIV_RT_ID

# サブネットIDの一括取得と削除
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query "Subnets[*].SubnetId" --output text)
for SUB_ID in $SUBNET_IDS; do aws ec2 delete-subnet --subnet-id $SUB_ID; done

# インターネットゲートウェイのデタッチおよび削除
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=Main-IGW" --query "InternetGateways[0].InternetGatewayId" --output text)
aws ec2 detach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID

# VPCの削除
aws ec2 delete-vpc --vpc-id $VPC_ID


# =====================================================
# 8. キーペアおよびローカル鍵ファイルの削除
# =====================================================
# AWS上のキーペア削除
aws ec2 delete-key-pair --key-name $KEY_NAME

# ローカルのpemファイル削除
rm -f "${KEY_NAME}.pem"