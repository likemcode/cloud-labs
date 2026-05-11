#!/bin/bash
# =============================================================================
# Three-Tier AWS Architecture — Teardown Script
# Destroys ALL resources created by deploy.sh
# =============================================================================
set -e

PROFILE="${1:-iamadmin}"
REGION="us-east-1"
VPC_ID="vpc-06317d0d65dcd6ff3"
BUCKET="three-tier-app-storage-146637284277"
BUCKET_ALT="three-tier-app-stg-146637284277"

echo "============================================"
echo " 🗑️  THREE-TIER TEARDOWN"
echo " Account: $(aws sts get-caller-identity --profile $PROFILE --query Account --output text 2>/dev/null || echo '?')"
echo "============================================"

# 1. TERMINATE EC2 INSTANCES
echo "[1/10] Terminating EC2 instances..."
INSTANCES=$(aws ec2 describe-instances --profile $PROFILE --region $REGION \
  --filters "Name=tag:Name,Values=three-tier-web,three-tier-app,three-tier-app-2" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null)

if [ -n "$INSTANCES" ]; then
  echo "  Terminating: $INSTANCES"
  aws ec2 terminate-instances --profile $PROFILE --region $REGION --instance-ids $INSTANCES
  echo "  Waiting for termination..."
  aws ec2 wait instance-terminated --profile $PROFILE --region $REGION --instance-ids $INSTANCES
else
  echo "  No instances found"
fi

# 2. DELETE ALB + LISTENER + TARGET GROUP
echo "[2/10] Deleting ALB and target group..."
ALB_ARN=$(aws elbv2 describe-load-balancers --profile $PROFILE --region $REGION \
  --names three-tier-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo "")

if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  aws elbv2 delete-load-balancer --profile $PROFILE --region $REGION --load-balancer-arn $ALB_ARN
  echo "  ALB deleted, waiting..."
  aws elbv2 wait load-balancers-deleted --profile $PROFILE --region $REGION --load-balancer-arns $ALB_ARN 2>/dev/null || sleep 10
fi

