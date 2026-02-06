"""
Lambda handlers for the serverless CRUD API.
Each function handles one API Gateway route and interacts with DynamoDB.
"""

import json
import logging
import os
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

# Setup
logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

TABLE_NAME = os.environ.get("TABLE_NAME", "dev-items")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)


def _response(status_code, body):
    """Build a standard API Gateway proxy response."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
        },
        "body": json.dumps(body, default=str),
    }


def _parse_body(event):
    """Parse and validate the request body."""
    body = event.get("body")
    if not body:
        return None, "Request body is required"

    try:
        if isinstance(body, str):
            data = json.loads(body)
        else:
            data = body
    except (json.JSONDecodeError, TypeError):
        return None, "Invalid JSON in request body"

    return data, None


def create_item(event, context):
    """
    Create a new item in DynamoDB.
    Expects JSON body with 'name' (required) and 'description' (optional).
    """
    logger.info("Creating new item")

    data, error = _parse_body(event)
    if error:
        return _response(400, {"error": error})

    # Validate required fields
    name = data.get("name", "").strip() if isinstance(data.get("name"), str) else ""
    if not name:
        return _response(400, {"error": "name is required and cannot be empty"})

    description = data.get("description", "")
    if not isinstance(description, str):
        return _response(400, {"error": "description must be a string"})

    now = datetime.now(timezone.utc).isoformat()
    item = {
        "id": str(uuid.uuid4()),
        "name": name,
        "description": description,
        "created_at": now,
        "updated_at": now,
    }

    try:
        table.put_item(Item=item)
        logger.info(f"Created item: {item['id']}")
        return _response(201, {"item": item})
    except ClientError as e:
        logger.error(f"DynamoDB error: {e.response['Error']['Message']}")
        return _response(500, {"error": "Failed to create item"})


def get_item(event, context):
    """
    Get a single item by ID from DynamoDB.
    ID is passed as a path parameter.
    """
    item_id = event.get("pathParameters", {}).get("id")
    if not item_id:
        return _response(400, {"error": "Item ID is required"})

    logger.info(f"Getting item: {item_id}")

    try:
        result = table.get_item(Key={"id": item_id})
    except ClientError as e:
        logger.error(f"DynamoDB error: {e.response['Error']['Message']}")
        return _response(500, {"error": "Failed to retrieve item"})

    item = result.get("Item")
    if not item:
        return _response(404, {"error": f"Item {item_id} not found"})

    return _response(200, {"item": item})


def list_items(event, context):
    """
    List all items from DynamoDB.
    Supports optional 'limit' query parameter (default 50, max 100).
    """
    logger.info("Listing items")

    # Parse query parameters
    params = event.get("queryStringParameters") or {}
    try:
        limit = min(int(params.get("limit", 50)), 100)
    except (ValueError, TypeError):
        limit = 50

    try:
        scan_kwargs = {"Limit": limit}

        # Support pagination with exclusive_start_key
        last_key = params.get("last_key")
        if last_key:
            scan_kwargs["ExclusiveStartKey"] = {"id": last_key}

        result = table.scan(**scan_kwargs)
        items = result.get("Items", [])

        response_body = {
            "items": items,
            "count": len(items),
        }

        # Include pagination token if there are more results
        if "LastEvaluatedKey" in result:
            response_body["last_key"] = result["LastEvaluatedKey"]["id"]

        return _response(200, response_body)

    except ClientError as e:
        logger.error(f"DynamoDB error: {e.response['Error']['Message']}")
        return _response(500, {"error": "Failed to list items"})


def delete_item(event, context):
    """
    Delete an item by ID from DynamoDB.
    Returns the deleted item or 404 if not found.
    """
    item_id = event.get("pathParameters", {}).get("id")
    if not item_id:
        return _response(400, {"error": "Item ID is required"})

    logger.info(f"Deleting item: {item_id}")

    try:
        # Use ConditionExpression to ensure item exists
        result = table.delete_item(
            Key={"id": item_id},
            ConditionExpression="attribute_exists(id)",
            ReturnValues="ALL_OLD",
        )
        deleted_item = result.get("Attributes")
        logger.info(f"Deleted item: {item_id}")
        return _response(200, {"message": f"Item {item_id} deleted", "item": deleted_item})

    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return _response(404, {"error": f"Item {item_id} not found"})
        logger.error(f"DynamoDB error: {e.response['Error']['Message']}")
        return _response(500, {"error": "Failed to delete item"})
# Updated
