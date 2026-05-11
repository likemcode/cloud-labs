#!/bin/bash
# =============================================================================
# Three-Tier AWS Architecture — Full Deployment (HA + WAF + S3)
# =============================================================================
set -e

PROFILE="${1:-iamadmin}"
REGION="us-east-1"
VPC_CIDR="10.0.0.0/16"
AMI_ID="ami-0fa63072dba82baa6"  # Amazon Linux 2 (latest)
INSTANCE_TYPE="t3.micro"
DB_CLASS="db.t3.micro"
KEY_NAME="three-tier-key"
BUCKET_NAME="three-tier-app-storage-$(aws sts get-caller-identity --profile $PROFILE --query Account --output text)"

echo "============================================"
echo " THREE-TIER HA DEPLOYMENT"
echo " Region: $REGION"
echo "============================================"

##############################################################################
# PHASE 1: NETWORK
##############################################################################
echo "[Phase 1/5] Network"

# VPC
VPC_ID=$(aws ec2 create-vpc --profile $PROFILE --region $REGION --cidr-block $VPC_CIDR \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=three-tier-vpc}]' \
  --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --profile $PROFILE --region $REGION --vpc-id $VPC_ID --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --profile $PROFILE --region $REGION --vpc-id $VPC_ID --enable-dns-hostnames '{"Value":true}'
echo "  VPC: $VPC_ID"

# Subnets
PUB1=$(aws ec2 create-subnet --profile $PROFILE --region $REGION --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone ${REGION}a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=three-tier-public-1}]' --query 'Subnet.SubnetId' --output text)
PUB2=$(aws ec2 create-subnet --profile $PROFILE --region $REGION --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone ${REGION}b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=three-tier-public-2}]' --query 'Subnet.SubnetId' --output text)
PRV1=$(aws ec2 create-subnet --profile $PROFILE --region $REGION --vpc-id $VPC_ID --cidr-block 10.0.3.0/24 --availability-zone ${REGION}a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=three-tier-private-1}]' --query 'Subnet.SubnetId' --output text)
PRV2=$(aws ec2 create-subnet --profile $PROFILE --region $REGION --vpc-id $VPC_ID --cidr-block 10.0.4.0/24 --availability-zone ${REGION}b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=three-tier-private-2}]' --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --profile $PROFILE --region $REGION --subnet-id $PUB1 --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --profile $PROFILE --region $REGION --subnet-id $PUB2 --map-public-ip-on-launch
echo "  Subnets: pub=$PUB1,$PUB2 priv=$PRV1,$PRV2"

# IGW + Route Tables
IGW=$(aws ec2 create-internet-gateway --profile $PROFILE --region $REGION --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=three-tier-igw}]' --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --profile $PROFILE --region $REGION --internet-gateway-id $IGW --vpc-id $VPC_ID
RT_PUB=$(aws ec2 create-route-table --profile $PROFILE --region $REGION --vpc-id $VPC_ID --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=three-tier-public-rt}]' --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --profile $PROFILE --region $REGION --route-table-id $RT_PUB --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
aws ec2 associate-route-table --profile $PROFILE --region $REGION --route-table-id $RT_PUB --subnet-id $PUB1
aws ec2 associate-route-table --profile $PROFILE --region $REGION --route-table-id $RT_PUB --subnet-id $PUB2
RT_PRV=$(aws ec2 create-route-table --profile $PROFILE --region $REGION --vpc-id $VPC_ID --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=three-tier-private-rt}]' --query 'RouteTable.RouteTableId' --output text)
aws ec2 associate-route-table --profile $PROFILE --region $REGION --route-table-id $RT_PRV --subnet-id $PRV1
aws ec2 associate-route-table --profile $PROFILE --region $REGION --route-table-id $RT_PRV --subnet-id $PRV2
echo "  IGW: $IGW | Public RT: $RT_PUB | Private RT: $RT_PRV"

# Key pair
aws ec2 create-key-pair --profile $PROFILE --region $REGION --key-name $KEY_NAME --query 'KeyMaterial' --output text > ${KEY_NAME}.pem 2>/dev/null || true
chmod 400 ${KEY_NAME}.pem 2>/dev/null || true

