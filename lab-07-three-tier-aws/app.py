from flask import Flask, jsonify, request
import pymysql, os, socket, datetime, boto3

app = Flask(__name__)
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_USER = os.environ.get("DB_USER", "admin")
DB_PASS = os.environ.get("DB_PASS", "ThreeTierTest2026!")
DB_NAME = os.environ.get("DB_NAME", "demodb")
BUCKET = os.environ.get("BUCKET", "three-tier-app-storage-146637284277")
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
