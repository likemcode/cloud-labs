#!/bin/bash
set -e
PROFILE="iamadmin"
REGION="us-east-1"
VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET_1_CIDR="10.0.1.0/24"
PUBLIC_SUBNET_2_CIDR="10.0.2.0/24"
PRIVATE_SUBNET_1_CIDR="10.0.3.0/24"
PRIVATE_SUBNET_2_CIDR="10.0.4.0/24"
KEY_NAME="three-tier-key"
INSTANCE_TYPE="t2.micro"
DB_INSTANCE_CLASS="db.t3.micro"
DB_NAME="demodb"
DB_USER="admin"
DB_PASS="ThreeTierTest2026!"
AMI_ID="ami-0d2614b50d35a09d7"  # Amazon Linux 2 us-east-1 (2026)

echo "============================================"
echo " THREE-TIER ARCHITECTURE DEPLOYMENT"
echo " Region: $REGION | Account: $(aws sts get-caller-identity --profile $PROFILE --query Account --output text)"
echo "============================================"

# ========== 1. CREATE KEY PAIR ==========
echo "[1/10] Creating SSH key pair..."
aws ec2 create-key-pair --profile $PROFILE --region $REGION \
  --key-name $KEY_NAME --query 'KeyMaterial' --output text > ${KEY_NAME}.pem 2>/dev/null || \
  echo "Key pair already exists, reusing."
chmod 400 ${KEY_NAME}.pem 2>/dev/null || true

# ========== 2. CREATE VPC ==========
echo "[2/10] Creating VPC..."
VPC_ID=$(aws ec2 create-vpc --profile $PROFILE --region $REGION \
  --cidr-block $VPC_CIDR --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=three-tier-vpc}]' \
  --query 'Vpc.VpcId' --output text)
echo "  VPC ID: $VPC_ID"

aws ec2 modify-vpc-attribute --profile $PROFILE --region $REGION --vpc-id $VPC_ID --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --profile $PROFILE --region $REGION --vpc-id $VPC_ID --enable-dns-hostnames '{"Value":true}'

# ========== 3. CREATE SUBNETS ==========
echo "[3/10] Creating subnets..."
PUBLIC_SUBNET_1=$(aws ec2 create-subnet --profile $PROFILE --region $REGION \
  --vpc-id $VPC_ID --cidr-block $PUBLIC_SUBNET_1_CIDR --availability-zone ${REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=three-tier-public-1}]' \
  --query 'Subnet.SubnetId' --output text)
PUBLIC_SUBNET_2=$(aws ec2 create-subnet --profile $PROFILE --region $REGION \
  --vpc-id $VPC_ID --cidr-block $PUBLIC_SUBNET_2_CIDR --availability-zone ${REGION}b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=three-tier-public-2}]' \
  --query 'Subnet.SubnetId' --output text)
PRIVATE_SUBNET_1=$(aws ec2 create-subnet --profile $PROFILE --region $REGION \
  --vpc-id $VPC_ID --cidr-block $PRIVATE_SUBNET_1_CIDR --availability-zone ${REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=three-tier-private-1}]' \
  --query 'Subnet.SubnetId' --output text)
PRIVATE_SUBNET_2=$(aws ec2 create-subnet --profile $PROFILE --region $REGION \
  --vpc-id $VPC_ID --cidr-block $PRIVATE_SUBNET_2_CIDR --availability-zone ${REGION}b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=three-tier-private-2}]' \
  --query 'Subnet.SubnetId' --output text)

echo "  Public 1: $PUBLIC_SUBNET_1 (${REGION}a)"
echo "  Public 2: $PUBLIC_SUBNET_2 (${REGION}b)"
echo "  Private 1: $PRIVATE_SUBNET_1 (${REGION}a)"
echo "  Private 2: $PRIVATE_SUBNET_2 (${REGION}b)"

# Enable auto-assign public IP for public subnets
aws ec2 modify-subnet-attribute --profile $PROFILE --region $REGION \
  --subnet-id $PUBLIC_SUBNET_1 --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --profile $PROFILE --region $REGION \
  --subnet-id $PUBLIC_SUBNET_2 --map-public-ip-on-launch

# ========== 4. INTERNET GATEWAY ==========
echo "[4/10] Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway --profile $PROFILE --region $REGION \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=three-tier-igw}]' \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --profile $PROFILE --region $REGION \
  --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
echo "  IGW: $IGW_ID"

# ========== 5. ROUTE TABLES ==========
echo "[5/10] Creating route tables..."

# Public route table
PUBLIC_RT=$(aws ec2 create-route-table --profile $PROFILE --region $REGION \
  --vpc-id $VPC_ID --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=three-tier-public-rt}]' \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --profile $PROFILE --region $REGION \
  --route-table-id $PUBLIC_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --profile $PROFILE --region $REGION \
  --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_SUBNET_1
aws ec2 associate-route-table --profile $PROFILE --region $REGION \
  --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_SUBNET_2
echo "  Public RT: $PUBLIC_RT"

# Private route table (local only - no NAT for cost saving)
PRIVATE_RT=$(aws ec2 create-route-table --profile $PROFILE --region $REGION \
  --vpc-id $VPC_ID --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=three-tier-private-rt}]' \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 associate-route-table --profile $PROFILE --region $REGION \
  --route-table-id $PRIVATE_RT --subnet-id $PRIVATE_SUBNET_1
aws ec2 associate-route-table --profile $PROFILE --region $REGION \
  --route-table-id $PRIVATE_RT --subnet-id $PRIVATE_SUBNET_2
echo "  Private RT: $PRIVATE_RT (local only, no NAT — cost optimized)"

# ========== 6. SECURITY GROUPS ==========
echo "[6/10] Creating security groups..."

# Web tier SG
SG_WEB=$(aws ec2 create-security-group --profile $PROFILE --region $REGION \
  --group-name three-tier-web-sg --description "Web tier security group" \
  --vpc-id $VPC_ID --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=three-tier-web-sg}]' \
  --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --profile $PROFILE --region $REGION \
  --group-id $SG_WEB --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --profile $PROFILE --region $REGION \
  --group-id $SG_WEB --protocol tcp --port 22 --cidr 0.0.0.0/0
echo "  Web SG: $SG_WEB (ports 80, 22 open)"

# App tier SG
SG_APP=$(aws ec2 create-security-group --profile $PROFILE --region $REGION \
  --group-name three-tier-app-sg --description "App tier security group" \
  --vpc-id $VPC_ID --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=three-tier-app-sg}]' \
  --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --profile $PROFILE --region $REGION \
  --group-id $SG_APP --protocol tcp --port 5000 --source-group $SG_WEB
aws ec2 authorize-security-group-ingress --profile $PROFILE --region $REGION \
  --group-id $SG_APP --protocol tcp --port 22 --source-group $SG_WEB
echo "  App SG: $SG_APP (port 5000 from Web SG, SSH from Web SG)"

# DB tier SG
SG_DB=$(aws ec2 create-security-group --profile $PROFILE --region $REGION \
  --group-name three-tier-db-sg --description "Database tier security group" \
  --vpc-id $VPC_ID --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=three-tier-db-sg}]' \
  --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --profile $PROFILE --region $REGION \
  --group-id $SG_DB --protocol tcp --port 3306 --source-group $SG_APP
echo "  DB SG: $SG_DB (port 3306 from App SG)"

# ========== 7. DB SUBNET GROUP ==========
echo "[7/10] Creating DB subnet group..."
aws rds create-db-subnet-group --profile $PROFILE --region $REGION \
  --db-subnet-group-name three-tier-db-subnet \
  --db-subnet-group-description "Three-tier DB subnet group" \
  --subnet-ids $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
  --tags 'Key=Name,Value=three-tier-db-subnet' 2>/dev/null || echo "  DB subnet group already exists"