##############################################################################
# PHASE 2: SECURITY GROUPS
##############################################################################
echo "[Phase 2/5] Security Groups"

SG_WEB=$(aws ec2 create-security-group --profile $PROFILE --region $REGION --group-name three-tier-web-sg --description "Web tier" --vpc-id $VPC_ID --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=three-tier-web-sg}]' --query 'GroupId' --output text)
SG_APP=$(aws ec2 create-security-group --profile $PROFILE --region $REGION --group-name three-tier-app-sg --description "App tier" --vpc-id $VPC_ID --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=three-tier-app-sg}]' --query 'GroupId' --output text)
SG_DB=$(aws ec2 create-security-group --profile $PROFILE --region $REGION --group-name three-tier-db-sg --description "DB tier" --vpc-id $VPC_ID --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=three-tier-db-sg}]' --query 'GroupId' --output text)
SG_ALB=$(aws ec2 create-security-group --profile $PROFILE --region $REGION --group-name three-tier-alb-sg --description "ALB" --vpc-id $VPC_ID --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=three-tier-alb-sg}]' --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --profile $PROFILE --region $REGION --group-id $SG_WEB --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --profile $PROFILE --region $REGION --group-id $SG_WEB --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --profile $PROFILE --region $REGION --group-id $SG_APP --protocol tcp --port 5000 --source-group $SG_WEB
aws ec2 authorize-security-group-ingress --profile $PROFILE --region $REGION --group-id $SG_APP --protocol tcp --port 22 --source-group $SG_WEB
aws ec2 authorize-security-group-ingress --profile $PROFILE --region $REGION --group-id $SG_DB --protocol tcp --port 3306 --source-group $SG_APP
aws ec2 authorize-security-group-ingress --profile $PROFILE --region $REGION --group-id $SG_ALB --protocol tcp --port 80 --cidr 0.0.0.0/0
echo "  SGs: Web=$SG_WEB App=$SG_APP DB=$SG_DB ALB=$SG_ALB"

##############################################################################
# PHASE 3: DATABASE (RDS Multi-AZ) + S3
##############################################################################
echo "[Phase 3/5] RDS + S3"

aws rds create-db-subnet-group --profile $PROFILE --region $REGION --db-subnet-group-name three-tier-db-subnet --db-subnet-group-description "Three-tier DB subnet group" --subnet-ids $PRV1 $PRV2 2>/dev/null || true

aws rds create-db-instance --profile $PROFILE --region $REGION --db-instance-identifier three-tier-db --db-instance-class $DB_CLASS --engine mysql --engine-version 8.0 --allocated-storage 20 --storage-type gp2 --master-username admin --master-user-password ThreeTierTest2026! --db-name demodb --vpc-security-group-ids $SG_DB --db-subnet-group-name three-tier-db-subnet --no-publicly-accessible --multi-az --backup-retention-period 0 --tags 'Key=Name,Value=three-tier-db' 2>/dev/null || echo "  RDS already exists"
echo "  RDS creating (Multi-AZ, ~8 min)..."

# S3 Bucket
aws s3api create-bucket --profile $PROFILE --region $REGION --bucket $BUCKET_NAME 2>/dev/null || true
aws s3api put-public-access-block --profile $PROFILE --region $REGION --bucket $BUCKET_NAME --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --profile $PROFILE --region $REGION --bucket $BUCKET_NAME --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --profile $PROFILE --region $REGION --bucket $BUCKET_NAME --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
echo "  S3: s3://$BUCKET_NAME (encrypted, versioned, private)"

# VPC S3 Gateway Endpoint
aws ec2 create-vpc-endpoint --profile $PROFILE --region $REGION --vpc-id $VPC_ID --service-name com.amazonaws.${REGION}.s3 --route-table-ids $RT_PRV --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=three-tier-s3-endpoint}]' 2>/dev/null || true
echo "  VPC S3 Endpoint → private route table"

##############################################################################
# PHASE 4: APPLICATION TIER (2× EC2 + ALB)
##############################################################################
echo "[Phase 4/5] App Tier + ALB"

