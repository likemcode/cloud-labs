# Lab 06: Serverless API

## Objective

Serverless vs containers: when to use which. This lab builds a CRUD API using AWS SAM (Serverless Application Model) with API Gateway, Lambda, and DynamoDB. The goal is to understand the serverless programming model and when it makes sense vs. running containers.

## What I Learned

### When serverless makes sense

- Low/unpredictable traffic (pay per request, not per hour)
- Simple request/response APIs
- Event-driven processing (S3 uploads, SQS messages)
- When you don't want to manage infrastructure at all

### When containers are better

- Consistent high traffic (Lambda costs add up fast at scale)
- Long-running processes (Lambda has a 15-minute timeout)
- Complex applications with many dependencies
- When you need WebSockets or persistent connections
- When cold start latency matters (1-2 seconds on first request)

### Cold starts are real

First request after idle: 1-2 seconds. Subsequent requests: 5-50ms. Provisioned concurrency fixes this but costs money. For most APIs, cold starts are acceptable. For real-time systems, they're not.

### SAM CLI is great for local testing

`sam local invoke` and `sam local start-api` let you test Lambda functions locally with Docker. The event format from API Gateway is verbose but predictable --- always check `event['body']` and `event['pathParameters']`.

## Architecture

```
  Client
    |
    v
[API Gateway]
    |
    +-- GET    /items     --> list_items()
    +-- POST   /items     --> create_item()
    +-- GET    /items/{id} --> get_item()
    +-- DELETE /items/{id} --> delete_item()
    |
    v
[DynamoDB Table: Items]
```

## Running

```bash
# Local testing
sam build
sam local start-api

# Deploy
sam deploy --guided

# Run tests
pytest tests/ -v

# Tear down
sam delete
```