# ========== 8. LAUNCH APP INSTANCE ==========
echo "[8/10] Launching App Tier instance..."

# App user-data
cat > /tmp/app-user-data.sh << 'APPEOF'
#!/bin/bash
yum update -y
yum install -y python3 python3-pip mysql
pip3 install flask pymysql

mkdir -p /home/ec2-user/app

cat > /home/ec2-user/app/app.py << 'PYEOF'
from flask import Flask, jsonify, request
import pymysql, os, socket, subprocess, datetime

app = Flask(__name__)

DB_HOST = os.environ.get('DB_HOST', 'localhost')
DB_USER = os.environ.get('DB_USER', 'admin')
DB_PASS = os.environ.get('DB_PASS', 'ThreeTierTest2026!')
DB_NAME = os.environ.get('DB_NAME', 'demodb')

@app.route('/api/status')
def status():
    return jsonify({
        'tier': 'application',
        'hostname': socket.gethostname(),
        'status': 'healthy',
        'timestamp': datetime.datetime.now().isoformat()
    })

@app.route('/api/db')
def db_check():
    try:
        conn = pymysql.connect(host=DB_HOST, user=DB_USER, password=DB_PASS, database=DB_NAME, connect_timeout=5)
        cur = conn.cursor()
        cur.execute("SELECT '✅ DB connection OK from App Tier' AS msg")
        row = cur.fetchone()
        cur.close()
        conn.close()
        return jsonify({'database': 'connected', 'message': row[0]})
    except Exception as e:
        return jsonify({'database': 'error', 'message': str(e)[:200]})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
PYEOF

echo 'DB_HOST=DB_PLACEHOLDER' > /home/ec2-user/app/.env
echo 'DB_USER=admin' >> /home/ec2-user/app/.env
echo 'DB_PASS=ThreeTierTest2026!' >> /home/ec2-user/app/.env
echo 'DB_NAME=demodb' >> /home/ec2-user/app/.env

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
systemctl start three-tier-app
APPEOF

APP_INSTANCE_ID=$(aws ec2 run-instances --profile $PROFILE --region $REGION \
  --image-id $AMI_ID --instance-type $INSTANCE_TYPE --key-name $KEY_NAME \
  --subnet-id $PUBLIC_SUBNET_1 \
  --security-group-ids $SG_APP \
  --associate-public-ip-address \
  --user-data file:///tmp/app-user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=three-tier-app}]' \
  --query 'Instances[0].InstanceId' --output text)
echo "  App Instance: $APP_INSTANCE_ID"

# Wait for instance running
echo "  Waiting for app instance to be running..."
aws ec2 wait instance-running --profile $PROFILE --region $REGION --instance-ids $APP_INSTANCE_ID
sleep 10