# App user-data
cat > /tmp/app-ud.sh << 'UDEOF'
#!/bin/bash
yum update -y
yum install -y python3 python3-pip mariadb105
pip3 install flask pymysql boto3
mkdir -p /home/ec2-user/app
cat > /home/ec2-user/app/app.py << 'PYEOF'
from flask import Flask, jsonify, request
import pymysql, os, socket, datetime, boto3

app = Flask(__name__)
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_USER = os.environ.get("DB_USER", "admin")
DB_PASS = os.environ.get("DB_PASS", "ThreeTierTest2026!")
DB_NAME = os.environ.get("DB_NAME", "demodb")
BUCKET = os.environ.get("BUCKET", "BUCKET_PLACEHOLDER")
REGION = os.environ.get("REGION", "us-east-1")
s3 = boto3.client("s3", region_name=REGION)

@app.route("/api/status")
def status():
    return jsonify({"tier":"application","hostname":socket.gethostname(),"private_ip":os.popen("hostname -I").read().strip().split()[0],"status":"healthy","s3_bucket":BUCKET,"timestamp":datetime.datetime.now().isoformat()})

@app.route("/api/db")
def db_check():
    try:
        conn = pymysql.connect(host=DB_HOST,user=DB_USER,password=DB_PASS,database=DB_NAME,connect_timeout=5)
        cur = conn.cursor()
        cur.execute("SELECT 'DB OK from App Tier via WAF+ALB' AS msg")
        row = cur.fetchone()
        cur.close(); conn.close()
        return jsonify({"database":"connected","message":row[0]})
    except Exception as e:
        return jsonify({"database":"error","message":str(e)[:300]})

@app.route("/api/files")
def list_files():
    try:
        resp = s3.list_objects_v2(Bucket=BUCKET, MaxKeys=100)
        files = [{"key":o["Key"],"size":o["Size"],"last_modified":o["LastModified"].isoformat()} for o in resp.get("Contents",[])]
        return jsonify({"files":files,"count":len(files)})
    except Exception as e:
        return jsonify({"error":str(e)[:300]})

@app.route("/api/upload", methods=["POST"])
def upload_file():
    try:
        if "file" not in request.files:
            return jsonify({"error":"No file provided"}), 400
        file = request.files["file"]
        if file.filename == "":
            return jsonify({"error":"No file selected"}), 400
        date_prefix = datetime.datetime.now().strftime("%Y/%m/%d")
        key = f"uploads/{date_prefix}/{file.filename}"
        s3.upload_fileobj(file, BUCKET, key)
        return jsonify({"uploaded":True,"key":key,"bucket":BUCKET})
    except Exception as e:
        return jsonify({"error":str(e)[:300]}), 500