TG_ARN=$(aws elbv2 describe-target-groups --profile $PROFILE --region $REGION \
  --names three-tier-app-tg --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
  aws elbv2 delete-target-group --profile $PROFILE --region $REGION --target-group-arn $TG_ARN 2>/dev/null
  echo "  Target group deleted"
fi

# 3. DELETE WAF
echo "[3/10] Deleting WAF Web ACL..."
WAF_ACL_ARN=$(aws wafv2 list-web-acls --profile $PROFILE --region $REGION --scope REGIONAL \
  --query "WebACLs[?Name=='three-tier-web-acl'].ARN" --output text 2>/dev/null || echo "")
if [ -n "$WAF_ACL_ARN" ] && [ "$WAF_ACL_ARN" != "None" ] && [ "$WAF_ACL_ARN" != "" ]; then
  # First disassociate from ALB
  aws wafv2 disassociate-web-acl --profile $PROFILE --region $REGION \
    --resource-arn "$ALB_ARN" 2>/dev/null || true
  sleep 5
  aws wafv2 delete-web-acl --profile $PROFILE --region $REGION \
    --name three-tier-web-acl --scope REGIONAL --id $(echo $WAF_ACL_ARN | rev | cut -d'/' -f1 | rev) \
    --lock-token $(aws wafv2 get-web-acl --profile $PROFILE --region $REGION --name three-tier-web-acl --scope REGIONAL --id $(echo $WAF_ACL_ARN | rev | cut -d'/' -f1 | rev) --query 'LockToken' --output text) 2>/dev/null
  echo "  WAF deleted"
fi

# 4. DELETE RDS
echo "[4/10] Deleting RDS instance..."
RDS_EXISTS=$(aws rds describe-db-instances --profile $PROFILE --region $REGION \
  --db-instance-identifier three-tier-db --query 'DBInstances[0].DBInstanceIdentifier' --output text 2>/dev/null || echo "")
if [ -n "$RDS_EXISTS" ] && [ "$RDS_EXISTS" != "None" ]; then
  aws rds delete-db-instance --profile $PROFILE --region $REGION \
    --db-instance-identifier three-tier-db --skip-final-snapshot --delete-automated-backups
  echo "  RDS deletion initiated (takes ~5 min)..."
  aws rds wait db-instance-deleted --profile $PROFILE --region $REGION \
    --db-instance-identifier three-tier-db 2>/dev/null || echo "  (waiting in background)"
fi

# 5. DELETE DB SUBNET GROUP
echo "[5/10] Deleting DB subnet group..."
aws rds delete-db-subnet-group --profile $PROFILE --region $REGION \
  --db-subnet-group-name three-tier-db-subnet 2>/dev/null && echo "  DB subnet group deleted" || echo "  (not found or still in use)"

# 6. DELETE VPC ENDPOINT
echo "[6/10] Deleting VPC S3 endpoint..."
aws ec2 delete-vpc-endpoints --profile $PROFILE --region $REGION \
  --vpc-endpoint-ids $(aws ec2 describe-vpc-endpoints --profile $PROFILE --region $REGION \
    --filters "Name=tag:Name,Values=three-tier-s3-endpoint" \
    --query 'VpcEndpoints[*].VpcEndpointId' --output text 2>/dev/null) 2>/dev/null && \
  echo "  VPC endpoint deleted" || echo "  (not found)"

# 7. EMPTY + DELETE S3 BUCKETS
echo "[7/10] Emptying and deleting S3 buckets..."
for B in $BUCKET $BUCKET_ALT; do
  if aws s3api head-bucket --profile $PROFILE --bucket $B 2>/dev/null; then
    aws s3 rm s3://$B --recursive --profile $PROFILE 2>/dev/null
    aws s3api delete-bucket --profile $PROFILE --region $REGION --bucket $B 2>/dev/null && \
      echo "  Deleted: s3://$B" || echo "  Could not delete s3://$B (may have versioning)"
    # Force-delete versioned objects
    aws s3api delete-objects --profile $PROFILE --bucket $B \
      --delete "$(aws s3api list-object-versions --profile $PROFILE --bucket $B \
        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)" 2>/dev/null || true
    aws s3api delete-objects --profile $PROFILE --bucket $B \
      --delete "$(aws s3api list-object-versions --profile $PROFILE --bucket $B \
        --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)" 2>/dev/null || true
    aws s3api delete-bucket --profile $PROFILE --region $REGION --bucket $B 2>/dev/null && \
      echo "  Deleted (after version cleanup): s3://$B" || echo "  Still could not delete s3://$B"
  fi
done

# 8. DELETE SECURITY GROUPS
echo "[8/10] Deleting security groups..."
# Need to wait for dependencies (ALB, RDS) to release SGs
sleep 10
for SG_NAME in three-tier-alb-sg three-tier-web-sg three-tier-app-sg three-tier-db-sg; do
  SG_ID=$(aws ec2 describe-security-groups --profile $PROFILE --region $REGION \
    --filters "Name=group-name,Values=$SG_NAME" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
  if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    # Remove all ingress rules first
    aws ec2 describe-security-group-rules --profile $PROFILE --region $REGION \
      --filters "Name=group-id,Values=$SG_ID" \
      --query 'SecurityGroupRules[?IsEgress==`false`].SecurityGroupRuleId' --output text 2>/dev/null | \
      xargs -r -n1 aws ec2 revoke-security-group-ingress --profile $PROFILE --region $REGION \
        --group-id $SG_ID --security-group-rule-ids 2>/dev/null || true
    aws ec2 delete-security-group --profile $PROFILE --region $REGION --group-id $SG_ID 2>/dev/null && \
      echo "  Deleted: $SG_NAME ($SG_ID)" || echo "  Could not delete $SG_NAME (dependencies)"
  fi
done

# 9. DELETE SUBNETS + ROUTE TABLES + IGW
echo "[9/10] Deleting VPC resources..."

# Detach and delete IGW
IGW_ID=$(aws ec2 describe-internet-gateways --profile $PROFILE --region $REGION \
  --filters "Name=tag:Name,Values=three-tier-igw" --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "")
if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
  aws ec2 detach-internet-gateway --profile $PROFILE --region $REGION --internet-gateway-id $IGW_ID --vpc-id $VPC_ID 2>/dev/null
  aws ec2 delete-internet-gateway --profile $PROFILE --region $REGION --internet-gateway-id $IGW_ID 2>/dev/null && \
    echo "  IGW deleted" || echo "  IGW not ready"
fi

# Delete subnets
for SUBNET in $(aws ec2 describe-subnets --profile $PROFILE --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text 2>/dev/null); do
  aws ec2 delete-subnet --profile $PROFILE --region $REGION --subnet-id $SUBNET 2>/dev/null && \
    echo "  Subnet deleted: $SUBNET" || echo "  Subnet not ready: $SUBNET"
done

# Delete route tables (non-main ones)
for RT in $(aws ec2 describe-route-tables --profile $PROFILE --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=three-tier*" \
  --query 'RouteTables[*].RouteTableId' --output text 2>/dev/null); do
  aws ec2 delete-route-table --profile $PROFILE --region $REGION --route-table-id $RT 2>/dev/null && \
    echo "  Route table deleted: $RT" || echo "  Route table not ready: $RT"
done

# 10. DELETE VPC
echo "[10/10] Deleting VPC..."
aws ec2 delete-vpc --profile $PROFILE --region $REGION --vpc-id $VPC_ID 2>/dev/null && \
  echo "  VPC deleted: $VPC_ID" || echo "  VPC not ready (will auto-cleanup)"

# Clean up IAM
echo "  Cleaning IAM..."
aws iam remove-role-from-instance-profile --profile $PROFILE \
  --instance-profile-name three-tier-ec2-profile --role-name three-tier-ec2-s3-role 2>/dev/null || true
aws iam delete-instance-profile --profile $PROFILE \
  --instance-profile-name three-tier-ec2-profile 2>/dev/null || true
aws iam delete-role-policy --profile $PROFILE \
  --role-name three-tier-ec2-s3-role --policy-name S3Access 2>/dev/null || true
aws iam delete-role --profile $PROFILE --role-name three-tier-ec2-s3-role 2>/dev/null && \
  echo "  IAM cleaned" || echo "  IAM already clean"

# Clean up key pair and local files
aws ec2 delete-key-pair --profile $PROFILE --region $REGION --key-name three-tier-key 2>/dev/null || true
rm -f three-tier-key.pem 2>/dev/null

echo ""
echo "============================================"
echo " ✅ TEARDOWN COMPLETE"
echo "============================================"