# Get app instance private IP
APP_PRIVATE_IP=$(aws ec2 describe-instances --profile $PROFILE --region $REGION \
  --instance-ids $APP_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
APP_PUBLIC_IP=$(aws ec2 describe-instances --profile $PROFILE --region $REGION \
  --instance-ids $APP_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "  App Private IP: $APP_PRIVATE_IP"
echo "  App Public IP: $APP_PUBLIC_IP"

# ========== 9. LAUNCH RDS ==========
echo "[9/10] Creating RDS MySQL instance (this takes 5-8 minutes)..."

aws rds create-db-instance --profile $PROFILE --region $REGION \
  --db-instance-identifier three-tier-db \
  --db-instance-class $DB_INSTANCE_CLASS \
  --engine mysql --engine-version 8.0 \
  --allocated-storage 20 --storage-type gp2 \
  --master-username $DB_USER --master-user-password $DB_PASS \
  --db-name $DB_NAME \
  --vpc-security-group-ids $SG_DB \
  --db-subnet-group-name three-tier-db-subnet \
  --no-publicly-accessible \
  --no-multi-az \
  --backup-retention-period 0 \
  --tags 'Key=Name,Value=three-tier-db' 2>/dev/null || echo "  RDS may already exist"

echo "  RDS creation initiated. Waiting for it to become available..."
aws rds wait db-instance-available --profile $PROFILE --region $REGION \
  --db-instance-identifier three-tier-db

RDS_ENDPOINT=$(aws rds describe-db-instances --profile $PROFILE --region $REGION \
  --db-instance-identifier three-tier-db \
  --query 'DBInstances[0].Endpoint.Address' --output text)
echo "  RDS Endpoint: $RDS_ENDPOINT"

# ========== Update app instance with DB host ==========
echo "  Updating app instance with DB endpoint..."
# Use SSM to update the .env file, or SSH
# For simplicity, we'll use a systemd override
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${KEY_NAME}.pem ec2-user@$APP_PUBLIC_IP \
  "sudo sed -i 's/DB_PLACEHOLDER/${RDS_ENDPOINT}/' /home/ec2-user/app/.env && sudo systemctl restart three-tier-app" 2>/dev/null || \
  echo "  WARNING: Couldn't SSH to update DB host. App will need manual update."

# ========== 10. LAUNCH WEB INSTANCE ==========
echo "[10/10] Launching Web Tier instance..."

# Web user-data with app private IP baked in
cat > /tmp/web-user-data.sh << WEBEOF
#!/bin/bash
yum update -y
yum install -y httpd

# Configure Apache as reverse proxy to app tier
cat > /etc/httpd/conf.d/reverse-proxy.conf << APACHECONF
<VirtualHost *:80>
    ServerName localhost
    
    # Serve static files from /var/www/html
    DocumentRoot /var/www/html
    
    # Proxy API calls to app tier
    ProxyPass /api/ http://${APP_PRIVATE_IP}:5000/api/
    ProxyPassReverse /api/ http://${APP_PRIVATE_IP}:5000/api/
</VirtualHost>
APACHECONF

# Ensure proxy modules are loaded (just in case)
echo 'LoadModule proxy_module modules/mod_proxy.so' >> /etc/httpd/conf/httpd.conf
echo 'LoadModule proxy_http_module modules/mod_proxy_http.so' >> /etc/httpd/conf/httpd.conf

# Create frontend
cat > /var/www/html/index.html << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Three-Tier Architecture Demo</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', system-ui, sans-serif; background: #0f172a; color: #e2e8f0; min-height: 100vh; display: flex; flex-direction: column; align-items: center; justify-content: center; }
        .container { max-width: 800px; width: 90%; }
        h1 { font-size: 2rem; text-align: center; margin-bottom: 0.5rem; background: linear-gradient(135deg, #60a5fa, #a78bfa); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        .subtitle { text-align: center; color: #94a3b8; margin-bottom: 2rem; }
        .tiers { display: grid; grid-template-columns: 1fr; gap: 1rem; }
        .tier { background: #1e293b; border-radius: 12px; padding: 1.5rem; border: 1px solid #334155; }
        .tier-header { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 1rem; }
        .tier-badge { padding: 0.25rem 0.75rem; border-radius: 20px; font-size: 0.75rem; font-weight: 600; text-transform: uppercase; }
        .badge-web { background: #1e40af33; color: #60a5fa; border: 1px solid #1e40af; }
        .badge-app { background: #16653433; color: #4ade80; border: 1px solid #166534; }
        .badge-db { background: #7e22ce33; color: #c084fc; border: 1px solid #7e22ce; }
        .tier .label { font-size: 0.85rem; color: #94a3b8; }
        .tier .value { font-weight: 600; word-break: break-all; }
        .status { display: inline-block; width: 10px; height: 10px; border-radius: 50%; margin-right: 0.5rem; }
        .status-ok { background: #4ade80; box-shadow: 0 0 8px #4ade8080; }
        .status-err { background: #f87171; box-shadow: 0 0 8px #f8717180; }
        .status-pending { background: #fbbf24; box-shadow: 0 0 8px #fbbf2480; animation: pulse 1.5s infinite; }
        @keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.4; } }
        pre { background: #0f172a; padding: 1rem; border-radius: 8px; overflow-x: auto; font-size: 0.85rem; margin-top: 0.5rem; max-height: 200px; }
        button { margin-top: 2rem; padding: 0.75rem 2rem; background: linear-gradient(135deg, #3b82f6, #8b5cf6); border: none; border-radius: 8px; color: white; font-size: 1rem; cursor: pointer; font-weight: 600; }
        button:hover { opacity: 0.9; transform: translateY(-1px); transition: all 0.2s; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🏗️ Three-Tier Architecture</h1>
        <p class="subtitle">AWS us-east-1 — Minimal Cost Test Deployment</p>
        
        <div class="tiers">
            <div class="tier" id="web-tier">
                <div class="tier-header">
                    <span class="tier-badge badge-web">Web Tier</span>
                    <span class="label">Apache Reverse Proxy — Public Subnet</span>
                </div>
                <div><span class="label">EC2:</span> <span class="value" id="web-host">Loading...</span></div>
            </div>
            
            <div class="tier" id="app-tier">
                <div class="tier-header">
                    <span class="tier-badge badge-app">App Tier</span>
                    <span class="label">Python Flask API — Port 5000</span>
                </div>
                <div><span class="status status-pending" id="app-status-dot"></span><span class="value" id="app-status">Unknown</span></div>
                <pre id="app-json">Loading...</pre>
            </div>
            
            <div class="tier" id="db-tier">
                <div class="tier-header">
                    <span class="tier-badge badge-db">DB Tier</span>
                    <span class="label">RDS MySQL 8.0 — Private Subnet</span>
                </div>
                <div><span class="status status-pending" id="db-status-dot"></span><span class="value" id="db-status">Unknown</span></div>
                <pre id="db-json">Loading...</pre>
            </div>
        </div>
        
        <button onclick="checkStatus()">🔄 Check Status</button>
        <button onclick="checkDB()">🗄️ Test Database</button>
    </div>
    
    <script>
        const BASE = window.location.origin;
        
        async function checkStatus() {
            const appDot = document.getElementById('app-status-dot');
            const appStatus = document.getElementById('app-status');
            const appJson = document.getElementById('app-json');
            
            appDot.className = 'status status-pending';
            appStatus.textContent = 'Checking...';
            
            try {
                const r = await fetch('/api/status');
                const data = await r.json();
                appDot.className = 'status status-ok';
                appStatus.textContent = 'ONLINE';
                appJson.textContent = JSON.stringify(data, null, 2);
                document.getElementById('web-host').textContent = data.hostname || 'N/A';
            } catch(e) {
                appDot.className = 'status status-err';
                appStatus.textContent = 'OFFLINE';
                appJson.textContent = 'Error: ' + e.message;
            }
        }
        
        async function checkDB() {
            const dbDot = document.getElementById('db-status-dot');
            const dbStatus = document.getElementById('db-status');
            const dbJson = document.getElementById('db-json');
            
            dbDot.className = 'status status-pending';
            dbStatus.textContent = 'Checking...';
            
            try {
                const r = await fetch('/api/db');
                const data = await r.json();
                dbDot.className = data.database === 'connected' ? 'status status-ok' : 'status status-err';
                dbStatus.textContent = data.database === 'connected' ? 'CONNECTED' : 'ERROR';
                dbJson.textContent = JSON.stringify(data, null, 2);
            } catch(e) {
                dbDot.className = 'status status-err';
                dbStatus.textContent = 'ERROR';
                dbJson.textContent = 'Error: ' + e.message;
            }
        }
        
        // Auto-check on load
        checkStatus();
    </script>
</body>
</html>
HTMLEOF

systemctl start httpd
systemctl enable httpd
WEBEOF

WEB_INSTANCE_ID=$(aws ec2 run-instances --profile $PROFILE --region $REGION \
  --image-id $AMI_ID --instance-type $INSTANCE_TYPE --key-name $KEY_NAME \
  --subnet-id $PUBLIC_SUBNET_1 \
  --security-group-ids $SG_WEB \
  --associate-public-ip-address \
  --user-data file:///tmp/web-user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=three-tier-web}]' \
  --query 'Instances[0].InstanceId' --output text)
echo "  Web Instance: $WEB_INSTANCE_ID"

echo "  Waiting for web instance to be running..."
aws ec2 wait instance-running --profile $PROFILE --region $REGION --instance-ids $WEB_INSTANCE_ID
sleep 10

WEB_PUBLIC_IP=$(aws ec2 describe-instances --profile $PROFILE --region $REGION \
  --instance-ids $WEB_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo ""
echo "============================================"
echo " ✅ DEPLOYMENT COMPLETE"
echo "============================================"
echo ""
echo "📋 SUMMARY:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "VPC:          $VPC_ID (10.0.0.0/16)"
echo "Public RT:    $PUBLIC_RT"
echo "Private RT:   $PRIVATE_RT (no NAT — cost optimized)"
echo ""
echo "🔵 WEB TIER  — t2.micro — $WEB_INSTANCE_ID"
echo "   Public IP:  $WEB_PUBLIC_IP"
echo "   SSH:        ssh -i ${KEY_NAME}.pem ec2-user@$WEB_PUBLIC_IP"
echo "   URL:        http://$WEB_PUBLIC_IP"
echo ""
echo "🟢 APP TIER  — t2.micro — $APP_INSTANCE_ID"
echo "   Private IP: $APP_PRIVATE_IP"
echo "   Public IP:  $APP_PUBLIC_IP"
echo "   Port:       5000 (only from Web SG)"
echo ""
echo "🟣 DB TIER   — db.t3.micro MySQL 8.0 — three-tier-db"
echo "   Endpoint:   $RDS_ENDPOINT"
echo "   Subnet:     Private (no public access)"
echo "   Storage:    20GB gp2"
echo ""
echo "🛡️ SECURITY GROUPS:"
echo "   Web SG: $SG_WEB → 80:world, 22:world"
echo "   App SG: $SG_APP → 5000:web-sg, 22:web-sg"
echo "   DB SG:  $SG_DB → 3306:app-sg"
echo ""
echo "💰 ESTIMATED COST (24/7):"
echo "   2x t2.micro:   ~\$0.56/day"
echo "   1x RDS t3.micro: ~\$0.41/day"
echo "   20GB gp2:      ~\$0.02/day"
echo "   TOTAL:         ~\$0.99/day (~\$30/month)"
echo ""
echo "🌐 Access the demo:"
echo "   http://$WEB_PUBLIC_IP"
echo ""
echo "⚠️  NOTE: App tier user-data may still be installing (2-3 min)."
echo "   Wait ~3 min then refresh the page."
echo "   The 'Check Status' button tests App Tier via reverse proxy."
echo "   'Test Database' button tests full 3-tier connectivity."
echo ""
echo "🗑️  To tear down: run three-tier-teardown.sh"
#!/bin/bash
set -e
PROFILE="iamadmin"
REGION="us-east-1"
AMI_ID="ami-0fa63072dba82baa6"  # Amazon Linux 2 latest
INSTANCE_TYPE="t3.micro"
DB_INSTANCE_CLASS="db.t3.micro"
KEY_NAME="three-tier-key"

# Resources already created
VPC_ID="vpc-06317d0d65dcd6ff3"
PUBLIC_SUBNET_1="subnet-052cd7ae2665192c8"
PRIVATE_SUBNET_1="subnet-04aaff7de37a1ee6f"
PRIVATE_SUBNET_2="subnet-03e25336f6c5e89d0"
SG_WEB="sg-0f66fb9045846221a"
SG_APP="sg-071fc63a983a804d5"
SG_DB="sg-0a9406eb85aa261ea"
DB_SUBNET_GROUP="three-tier-db-subnet"
DB_USER="admin"
DB_PASS="ThreeTierTest2026!"
DB_NAME="demodb"

echo "=== RESUMING 3-TIER DEPLOYMENT ==="
echo "Using existing: VPC=$VPC_ID, SGs=$SG_WEB/$SG_APP/$SG_DB"
echo ""

# ========== LAUNCH APP INSTANCE ==========
echo "[1/3] Launching App Tier instance..."

cat > /tmp/app-user-data.sh << 'APPEOF'
#!/bin/bash
yum update -y
yum install -y python3 python3-pip mariadb105
pip3 install flask pymysql

mkdir -p /home/ec2-user/app

cat > /home/ec2-user/app/app.py << 'PYEOF'
from flask import Flask, jsonify, request
import pymysql, os, socket, datetime

app = Flask(__name__)

DB_HOST = os.environ.get('DB_HOST', 'localhost')
DB_USER = os.environ.get('DB_USER', 'admin')
DB_PASS = os.environ.get('DB_PASS', 'ThreeTierTest2026!')
DB_NAME = os.environ.get('DB_NAME', 'demodb')

@app.route('/api/status')
def status():
    return jsonify({
        'tier': 'application',
        'hostname': socket.gethostname(),
        'private_ip': os.popen('hostname -I').read().strip().split()[0],
        'status': 'healthy',
        'timestamp': datetime.datetime.now().isoformat()
    })

@app.route('/api/db')
def db_check():
    try:
        conn = pymysql.connect(host=DB_HOST, user=DB_USER, password=DB_PASS, database=DB_NAME, connect_timeout=5)
        cur = conn.cursor()
        cur.execute("SELECT 'DB connection OK from App Tier' AS msg")
        row = cur.fetchone()
        cur.close()
        conn.close()
        return jsonify({'database': 'connected', 'message': row[0]})
    except Exception as e:
        return jsonify({'database': 'error', 'message': str(e)[:300]})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
PYEOF

cat > /home/ec2-user/app/.env << 'ENVEOF'
DB_HOST=DB_PLACEHOLDER
DB_USER=admin
DB_PASS=ThreeTierTest2026!
DB_NAME=demodb
ENVEOF

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
APPEOF

APP_INSTANCE_ID=$(aws ec2 run-instances --profile $PROFILE --region $REGION \
  --image-id $AMI_ID --instance-type $INSTANCE_TYPE --key-name $KEY_NAME \
  --subnet-id $PUBLIC_SUBNET_1 \
  --security-group-ids $SG_APP \
  --associate-public-ip-address \
  --user-data file:///tmp/app-user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=three-tier-app}]' \
  --query 'Instances[0].InstanceId' --output text)
echo "  App Instance: $APP_INSTANCE_ID"

echo "  Waiting for app instance running..."
aws ec2 wait instance-running --profile $PROFILE --region $REGION --instance-ids $APP_INSTANCE_ID
sleep 15  # Let SSH come up

APP_PRIVATE_IP=$(aws ec2 describe-instances --profile $PROFILE --region $REGION \
  --instance-ids $APP_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
APP_PUBLIC_IP=$(aws ec2 describe-instances --profile $PROFILE --region $REGION \
  --instance-ids $APP_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "  App Private IP: $APP_PRIVATE_IP | Public: $APP_PUBLIC_IP"

# ========== LAUNCH RDS ==========
echo "[2/3] Creating RDS MySQL (5-8 min)..."

aws rds create-db-instance --profile $PROFILE --region $REGION \
  --db-instance-identifier three-tier-db \
  --db-instance-class $DB_INSTANCE_CLASS \
  --engine mysql --engine-version 8.0 \
  --allocated-storage 20 --storage-type gp2 \
  --master-username $DB_USER --master-user-password $DB_PASS \
  --db-name $DB_NAME \
  --vpc-security-group-ids $SG_DB \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --no-publicly-accessible \
  --no-multi-az \
  --backup-retention-period 0 \
  --tags 'Key=Name,Value=three-tier-db' 2>/dev/null || echo "  RDS already exists, continuing..."

echo "  Waiting for RDS to become available (this takes several minutes)..."
aws rds wait db-instance-available --profile $PROFILE --region $REGION \
  --db-instance-identifier three-tier-db

RDS_ENDPOINT=$(aws rds describe-db-instances --profile $PROFILE --region $REGION \
  --db-instance-identifier three-tier-db \
  --query 'DBInstances[0].Endpoint.Address' --output text)
echo "  RDS Endpoint: $RDS_ENDPOINT"

# ========== LAUNCH WEB INSTANCE ==========
echo "[3/3] Launching Web Tier instance..."

# Wait for app user-data to complete then update DB env
echo "  Updating app with DB endpoint..."
for i in 1 2 3 4 5; do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i three-tier-key.pem ec2-user@$APP_PUBLIC_IP \
    "sudo sed -i 's/DB_PLACEHOLDER/${RDS_ENDPOINT}/' /home/ec2-user/app/.env && sudo systemctl start three-tier-app" 2>/dev/null; then
    echo "  App updated and started OK"
    break
  fi
  echo "  Retry $i/5: waiting for SSH..."
  sleep 15
done

cat > /tmp/web-user-data.sh << WEBEOF
#!/bin/bash
yum update -y
yum install -y httpd

# Load proxy modules
echo 'LoadModule proxy_module modules/mod_proxy.so' >> /etc/httpd/conf/httpd.conf
echo 'LoadModule proxy_http_module modules/mod_proxy_http.so' >> /etc/httpd/conf/httpd.conf

# Configure reverse proxy
cat > /etc/httpd/conf.d/reverse-proxy.conf << APACHECONF
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot /var/www/html
    ProxyPass /api/ http://${APP_PRIVATE_IP}:5000/api/
    ProxyPassReverse /api/ http://${APP_PRIVATE_IP}:5000/api/
</VirtualHost>
APACHECONF

cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Three-Tier Architecture Demo</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', system-ui, sans-serif; background: #0f172a; color: #e2e8f0; min-height: 100vh; display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 2rem; }
        .container { max-width: 800px; width: 100%; }
        h1 { font-size: 2rem; text-align: center; margin-bottom: 0.5rem; background: linear-gradient(135deg, #60a5fa, #a78bfa); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        .subtitle { text-align: center; color: #94a3b8; margin-bottom: 2rem; }
        .tiers { display: flex; flex-direction: column; gap: 1rem; }
        .tier { background: #1e293b; border-radius: 12px; padding: 1.5rem; border: 1px solid #334155; }
        .tier-header { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 1rem; }
        .badge { padding: 0.25rem 0.75rem; border-radius: 20px; font-size: 0.75rem; font-weight: 600; text-transform: uppercase; }
        .badge-web { background: #1e40af33; color: #60a5fa; border: 1px solid #1e40af; }
        .badge-app { background: #16653433; color: #4ade80; border: 1px solid #166534; }
        .badge-db { background: #7e22ce33; color: #c084fc; border: 1px solid #7e22ce; }
        .label { font-size: 0.85rem; color: #94a3b8; }
        .value { font-weight: 600; word-break: break-all; }
        .dot { display: inline-block; width: 10px; height: 10px; border-radius: 50%; margin-right: 0.5rem; }
        .dot-ok { background: #4ade80; box-shadow: 0 0 8px #4ade8080; }
        .dot-err { background: #f87171; box-shadow: 0 0 8px #f8717180; }
        .dot-wait { background: #fbbf24; box-shadow: 0 0 8px #fbbf2480; animation: pulse 1.5s infinite; }
        @keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.4; } }
        pre { background: #0f172a; padding: 1rem; border-radius: 8px; overflow-x: auto; font-size: 0.85rem; margin-top: 0.5rem; max-height: 200px; }
        button { margin: 1.5rem 0.5rem 0 0; padding: 0.75rem 2rem; background: linear-gradient(135deg, #3b82f6, #8b5cf6); border: none; border-radius: 8px; color: white; font-size: 1rem; cursor: pointer; font-weight: 600; }
        button:hover { opacity: 0.9; transform: translateY(-1px); transition: all 0.2s; }
        .arch-diagram { display: flex; align-items: center; gap: 0.5rem; margin: 1.5rem 0; font-size: 0.8rem; flex-wrap: wrap; justify-content: center; }
        .arch-box { background: #1e293b; border-radius: 8px; padding: 0.5rem 1rem; text-align: center; border: 1px solid #334155; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🏗️ Three-Tier Architecture</h1>
        <p class="subtitle">AWS us-east-1 — Minimum-Cost Test Deployment</p>
        
        <div class="arch-diagram">
            <div class="arch-box" style="border-color:#60a5fa">🌐 Web<br><small>Apache</small></div>
            <span style="color:#94a3b8;font-size:1.2rem">→</span>
            <div class="arch-box" style="border-color:#4ade80">⚙️ App<br><small>Flask :5000</small></div>
            <span style="color:#94a3b8;font-size:1.2rem">→</span>
            <div class="arch-box" style="border-color:#c084fc">🗄️ DB<br><small>RDS MySQL</small></div>
        </div>
        
        <div class="tiers">
            <div class="tier">
                <div class="tier-header">
                    <span class="badge badge-web">Web Tier</span>
                    <span class="label">Apache Reverse Proxy — Public Subnet</span>
                </div>
                <div><span class="label">Host:</span> <span class="value" id="web-host">-</span></div>
            </div>
            
            <div class="tier">
                <div class="tier-header">
                    <span class="badge badge-app">App Tier</span>
                    <span class="label">Python Flask API — Port 5000 (SG-locked)</span>
                </div>
                <div><span class="dot dot-wait" id="app-dot"></span><span class="value" id="app-status">Waiting...</span></div>
                <pre id="app-json">{}</pre>
            </div>
            
            <div class="tier">
                <div class="tier-header">
                    <span class="badge badge-db">DB Tier</span>
                    <span class="label">RDS MySQL 8.0 — Private Subnets (no public access)</span>
                </div>
                <div><span class="dot dot-wait" id="db-dot"></span><span class="value" id="db-status">Waiting...</span></div>
                <pre id="db-json">{}</pre>
            </div>
        </div>
        
        <button onclick="checkStatus()">🔄 Check App Status</button>
        <button onclick="checkDB()">🗄️ Test Database</button>
    </div>
    
    <script>
        async function checkStatus() {
            const dot = document.getElementById('app-dot');
            const st = document.getElementById('app-status');
            const json = document.getElementById('app-json');
            dot.className = 'dot dot-wait'; st.textContent = 'Checking...';
            try {
                const r = await fetch('/api/status');
                const d = await r.json();
                dot.className = 'dot dot-ok'; st.textContent = 'ONLINE';
                json.textContent = JSON.stringify(d, null, 2);
                document.getElementById('web-host').textContent = d.hostname || 'N/A';
            } catch(e) {
                dot.className = 'dot dot-err'; st.textContent = 'UNREACHABLE';
                json.textContent = 'Error: ' + e.message;
            }
        }
        
        async function checkDB() {
            const dot = document.getElementById('db-dot');
            const st = document.getElementById('db-status');
            const json = document.getElementById('db-json');
            dot.className = 'dot dot-wait'; st.textContent = 'Checking...';
            try {
                const r = await fetch('/api/db');
                const d = await r.json();
                dot.className = d.database==='connected' ? 'dot dot-ok' : 'dot dot-err';
                st.textContent = d.database==='connected' ? 'CONNECTED' : 'ERROR';
                json.textContent = JSON.stringify(d, null, 2);
            } catch(e) {
                dot.className = 'dot dot-err'; st.textContent = 'ERROR';
                json.textContent = 'Error: ' + e.message;
            }
        }
        checkStatus();
    </script>
</body>
</html>
HTMLEOF

systemctl start httpd
systemctl enable httpd
WEBEOF

WEB_INSTANCE_ID=$(aws ec2 run-instances --profile $PROFILE --region $REGION \
  --image-id $AMI_ID --instance-type $INSTANCE_TYPE --key-name $KEY_NAME \
  --subnet-id $PUBLIC_SUBNET_1 \
  --security-group-ids $SG_WEB \
  --associate-public-ip-address \
  --user-data file:///tmp/web-user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=three-tier-web}]' \
  --query 'Instances[0].InstanceId' --output text)
echo "  Web Instance: $WEB_INSTANCE_ID"

echo "  Waiting for web instance running..."
aws ec2 wait instance-running --profile $PROFILE --region $REGION --instance-ids $WEB_INSTANCE_ID
sleep 10

WEB_PUBLIC_IP=$(aws ec2 describe-instances --profile $PROFILE --region $REGION \
  --instance-ids $WEB_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo ""
echo "============================================"
echo " ✅ DEPLOYMENT COMPLETE"
echo "============================================"
echo ""
echo "🌐 WEB TIER"
echo "   Instance: $WEB_INSTANCE_ID"
echo "   URL:      http://$WEB_PUBLIC_IP"
echo "   SSH:      ssh -i three-tier-key.pem ec2-user@$WEB_PUBLIC_IP"
echo ""
echo "⚙️  APP TIER"
echo "   Instance: $APP_INSTANCE_ID"
echo "   Private:  $APP_PRIVATE_IP | Public: $APP_PUBLIC_IP"
echo ""
echo "🗄️  DB TIER"
echo "   RDS:      three-tier-db"
echo "   Endpoint: $RDS_ENDPOINT"
echo "   Port:     3306 (only from App SG)"
echo ""
echo "🛡️  SECURITY (3-tier enforced):"
echo "   Web SG ($SG_WEB) → :80 world, :22 world"
echo "   App SG ($SG_APP) → :5000 from Web SG, :22 from Web SG"
echo "   DB SG  ($SG_DB) → :3306 from App SG"
echo ""
echo "💰 ESTIMATED: ~\$0.99/day (~\$30/mo)"
echo "   (2x t2.micro + 1x RDS t3.micro + 20GB gp2)"
echo ""
echo "🔗 http://$WEB_PUBLIC_IP"
echo "   Wait 2-3 min for user-data to complete, then test."
#!/bin/bash
set -e
PROFILE="iamadmin"
REGION="us-east-1"
AMI_ID="ami-0fa63072dba82baa6"
KEY_NAME="three-tier-key"
VPC_ID="vpc-06317d0d65dcd6ff3"
PUBLIC_SUBNET_1="subnet-052cd7ae2665192c8"
PUBLIC_SUBNET_2="subnet-0c4123a43882a82c4"
SG_WEB="sg-0f66fb9045846221a"
SG_APP="sg-071fc63a983a804d5"
SG_DB="sg-0a9406eb85aa261ea"
APP1_PRIVATE_IP="10.0.1.83"
APP1_INSTANCE_ID="i-042132bef8539df70"
WEB_INSTANCE_ID="i-0252c77ff60a8d204"
WEB_PUBLIC_IP="44.195.35.77"
RDS_ENDPOINT="three-tier-db.c09uow68gduc.us-east-1.rds.amazonaws.com"

echo "============================================"
echo " UPGRADING TO HA ARCHITECTURE"
echo " Multi-AZ RDS + 2 App Instances + ALB"
echo "============================================"

# ========== 1. RDS → MULTI-AZ ==========
echo "[1/4] Enabling RDS Multi-AZ..."
aws rds modify-db-instance --profile $PROFILE --region $REGION \
  --db-instance-identifier three-tier-db --multi-az --apply-immediately
echo "  Multi-AZ modification initiated (takes ~2-3 min for failover replica)"

# ========== 2. SECOND APP INSTANCE ==========
echo "[2/4] Launching App Tier #2 (us-east-1b)..."

# Same user-data as App #1 but will get its own IP
RDS_ENDPOINT="$RDS_ENDPOINT"  # use variable

cat > /tmp/app2-user-data.sh << 'APPEOF'
#!/bin/bash
yum update -y
yum install -y python3 python3-pip mariadb105
pip3 install flask pymysql

mkdir -p /home/ec2-user/app

cat > /home/ec2-user/app/app.py << 'PYEOF'
from flask import Flask, jsonify
import pymysql, os, socket, datetime

app = Flask(__name__)

@app.route('/api/status')
def status():
    return jsonify({
        'tier': 'application',
        'hostname': socket.gethostname(),
        'private_ip': os.popen('hostname -I').read().strip().split()[0],
        'status': 'healthy',
        'timestamp': datetime.datetime.now().isoformat()
    })

@app.route('/api/db')
def db_check():
    try:
        conn = pymysql.connect(
            host=os.environ.get('DB_HOST', 'localhost'),
            user=os.environ.get('DB_USER', 'admin'),
            password=os.environ.get('DB_PASS', 'ThreeTierTest2026!'),
            database=os.environ.get('DB_NAME', 'demodb'),
            connect_timeout=5
        )
        cur = conn.cursor()
        cur.execute("SELECT 'DB connection OK from App Tier' AS msg")
        row = cur.fetchone()
        cur.close(); conn.close()
        return jsonify({'database': 'connected', 'message': row[0]})
    except Exception as e:
        return jsonify({'database': 'error', 'message': str(e)[:300]})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
PYEOF

cat > /home/ec2-user/app/.env << 'ENVEOF'
DB_HOST=three-tier-db.c09uow68gduc.us-east-1.rds.amazonaws.com
DB_USER=admin
DB_PASS=ThreeTierTest2026!
DB_NAME=demodb
ENVEOF

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
systemctl start three-tier-app
APPEOF

APP2_ID=$(aws ec2 run-instances --profile $PROFILE --region $REGION \
  --image-id $AMI_ID --instance-type t3.micro --key-name $KEY_NAME \
  --subnet-id $PUBLIC_SUBNET_2 \
  --security-group-ids $SG_APP \
  --associate-public-ip-address \
  --user-data file:///tmp/app2-user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=three-tier-app-2}]' \
  --query 'Instances[0].InstanceId' --output text)
echo "  App #2: $APP2_ID"

aws ec2 wait instance-running --profile $PROFILE --region $REGION --instance-ids $APP2_ID
sleep 10

APP2_PRIVATE_IP=$(aws ec2 describe-instances --profile $PROFILE --region $REGION \
  --instance-ids $APP2_ID --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
echo "  App #2 Private IP: $APP2_PRIVATE_IP"

# ========== 3. CREATE ALB ==========
echo "[3/4] Creating Application Load Balancer..."

# ALB Security Group
SG_ALB=$(aws ec2 create-security-group --profile $PROFILE --region $REGION \
  --group-name three-tier-alb-sg --description "ALB security group" \
  --vpc-id $VPC_ID --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=three-tier-alb-sg}]' \
  --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --profile $PROFILE --region $REGION \
  --group-id $SG_ALB --protocol tcp --port 80 --cidr 0.0.0.0/0
echo "  ALB SG: $SG_ALB"

# Target Group
TG_ARN=$(aws elbv2 create-target-group --profile $PROFILE --region $REGION \
  --name three-tier-app-tg --protocol HTTP --port 5000 --vpc-id $VPC_ID \
  --target-type instance \
  --health-check-path /api/status --health-check-interval-seconds 15 \
  --healthy-threshold-count 2 --unhealthy-threshold-count 3 \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
echo "  Target Group: $TG_ARN"

# Create ALB
ALB_ARN=$(aws elbv2 create-load-balancer --profile $PROFILE --region $REGION \
  --name three-tier-alb --subnets $PUBLIC_SUBNET_1 $PUBLIC_SUBNET_2 \
  --security-groups $SG_ALB \
  --scheme internet-facing --ip-address-type ipv4 \
  --tags 'Key=Name,Value=three-tier-alb' \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)
echo "  ALB ARN: $ALB_ARN"

# Wait for ALB provisioning
echo "  Waiting for ALB to be active..."
aws elbv2 wait load-balancer-available --profile $PROFILE --region $REGION \
  --load-balancer-arns $ALB_ARN

ALB_DNS=$(aws elbv2 describe-load-balancers --profile $PROFILE --region $REGION \
  --load-balancer-arns $ALB_ARN --query 'LoadBalancers[0].DNSName' --output text)
echo "  ALB DNS: $ALB_DNS"

# Listener: HTTP 80 → Target Group
aws elbv2 create-listener --profile $PROFILE --region $REGION \
  --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN
echo "  Listener created: HTTP:80 → App Target Group"

# Allow App SG to receive from ALB SG
aws ec2 authorize-security-group-ingress --profile $PROFILE --region $REGION \
  --group-id $SG_APP --protocol tcp --port 5000 --source-group $SG_ALB
echo "  App SG updated: port 5000 from ALB SG"

# ========== 4. REGISTER TARGETS ==========
echo "[4/4] Registering app instances with ALB..."

# Wait for app2 to be ready
sleep 20

aws elbv2 register-targets --profile $PROFILE --region $REGION \
  --target-group-arn $TG_ARN \
  --targets Id=$APP1_INSTANCE_ID Id=$APP2_ID
echo "  Registered: $APP1_INSTANCE_ID + $APP2_ID"

# ========== 5. UPDATE WEB SERVER ==========
echo "  Updating web server to proxy to ALB..."

# Update Apache to proxy to ALB instead of direct app IP
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i three-tier-key.pem ec2-user@$WEB_PUBLIC_IP \
  "sudo sed -i 's|ProxyPass /api/ http://.*:5000/api/|ProxyPass /api/ http://${ALB_DNS}:80/api/|' /etc/httpd/conf.d/reverse-proxy.conf && \
   sudo sed -i 's|ProxyPassReverse /api/ http://.*:5000/api/|ProxyPassReverse /api/ http://${ALB_DNS}:80/api/|' /etc/httpd/conf.d/reverse-proxy.conf && \
   sudo systemctl restart httpd" 2>&1

# Remove the temporary SSH rule from App SG (keep only Web SG + ALB SG access)
# Actually let's keep it for now for debugging

echo ""
echo "============================================"
echo " ✅ HA UPGRADE COMPLETE"
echo "============================================"
echo ""
echo "🔄 RDS: Multi-AZ enabled (failover replica deploying)"
echo ""
echo "⚖️  ALB: $ALB_DNS"
echo "   Listener: HTTP:80 → App Target Group (:5000)"
echo "   Targets: $APP1_INSTANCE_ID + $APP2_ID"
echo ""
echo "📊 APP TIER (2 instances):"
echo "   App #1: $APP1_INSTANCE_ID ($APP1_PRIVATE_IP) — us-east-1a"
echo "   App #2: $APP2_ID ($APP2_PRIVATE_IP) — us-east-1b"
echo ""
echo "🔗 UPDATED URL: http://$WEB_PUBLIC_IP"
echo ""
echo "🌐 ARCHITECTURE NOW:"
echo "   Web → ALB → [App#1, App#2] → RDS (Multi-AZ)"
echo ""
echo "💰 UPDATED COST:"
echo "   2x t3.micro:     ~\$0.50/day"
echo "   1x RDS Multi-AZ: ~\$0.82/day"
echo "   1x ALB:          ~\$0.54/day"
echo "   20GB gp2:        ~\$0.02/day"
echo "   TOTAL:           ~\$1.88/day (~\$57/mo)"
echo ""
echo "🧪 Test: curl http://$WEB_PUBLIC_IP/api/status"
#!/bin/bash
set -e
PROFILE="iamadmin"
REGION="us-east-1"
VPC_ID="vpc-06317d0d65dcd6ff3"
PUBLIC_SUBNET_1="subnet-052cd7ae2665192c8"
PUBLIC_SUBNET_2="subnet-0c4123a43882a82c4"
PRIVATE_SUBNET_1="subnet-04aaff7de37a1ee6f"
PRIVATE_SUBNET_2="subnet-03e25336f6c5e89d0"
PRIVATE_RT="rtb-0953444d42f949827"
SG_WEB="sg-0f66fb9045846221a"
SG_APP="sg-071fc63a983a804d5"
ALB_ARN="arn:aws:elasticloadbalancing:us-east-1:146637284277:loadbalancer/app/three-tier-alb/e0d8901e9142c20b"
TG_ARN="arn:aws:elasticloadbalancing:us-east-1:146637284277:targetgroup/three-tier-app-tg/7f537ef53dd2fbcd"
APP1_IP="34.237.222.0"
WEB_IP="44.195.35.77"
KEY_NAME="three-tier-key"
ACCOUNT_ID="146637284277"
BUCKET_NAME="three-tier-app-storage-${ACCOUNT_ID}"
ALB_DNS="three-tier-alb-1550058503.us-east-1.elb.amazonaws.com"

echo "============================================"
echo " ADDING WAF + S3 + VPC ENDPOINT + IAM"
echo "============================================"

# ========== 1. S3 BUCKET ==========
echo "[1/6] Creating S3 bucket..."
aws s3api create-bucket --profile $PROFILE --region $REGION \
  --bucket $BUCKET_NAME  2>/dev/null || \
  echo "  Bucket already exists"

aws s3api put-public-access-block --profile $PROFILE --region $REGION \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Enable versioning (safety)
aws s3api put-bucket-versioning --profile $PROFILE --region $REGION \
  --bucket $BUCKET_NAME --versioning-configuration Status=Enabled

# Enable default encryption
aws s3api put-bucket-encryption --profile $PROFILE --region $REGION \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "  Bucket: s3://$BUCKET_NAME (versioned, encrypted, private)"

# ========== 2. VPC S3 GATEWAY ENDPOINT ==========
echo "[2/6] Creating VPC S3 Gateway Endpoint..."
aws ec2 create-vpc-endpoint --profile $PROFILE --region $REGION \
  --vpc-id $VPC_ID --service-name com.amazonaws.${REGION}.s3 \
  --route-table-ids $PRIVATE_RT \
  --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=three-tier-s3-endpoint}]' \
  2>/dev/null && echo "  S3 Gateway Endpoint created" || echo "  S3 endpoint already exists"

# ========== 3. IAM ROLE FOR EC2 → S3 ==========
echo "[3/6] Creating IAM role for EC2 → S3 access..."

cat > /tmp/ec2-s3-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role --profile $PROFILE --region $REGION \
  --role-name three-tier-ec2-s3-role \
  --assume-role-policy-document file:///tmp/ec2-s3-trust-policy.json 2>/dev/null || \
  echo "  Role already exists"

aws iam put-role-policy --profile $PROFILE --region $REGION \
  --role-name three-tier-ec2-s3-role \
  --policy-name S3Access \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [\"s3:PutObject\",\"s3:GetObject\",\"s3:ListBucket\",\"s3:DeleteObject\"],
      \"Resource\": [\"arn:aws:s3:::${BUCKET_NAME}\",\"arn:aws:s3:::${BUCKET_NAME}/*\"]
    }]
  }" 2>/dev/null

# Create instance profile
aws iam create-instance-profile --profile $PROFILE --region $REGION \
  --instance-profile-name three-tier-ec2-profile 2>/dev/null || echo "  Instance profile exists"

aws iam add-role-to-instance-profile --profile $PROFILE --region $REGION \
  --instance-profile-name three-tier-ec2-profile \
  --role-name three-tier-ec2-s3-role 2>/dev/null || echo "  Role already in profile"

# Associate with both app instances
for INST_ID in i-042132bef8539df70 i-0298f6e3d96b7b150; do
  aws ec2 associate-iam-instance-profile --profile $PROFILE --region $REGION \
    --instance-id $INST_ID \
    --iam-instance-profile Name=three-tier-ec2-profile 2>/dev/null || \
    echo "  Profile already on $INST_ID"
done
echo "  IAM profile attached to both app instances"

# ========== 4. WAF ==========
echo "[4/6] Creating AWS WAF Web ACL..."

# Create WAF IP set for rate limiting exclusion (optional)
WAF_IP_SET=$(aws wafv2 create-ip-set --profile $PROFILE --region $REGION \
  --name three-tier-trusted-ips --scope REGIONAL \
  --ip-address-version IPV4 \
  --addresses 0.0.0.0/0 \
  --query 'Summary.Id' --output text 2>/dev/null || \
  aws wafv2 list-ip-sets --profile $PROFILE --region $REGION --scope REGIONAL \
    --query "IPSets[?Name=='three-tier-trusted-ips'].Id" --output text)

# Create rule group (or just inline rules in Web ACL for simplicity)
WEB_ACL_ARN=$(aws wafv2 create-web-acl --profile $PROFILE --region $REGION \
  --name three-tier-web-acl --scope REGIONAL \
  --default-action '{"Allow":{}}' \
  --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=three-tier-waf \
  --rules '[
    {
      "Name": "RateLimit",
      "Priority": 1,
      "Action": {"Block": {}},
      "Statement": {
        "RateBasedStatement": {
          "Limit": 500,
          "AggregateKeyType": "IP"
        }
      },
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "three-tier-rate-limit"
      }
    },
    {
      "Name": "SQLInjectionProtection",
      "Priority": 2,
      "OverrideAction": {"None": {}},
      "Statement": {
        "ManagedRuleGroupStatement": {
          "VendorName": "AWS",
          "Name": "AWSManagedRulesSQLiRuleSet"
        }
      },
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "three-tier-sqli"
      }
    },
    {
      "Name": "CommonRuleSet",
      "Priority": 3,
      "OverrideAction": {"None": {}},
      "Statement": {
        "ManagedRuleGroupStatement": {
          "VendorName": "AWS",
          "Name": "AWSManagedRulesCommonRuleSet"
        }
      },
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "three-tier-common"
      }
    }
  ]' \
  --query 'Summary.ARN' --output text)
echo "  Web ACL: $WEB_ACL_ARN"

# Associate WAF with ALB
aws wafv2 associate-web-acl --profile $PROFILE --region $REGION \
  --web-acl-arn $WEB_ACL_ARN \
  --resource-arn $ALB_ARN
echo "  WAF associated with ALB ✓"

# ========== 5. UPDATE APP CODE WITH S3 ENDPOINTS ==========
echo "[5/6] Updating app code with S3 upload/download..."

cat > /tmp/app-update.sh << 'APPSH'
#!/bin/bash
BUCKET="three-tier-app-stg-146637284277"
REGION="us-east-1"

# Update app.py to add S3 endpoints
cat > /home/ec2-user/app/app.py << 'PYEOF'
from flask import Flask, jsonify, request
import pymysql, os, socket, datetime, boto3, json

app = Flask(__name__)

DB_HOST = os.environ.get('DB_HOST', 'localhost')
DB_USER = os.environ.get('DB_USER', 'admin')
DB_PASS = os.environ.get('DB_PASS', 'ThreeTierTest2026!')
DB_NAME = os.environ.get('DB_NAME', 'demodb')
BUCKET = os.environ.get('BUCKET', 'three-tier-app-stg-146637284277')
REGION = os.environ.get('REGION', 'us-east-1')
s3 = boto3.client('s3', region_name=REGION)

@app.route('/api/status')
def status():
    return jsonify({
        'tier': 'application',
        'hostname': socket.gethostname(),
        'private_ip': os.popen('hostname -I').read().strip().split()[0],
        'status': 'healthy',
        's3_bucket': BUCKET,
        'timestamp': datetime.datetime.now().isoformat()
    })

@app.route('/api/db')
def db_check():
    try:
        conn = pymysql.connect(host=DB_HOST, user=DB_USER, password=DB_PASS, database=DB_NAME, connect_timeout=5)
        cur = conn.cursor()
        cur.execute("SELECT 'DB connection OK from App Tier' AS msg")
        row = cur.fetchone()
        cur.close(); conn.close()
        return jsonify({'database': 'connected', 'message': row[0]})
    except Exception as e:
        return jsonify({'database': 'error', 'message': str(e)[:300]})

@app.route('/api/files')
def list_files():
    """List files in S3 bucket"""
    try:
        resp = s3.list_objects_v2(Bucket=BUCKET, MaxKeys=100)
        files = []
        for obj in resp.get('Contents', []):
            files.append({
                'key': obj['Key'],
                'size': obj['Size'],
                'last_modified': obj['LastModified'].isoformat()
            })
        return jsonify({'files': files, 'count': len(files)})
    except Exception as e:
        return jsonify({'error': str(e)[:300]})

@app.route('/api/upload', methods=['POST'])
def upload_file():
    """Upload a file to S3"""
    try:
        if 'file' not in request.files:
            return jsonify({'error': 'No file provided'}), 400
        file = request.files['file']
        if file.filename == '':
            return jsonify({'error': 'No file selected'}), 400
        
        key = f"uploads/{datetime.datetime.now().strftime('%Y/%m/%d')}/{file.filename}"
        s3.upload_fileobj(file, BUCKET, key)
        
        # Log upload to DB
        try:
            conn = pymysql.connect(host=DB_HOST, user=DB_USER, password=DB_PASS, database=DB_NAME, connect_timeout=3)
            cur = conn.cursor()
            cur.execute(
                "INSERT INTO uploads (filename, s3_key, uploaded_by, size) VALUES (%s, %s, %s, %s)",
                (file.filename, key, request.remote_addr, 0)
            )
            conn.commit()
            cur.close(); conn.close()
        except:
            pass  # DB log is optional
        
        return jsonify({'uploaded': True, 'key': key, 'bucket': BUCKET})
    except Exception as e:
        return jsonify({'error': str(e)[:300]}), 500

@app.route('/api/download/<path:key>')
def download_file(key):
    """Generate a presigned URL for S3 download"""
    try:
        url = s3.generate_presigned_url(
            'get_object',
            Params={'Bucket': BUCKET, 'Key': key},
            ExpiresIn=3600
        )
        return jsonify({'download_url': url, 'key': key, 'expires_in': 3600})
    except Exception as e:
        return jsonify({'error': str(e)[:300]}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
PYEOF

# Update .env with bucket info
cat > /home/ec2-user/app/.env << 'ENVEOF'
DB_HOST=three-tier-db.c09uow68gduc.us-east-1.rds.amazonaws.com
DB_USER=admin
DB_PASS=ThreeTierTest2026!
DB_NAME=demodb
BUCKET=three-tier-app-stg-146637284277
REGION=us-east-1
ENVEOF

# Restart app
systemctl restart three-tier-app
echo "App restarted with S3 endpoints"
APPSH

# Push update to both app instances
for APP_IP in $APP1_IP 13.221.196.202; do
  echo "  Updating app at $APP_IP..."
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i three-tier-key.pem ec2-user@$APP_IP "sudo bash -s" < /tmp/app-update.sh 2>/dev/null; then
    echo "  ✓ Updated $APP_IP"
  else
    echo "  ⚠️  Could not reach $APP_IP (may need SG rule update)"
  fi
done

# ========== 6. ENABLE ALB ACCESS LOGS ==========
echo "[6/6] Enabling ALB access logs to S3..."

# Add bucket policy for ALB logging
ALB_ACCOUNT="127311923021"  # us-east-1 ALB account ID
aws s3api put-bucket-policy --profile $PROFILE --region $REGION \
  --bucket $BUCKET_NAME \
  --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Principal\": {\"AWS\": \"arn:aws:iam::${ALB_ACCOUNT}:root\"},
      \"Action\": \"s3:PutObject\",
      \"Resource\": \"arn:aws:s3:::${BUCKET_NAME}/alb-logs/*\"
    }]
  }"

aws elbv2 modify-load-balancer-attributes --profile $PROFILE --region $REGION \
  --load-balancer-arn $ALB_ARN \
  --attributes "Key=access_logs.s3.enabled,Value=true" \
               "Key=access_logs.s3.bucket,Value=$BUCKET_NAME" \
               "Key=access_logs.s3.prefix,Value=alb-logs"
echo "  ALB access logs → s3://$BUCKET_NAME/alb-logs/"

echo ""
echo "============================================"
echo " ✅ WAF + S3 + VPC ENDPOINT + IAM DONE"
echo "============================================"
echo ""
echo "🛡️  WAF Web ACL: $WEB_ACL_ARN"
echo "   Rules: Rate Limit (500 req/5min) + SQLi + Common Rules"
echo "   Attached to: ALB"
echo ""
echo "📦 S3: s3://$BUCKET_NAME"
echo "   ✓ Server-side encryption (AES-256)"
echo "   ✓ Versioning enabled"
echo "   ✓ Public access blocked"
echo "   ✓ ALB access logs → alb-logs/"
echo ""
echo "🔌 VPC S3 Gateway Endpoint"
echo "   ✓ Attached to private route table"
echo "   → EC2 in private subnets can reach S3 without internet"
echo ""
echo "🔑 IAM: three-tier-ec2-s3-role"
echo "   Permissions: s3:PutObject, GetObject, ListBucket, DeleteObject"
echo "   Attached to: App #1 + App #2"
echo ""
echo "📡 NEW APP ENDPOINTS:"
echo "   GET  /api/files          — List S3 files"
echo "   POST /api/upload          — Upload file to S3"
echo "   GET  /api/download/<key>  — Get presigned S3 URL"
echo ""
echo "🌐 ARCHITECTURE:"
echo "   [WAF] → [ALB] → [App#1, App#2] → [RDS Multi-AZ]"
echo "                          ↓"
echo "                     [S3 via VPC Endpoint]"