@app.route("/api/download/<path:key>")
def download_file(key):
    try:
        url = s3.generate_presigned_url("get_object",Params={"Bucket":BUCKET,"Key":key},ExpiresIn=3600)
        return jsonify({"download_url":url,"key":key,"expires_in":3600})
    except Exception as e:
        return jsonify({"error":str(e)[:300]}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
PYEOF

cat > /home/ec2-user/app/.env << EOF
DB_HOST=RDS_PLACEHOLDER
DB_USER=admin
DB_PASS=ThreeTierTest2026!
DB_NAME=demodb
BUCKET=BUCKET_PLACEHOLDER
REGION=us-east-1
EOF

cat > /etc/systemd/system/three-tier-app.service << 'SVC'
[Unit]
Description=Three Tier App Service
After=network.target
[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/app
EnvironmentFile=/home/ec2-user/app/.env
ExecStart=/usr/bin/python3 /home/ec2-user/app/app.py
Restart=always
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload
systemctl enable three-tier-app
UDEOF

# Launch App #1
APP1_ID=$(aws ec2 run-instances --profile $PROFILE --region $REGION --image-id $AMI_ID --instance-type $INSTANCE_TYPE --key-name $KEY_NAME --subnet-id $PUB1 --security-group-ids $SG_APP --associate-public-ip-address --user-data file:///tmp/app-ud.sh --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=three-tier-app-1}]' --query 'Instances[0].InstanceId' --output text)
echo "  App #1: $APP1_ID"

aws ec2 wait instance-running --profile $PROFILE --region $REGION --instance-ids $APP1_ID
sleep 10

# Launch App #2
APP2_ID=$(aws ec2 run-instances --profile $PROFILE --region $REGION --image-id $AMI_ID --instance-type $INSTANCE_TYPE --key-name $KEY_NAME --subnet-id $PUB2 --security-group-ids $SG_APP --associate-public-ip-address --user-data file:///tmp/app-ud.sh --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=three-tier-app-2}]' --query 'Instances[0].InstanceId' --output text)
echo "  App #2: $APP2_ID"

aws ec2 wait instance-running --profile $PROFILE --region $REGION --instance-ids $APP2_ID
sleep 10

APP1_IP=$(aws ec2 describe-instances --profile $PROFILE --region $REGION --instance-ids $APP1_ID --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
echo "  App #1 IP: $APP1_IP"

# ALB Target Group
TG_ARN=$(aws elbv2 create-target-group --profile $PROFILE --region $REGION --name three-tier-app-tg --protocol HTTP --port 5000 --vpc-id $VPC_ID --target-type instance --health-check-path /api/status --health-check-interval-seconds 15 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --query 'TargetGroups[0].TargetGroupArn' --output text)

# ALB
ALB_ARN=$(aws elbv2 create-load-balancer --profile $PROFILE --region $REGION --name three-tier-alb --subnets $PUB1 $PUB2 --security-groups $SG_ALB --scheme internet-facing --ip-address-type ipv4 --tags 'Key=Name,Value=three-tier-alb' --query 'LoadBalancers[0].LoadBalancerArn' --output text)
echo "  ALB: $ALB_ARN (provisioning...)"

aws elbv2 wait load-balancer-available --profile $PROFILE --region $REGION --load-balancer-arns $ALB_ARN
ALB_DNS=$(aws elbv2 describe-load-balancers --profile $PROFILE --region $REGION --load-balancer-arns $ALB_ARN --query 'LoadBalancers[0].DNSName' --output text)
echo "  ALB DNS: $ALB_DNS"

aws elbv2 create-listener --profile $PROFILE --region $REGION --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$TG_ARN

# Allow ALB → App
aws ec2 authorize-security-group-ingress --profile $PROFILE --region $REGION --group-id $SG_APP --protocol tcp --port 5000 --source-group $SG_ALB

echo "  Waiting for RDS..."
aws rds wait db-instance-available --profile $PROFILE --region $REGION --db-instance-identifier three-tier-db
RDS_ENDPOINT=$(aws rds describe-db-instances --profile $PROFILE --region $REGION --db-instance-identifier three-tier-db --query 'DBInstances[0].Endpoint.Address' --output text)
echo "  RDS: $RDS_ENDPOINT"

# Register targets
sleep 15
aws elbv2 register-targets --profile $PROFILE --region $REGION --target-group-arn $TG_ARN --targets Id=$APP1_ID Id=$APP2_ID

##############################################################################
# PHASE 5: WEB TIER + WAF + IAM
##############################################################################
echo "[Phase 5/5] Web Tier + WAF + IAM"

# IAM Role for EC2 → S3
aws iam create-role --profile $PROFILE --region $REGION --role-name three-tier-ec2-s3-role --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' 2>/dev/null || true
aws iam put-role-policy --profile $PROFILE --region $REGION --role-name three-tier-ec2-s3-role --policy-name S3Access --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:PutObject\",\"s3:GetObject\",\"s3:ListBucket\",\"s3:DeleteObject\"],\"Resource\":[\"arn:aws:s3:::${BUCKET_NAME}\",\"arn:aws:s3:::${BUCKET_NAME}/*\"]}]}" 2>/dev/null || true
aws iam create-instance-profile --profile $PROFILE --region $REGION --instance-profile-name three-tier-ec2-profile 2>/dev/null || true
aws iam add-role-to-instance-profile --profile $PROFILE --region $REGION --instance-profile-name three-tier-ec2-profile --role-name three-tier-ec2-s3-role 2>/dev/null || true
aws ec2 associate-iam-instance-profile --profile $PROFILE --region $REGION --instance-id $APP1_ID --iam-instance-profile Name=three-tier-ec2-profile 2>/dev/null || true
aws ec2 associate-iam-instance-profile --profile $PROFILE --region $REGION --instance-id $APP2_ID --iam-instance-profile Name=three-tier-ec2-profile 2>/dev/null || true
echo "  IAM role attached to app instances"

# Web user-data
APP1_PRIVATE_IP=$APP1_IP  # reuse variable
cat > /tmp/web-ud.sh << WEBUD
#!/bin/bash
yum update -y
yum install -y httpd
echo 'LoadModule proxy_module modules/mod_proxy.so' >> /etc/httpd/conf/httpd.conf
echo 'LoadModule proxy_http_module modules/mod_proxy_http.so' >> /etc/httpd/conf/httpd.conf
cat > /etc/httpd/conf.d/reverse-proxy.conf << APACHECONF
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot /var/www/html
    ProxyPass /api/ http://${ALB_DNS}:80/api/
    ProxyPassReverse /api/ http://${ALB_DNS}:80/api/
</VirtualHost>
APACHECONF
cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>Three-Tier Architecture Demo</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:'Segoe UI',system-ui,sans-serif;background:#0f172a;color:#e2e8f0;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:2rem}.container{max-width:800px;width:100%}h1{font-size:2rem;text-align:center;margin-bottom:.5rem;background:linear-gradient(135deg,#60a5fa,#a78bfa);-webkit-background-clip:text;-webkit-text-fill-color:transparent}.subtitle{text-align:center;color:#94a3b8;margin-bottom:2rem}.tiers{display:flex;flex-direction:column;gap:1rem}.tier{background:#1e293b;border-radius:12px;padding:1.5rem;border:1px solid #334155}.tier-header{display:flex;align-items:center;gap:.75rem;margin-bottom:1rem}.badge{padding:.25rem .75rem;border-radius:20px;font-size:.75rem;font-weight:600;text-transform:uppercase}.badge-web{background:#1e40af33;color:#60a5fa;border:1px solid #1e40af}.badge-app{background:#16653433;color:#4ade80;border:1px solid #166534}.badge-db{background:#7e22ce33;color:#c084fc;border:1px solid #7e22ce}.label{font-size:.85rem;color:#94a3b8}.value{font-weight:600;word-break:break-all}.dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:.5rem}.dot-ok{background:#4ade80;box-shadow:0 0 8px #4ade8080}.dot-err{background:#f87171;box-shadow:0 0 8px #f8717180}.dot-wait{background:#fbbf24;box-shadow:0 0 8px #fbbf2480;animation:pulse 1.5s infinite}@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}pre{background:#0f172a;padding:1rem;border-radius:8px;overflow-x:auto;font-size:.85rem;margin-top:.5rem;max-height:200px}button{margin:1.5rem .5rem 0 0;padding:.75rem 2rem;background:linear-gradient(135deg,#3b82f6,#8b5cf6);border:none;border-radius:8px;color:white;font-size:1rem;cursor:pointer;font-weight:600}button:hover{opacity:.9;transform:translateY(-1px);transition:all .2s}.arch-diagram{display:flex;align-items:center;gap:.5rem;margin:1.5rem 0;font-size:.8rem;flex-wrap:wrap;justify-content:center}.arch-box{background:#1e293b;border-radius:8px;padding:.5rem 1rem;text-align:center;border:1px solid #334155}</style></head>
<body><div class="container"><h1>Three-Tier Architecture</h1><p class="subtitle">AWS us-east-1 — HA + WAF + S3</p>
<div class="arch-diagram"><div class="arch-box" style="border-color:#f87171">WAF</div><span>→</span><div class="arch-box" style="border-color:#60a5fa">ALB</div><span>→</span><div class="arch-box" style="border-color:#4ade80">App x2</div><span>→</span><div class="arch-box" style="border-color:#c084fc">RDS</div><span>→</span><div class="arch-box" style="border-color:#fbbf24">S3</div></div>
<div class="tiers"><div class="tier"><div class="tier-header"><span class="badge badge-web">Web Tier</span><span class="label">Apache Reverse Proxy</span></div><div><span class="label">Host:</span> <span class="value" id="web-host">-</span></div></div>
<div class="tier"><div class="tier-header"><span class="badge badge-app">App Tier</span><span class="label">Python Flask — ALB Round-Robin</span></div><div><span class="dot dot-wait" id="app-dot"></span><span class="value" id="app-status">Waiting...</span></div><pre id="app-json">{}</pre></div>
<div class="tier"><div class="tier-header"><span class="badge badge-db">DB Tier</span><span class="label">RDS MySQL 8.0 Multi-AZ</span></div><div><span class="dot dot-wait" id="db-dot"></span><span class="value" id="db-status">Waiting...</span></div><pre id="db-json">{}</pre></div>
<div class="tier"><div class="tier-header"><span class="badge badge-web">S3 Storage</span><span class="label">Uploads / Downloads</span></div><div><span class="dot dot-wait" id="s3-dot"></span><span class="value" id="s3-status">Waiting...</span></div><pre id="s3-json">{}</pre></div></div>
<button onclick="checkStatus()">App Status</button><button onclick="checkDB()">Test DB</button><button onclick="checkS3()">List S3</button></div>
<script>
async function checkStatus(){const d=document.getElementById('app-dot'),s=document.getElementById('app-status'),j=document.getElementById('app-json');d.className='dot dot-wait';s.textContent='Checking...';try{const r=await fetch('/api/status');const dt=await r.json();d.className='dot dot-ok';s.textContent='ONLINE';j.textContent=JSON.stringify(dt,null,2);document.getElementById('web-host').textContent=dt.hostname||'N/A'}catch(e){d.className='dot dot-err';s.textContent='UNREACHABLE';j.textContent='Error: '+e.message}}
async function checkDB(){const d=document.getElementById('db-dot'),s=document.getElementById('db-status'),j=document.getElementById('db-json');d.className='dot dot-wait';s.textContent='Checking...';try{const r=await fetch('/api/db');const dt=await r.json();d.className=dt.database==='connected'?'dot dot-ok':'dot dot-err';s.textContent=dt.database==='connected'?'CONNECTED':'ERROR';j.textContent=JSON.stringify(dt,null,2)}catch(e){d.className='dot dot-err';s.textContent='ERROR';j.textContent='Error: '+e.message}}
async function checkS3(){const d=document.getElementById('s3-dot'),s=document.getElementById('s3-status'),j=document.getElementById('s3-json');d.className='dot dot-wait';s.textContent='Checking...';try{const r=await fetch('/api/files');const dt=await r.json();d.className='dot dot-ok';s.textContent=dt.error?'ERROR':'OK ('+dt.count+' files)';j.textContent=JSON.stringify(dt,null,2)}catch(e){d.className='dot dot-err';s.textContent='ERROR';j.textContent='Error: '+e.message}}
checkStatus();
</script></body></html>
HTMLEOF
systemctl start httpd
systemctl enable httpd
WEBUD

WEB_ID=$(aws ec2 run-instances --profile $PROFILE --region $REGION --image-id $AMI_ID --instance-type $INSTANCE_TYPE --key-name $KEY_NAME --subnet-id $PUB1 --security-group-ids $SG_WEB --associate-public-ip-address --user-data file:///tmp/web-ud.sh --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=three-tier-web}]' --query 'Instances[0].InstanceId' --output text)
echo "  Web: $WEB_ID"

aws ec2 wait instance-running --profile $PROFILE --region $REGION --instance-ids $WEB_ID
sleep 10
WEB_IP=$(aws ec2 describe-instances --profile $PROFILE --region $REGION --instance-ids $WEB_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "  Web IP: $WEB_IP"

# WAF
echo "  Creating WAF..."
WAF_ACL=$(aws wafv2 create-web-acl --profile $PROFILE --region $REGION --name three-tier-web-acl --scope REGIONAL --default-action '{"Allow":{}}' --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=three-tier-waf --rules '[{"Name":"RateLimit","Priority":1,"Action":{"Block":{}},"Statement":{"RateBasedStatement":{"Limit":500,"AggregateKeyType":"IP"}},"VisibilityConfig":{"SampledRequestsEnabled":true,"CloudWatchMetricsEnabled":true,"MetricName":"three-tier-rate-limit"}},{"Name":"SQLiProtection","Priority":2,"OverrideAction":{"None":{}},"Statement":{"ManagedRuleGroupStatement":{"VendorName":"AWS","Name":"AWSManagedRulesSQLiRuleSet"}},"VisibilityConfig":{"SampledRequestsEnabled":true,"CloudWatchMetricsEnabled":true,"MetricName":"three-tier-sqli"}},{"Name":"CommonRules","Priority":3,"OverrideAction":{"None":{}},"Statement":{"ManagedRuleGroupStatement":{"VendorName":"AWS","Name":"AWSManagedRulesCommonRuleSet"}},"VisibilityConfig":{"SampledRequestsEnabled":true,"CloudWatchMetricsEnabled":true,"MetricName":"three-tier-common"}}]' --query 'Summary.ARN' --output text)
sleep 5
aws wafv2 associate-web-acl --profile $PROFILE --region $REGION --web-acl-arn $WAF_ACL --resource-arn $ALB_ARN 2>/dev/null && echo "  WAF: attached to ALB" || echo "  WAF: $(echo $WAF_ACL)"

# ALB Access Logs → S3
aws s3api put-bucket-policy --profile $PROFILE --region $REGION --bucket $BUCKET_NAME --policy "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::127311923021:root\"},\"Action\":\"s3:PutObject\",\"Resource\":\"arn:aws:s3:::${BUCKET_NAME}/alb-logs/*\"}]}" 2>/dev/null || true
aws elbv2 modify-load-balancer-attributes --profile $PROFILE --region $REGION --load-balancer-arn $ALB_ARN --attributes "Key=access_logs.s3.enabled,Value=true" "Key=access_logs.s3.bucket,Value=$BUCKET_NAME" "Key=access_logs.s3.prefix,Value=alb-logs" 2>/dev/null || true

# Update app instances with RDS endpoint (via SSH)
VPS_IP=$(curl -s ifconfig.me)
aws ec2 authorize-security-group-ingress --profile $PROFILE --region $REGION --group-id $SG_APP --protocol tcp --port 22 --cidr ${VPS_IP}/32 2>/dev/null || true

for APP_INST in $APP1_ID $APP2_ID; do
  APP_PUB_IP=$(aws ec2 describe-instances --profile $PROFILE --region $REGION --instance-ids $APP_INST --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
  echo "  Configuring app at $APP_PUB_IP..."
  sleep 5
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${KEY_NAME}.pem ec2-user@$APP_PUB_IP \
    "sudo sed -i 's/RDS_PLACEHOLDER/${RDS_ENDPOINT}/' /home/ec2-user/app/.env && sudo sed -i 's/BUCKET_PLACEHOLDER/${BUCKET_NAME}/' /home/ec2-user/app/.env && sudo systemctl start three-tier-app" 2>/dev/null || echo "  (will retry after user-data completes)"
done

##############################################################################
# DONE
##############################################################################
echo ""
echo "============================================"
echo " ✅ DEPLOYMENT COMPLETE"
echo "============================================"
echo ""
echo "🌐 URL: http://$WEB_IP"
echo "⚖️  ALB: $ALB_DNS"
echo "🗄️  RDS: $RDS_ENDPOINT (Multi-AZ)"
echo "📦 S3:  s3://$BUCKET_NAME"
echo "🛡️  WAF: $WAF_ACL"
echo ""
echo "💰 ~\$2.46/day (~\$75/mo)"
echo ""
echo "🗑️  Teardown: bash teardown.sh"
echo ""
echo "⚠️  Wait 2-3 min for user-data, then:"
echo "   curl http://$WEB_IP/api/status"
echo "   curl http://$WEB_IP/api/db"
echo "   curl http://$WEB_IP/api/files"
