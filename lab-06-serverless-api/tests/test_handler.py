"""
Tests for the serverless CRUD API Lambda handlers.
Uses moto to mock DynamoDB.
"""

import json
import os
import pytest
import boto3
from moto import mock_aws


@pytest.fixture(autouse=True)
def aws_env():
    """Set up environment variables for tests."""
    os.environ["TABLE_NAME"] = "test-items"
    os.environ["AWS_DEFAULT_REGION"] = "us-east-1"
    os.environ["AWS_ACCESS_KEY_ID"] = "testing"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
    os.environ["AWS_SECURITY_TOKEN"] = "testing"
    os.environ["AWS_SESSION_TOKEN"] = "testing"
    yield


@pytest.fixture
def dynamodb_table():
    """Create a mock DynamoDB table."""
    with mock_aws():
        client = boto3.resource("dynamodb", region_name="us-east-1")
        table = client.create_table(
            TableName="test-items",
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        table.meta.client.get_waiter("table_exists").wait(TableName="test-items")
        yield table


def _api_event(method="GET", path="/items", body=None, path_params=None, query_params=None):
    """Build a mock API Gateway proxy event."""
    event = {
        "httpMethod": method,
        "path": path,
        "headers": {"Content-Type": "application/json"},
        "pathParameters": path_params,
        "queryStringParameters": query_params,
        "body": json.dumps(body) if body else None,
    }
    return event


class TestCreateItem:
    def test_create_item_success(self, dynamodb_table):
        from src.handler import create_item

        event = _api_event(method="POST", body={"name": "Test Item", "description": "A test"})
        response = create_item(event, None)

        assert response["statusCode"] == 201
        body = json.loads(response["body"])
        assert body["item"]["name"] == "Test Item"
        assert body["item"]["description"] == "A test"
        assert "id" in body["item"]
        assert "created_at" in body["item"]

    def test_create_item_missing_name(self, dynamodb_table):
        from src.handler import create_item

        event = _api_event(method="POST", body={"description": "No name"})
        response = create_item(event, None)

        assert response["statusCode"] == 400
        body = json.loads(response["body"])
        assert "error" in body

    def test_create_item_empty_name(self, dynamodb_table):
        from src.handler import create_item

        event = _api_event(method="POST", body={"name": "   "})
        response = create_item(event, None)

        assert response["statusCode"] == 400

    def test_create_item_no_body(self, dynamodb_table):
        from src.handler import create_item

        event = _api_event(method="POST", body=None)
        response = create_item(event, None)

        assert response["statusCode"] == 400


class TestGetItem:
    def test_get_item_success(self, dynamodb_table):
        from src.handler import create_item, get_item

        # Create an item first
        create_event = _api_event(method="POST", body={"name": "Findable"})
        create_response = create_item(create_event, None)
        item_id = json.loads(create_response["body"])["item"]["id"]

        # Get it
        get_event = _api_event(method="GET", path_params={"id": item_id})
        response = get_item(get_event, None)

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body["item"]["name"] == "Findable"

    def test_get_item_not_found(self, dynamodb_table):
        from src.handler import get_item

        event = _api_event(method="GET", path_params={"id": "nonexistent-id"})
        response = get_item(event, None)

        assert response["statusCode"] == 404

    def test_get_item_no_id(self, dynamodb_table):
        from src.handler import get_item

        event = _api_event(method="GET", path_params={})
        response = get_item(event, None)

        assert response["statusCode"] == 400


class TestListItems:
    def test_list_items_empty(self, dynamodb_table):
        from src.handler import list_items

        event = _api_event(method="GET")
        response = list_items(event, None)

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body["items"] == []
        assert body["count"] == 0

    def test_list_items_with_data(self, dynamodb_table):
        from src.handler import create_item, list_items

        for i in range(3):
            create_item(_api_event(method="POST", body={"name": f"Item {i}"}), None)

        event = _api_event(method="GET")
        response = list_items(event, None)

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body["count"] == 3

    def test_list_items_with_limit(self, dynamodb_table):
        from src.handler import create_item, list_items

        for i in range(5):
            create_item(_api_event(method="POST", body={"name": f"Item {i}"}), None)

        event = _api_event(method="GET", query_params={"limit": "2"})
        response = list_items(event, None)

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body["count"] == 2


class TestDeleteItem:
    def test_delete_item_success(self, dynamodb_table):
        from src.handler import create_item, delete_item

        # Create then delete
        create_response = create_item(
            _api_event(method="POST", body={"name": "Deletable"}), None
        )
        item_id = json.loads(create_response["body"])["item"]["id"]

        event = _api_event(method="DELETE", path_params={"id": item_id})
        response = delete_item(event, None)

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert "deleted" in body["message"].lower() or item_id in body["message"]

    def test_delete_item_not_found(self, dynamodb_table):
        from src.handler import delete_item

        event = _api_event(method="DELETE", path_params={"id": "nonexistent"})
        response = delete_item(event, None)

        assert response["statusCode"] == 404

    def test_delete_item_no_id(self, dynamodb_table):
        from src.handler import delete_item

        event = _api_event(method="DELETE", path_params={})
        response = delete_item(event, None)

        assert response["statusCode"] == 400
