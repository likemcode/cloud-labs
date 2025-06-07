import os
import json
import logging
from datetime import datetime

from flask import Flask, request, jsonify
import psycopg2
from psycopg2.extras import RealDictCursor
import redis

app = Flask(__name__)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://labuser:labpass@localhost:5432/labdb")
REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")
CACHE_TTL = int(os.environ.get("CACHE_TTL", "300"))

# Redis connection
cache = redis.from_url(REDIS_URL, decode_responses=True)

def get_db():
    """Get a database connection."""
    conn = psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)
    conn.autocommit = False
    return conn

def init_db():
    """Initialize the database schema."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS items (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(255) NOT NULL,
                    description TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            cur.execute("""
                CREATE INDEX IF NOT EXISTS idx_items_name ON items (name)
            """)
        conn.commit()
        logger.info("Database initialized successfully")
    except Exception as e:
        conn.rollback()
        logger.error(f"Failed to initialize database: {e}")
        raise
    finally:
        conn.close()

# Initialize on startup
with app.app_context():
    try:
        init_db()
    except Exception as e:
        logger.warning(f"Could not initialize DB on startup: {e}")


@app.route("/health")
def health():
    """Health check endpoint."""
    status = {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}

    # Check Postgres
    try:
        conn = get_db()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        conn.close()
        status["postgres"] = "connected"
    except Exception as e:
        status["postgres"] = f"error: {str(e)}"
        status["status"] = "degraded"

    # Check Redis
    try:
        cache.ping()
        status["redis"] = "connected"
    except Exception as e:
        status["redis"] = f"error: {str(e)}"
        status["status"] = "degraded"

    code = 200 if status["status"] == "healthy" else 503
    return jsonify(status), code


@app.route("/api/items", methods=["GET"])
def list_items():
    """List all items, with Redis caching."""
    cache_key = "items:all"

    # Try cache first
    cached = cache.get(cache_key)
    if cached:
        logger.info("Cache hit for items list")
        return jsonify({"items": json.loads(cached), "source": "cache"})

    # Cache miss --- query database
    logger.info("Cache miss for items list")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id, name, description, created_at::text, updated_at::text FROM items ORDER BY created_at DESC")
            items = cur.fetchall()

        # Store in cache
        cache.setex(cache_key, CACHE_TTL, json.dumps(items))

        return jsonify({"items": items, "source": "database"})
    finally:
        conn.close()


@app.route("/api/items", methods=["POST"])
def create_item():
    """Create a new item."""
    data = request.get_json()

    if not data or "name" not in data:
        return jsonify({"error": "name is required"}), 400

    name = data["name"].strip()
    if not name:
        return jsonify({"error": "name cannot be empty"}), 400

    description = data.get("description", "")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO items (name, description) VALUES (%s, %s) RETURNING id, name, description, created_at::text, updated_at::text",
                (name, description)
            )
            item = cur.fetchone()
        conn.commit()

        # Invalidate list cache
        cache.delete("items:all")

        logger.info(f"Created item: {item['id']}")
        return jsonify({"item": item}), 201
    except Exception as e:
        conn.rollback()
        logger.error(f"Failed to create item: {e}")
        return jsonify({"error": "Failed to create item"}), 500
    finally:
        conn.close()


@app.route("/api/items/<int:item_id>", methods=["GET"])
def get_item(item_id):
    """Get a single item by ID, with caching."""
    cache_key = f"items:{item_id}"

    cached = cache.get(cache_key)
    if cached:
        return jsonify({"item": json.loads(cached), "source": "cache"})

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, name, description, created_at::text, updated_at::text FROM items WHERE id = %s",
                (item_id,)
            )
            item = cur.fetchone()

        if not item:
            return jsonify({"error": "Item not found"}), 404

        cache.setex(cache_key, CACHE_TTL, json.dumps(item))
        return jsonify({"item": item, "source": "database"})
    finally:
        conn.close()


@app.route("/api/items/<int:item_id>", methods=["PUT"])
def update_item(item_id):
    """Update an existing item."""
    data = request.get_json()

    if not data:
        return jsonify({"error": "Request body is required"}), 400

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Check if item exists
            cur.execute("SELECT id FROM items WHERE id = %s", (item_id,))
            if not cur.fetchone():
                return jsonify({"error": "Item not found"}), 404

            # Build update query dynamically
            fields = []
            values = []
            if "name" in data:
                fields.append("name = %s")
                values.append(data["name"].strip())
            if "description" in data:
                fields.append("description = %s")
                values.append(data["description"])

            if not fields:
                return jsonify({"error": "No fields to update"}), 400

            fields.append("updated_at = CURRENT_TIMESTAMP")
            values.append(item_id)

            cur.execute(
                f"UPDATE items SET {', '.join(fields)} WHERE id = %s RETURNING id, name, description, created_at::text, updated_at::text",
                values
            )
            item = cur.fetchone()
        conn.commit()

        # Invalidate caches
        cache.delete(f"items:{item_id}")
        cache.delete("items:all")

        return jsonify({"item": item})
    except Exception as e:
        conn.rollback()
        logger.error(f"Failed to update item {item_id}: {e}")
        return jsonify({"error": "Failed to update item"}), 500
    finally:
        conn.close()


@app.route("/api/items/<int:item_id>", methods=["DELETE"])
def delete_item(item_id):
    """Delete an item."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM items WHERE id = %s RETURNING id", (item_id,))
            deleted = cur.fetchone()

        if not deleted:
            return jsonify({"error": "Item not found"}), 404

        conn.commit()

        # Invalidate caches
        cache.delete(f"items:{item_id}")
        cache.delete("items:all")

        return jsonify({"message": f"Item {item_id} deleted"})
    except Exception as e:
        conn.rollback()
        logger.error(f"Failed to delete item {item_id}: {e}")
        return jsonify({"error": "Failed to delete item"}), 500
    finally:
        conn.close()


@app.route("/api/stats")
def stats():
    """Get basic stats about the items collection."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) as count FROM items")
            count = cur.fetchone()["count"]

            cur.execute("SELECT created_at::text FROM items ORDER BY created_at DESC LIMIT 1")
            latest = cur.fetchone()

        return jsonify({
            "total_items": count,
            "latest_created": latest["created_at"] if latest else None,
            "cache_info": {
                "ttl_seconds": CACHE_TTL,
                "redis_connected": cache.ping()
            }
        })
    finally:
        conn.close()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
