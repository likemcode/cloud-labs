# Lab 01: Docker Fundamentals

## Objective

Build a containerized Python Flask API with Redis caching and Postgres storage. Learn Docker networking, multi-stage builds, health checks, and Compose orchestration.

## Architecture

```
                 +-----------+
  HTTP :5000 --> |  Flask API |
                 +-----+-----+
                       |
              +--------+--------+
              |                 |
        +-----+-----+    +-----+-----+
        |   Redis    |    | Postgres  |
        |  :6379     |    |  :5432    |
        +------------+    +-----------+
```

## What I Learned

### Multi-stage builds are a game-changer
My initial image was 1.2GB because it included gcc, python-dev, and all build dependencies. The multi-stage build separates the "build wheels" step from the "run the app" step. Final image: 89MB. The key insight is that you can COPY artifacts from an earlier stage.

### Docker networking DNS
Containers on the default bridge network can't resolve each other by name. You need a custom network. In Compose, services automatically get DNS names matching their service name, but only on custom networks (which Compose creates by default, so it usually just works).

### Health checks prevent startup race conditions
Without health checks, `depends_on` only waits for the container to start, not for the service inside to be ready. Postgres takes a few seconds to initialize, and the Flask app would crash trying to connect. Adding `pg_isready` as a health check and using `depends_on: condition: service_healthy` fixed this.

### Layer caching order matters
Put `COPY requirements.txt` and `RUN pip install` before `COPY . .` so that changing application code doesn't invalidate the pip install cache. This dropped rebuild times from 2 minutes to 5 seconds when only changing Python code.

## Gotchas

1. **Postgres data loss**: Forgot to add a volume the first time. Restarted containers, all data gone. Always use named volumes for databases.
2. **Port conflicts**: Had another Postgres running on my host on port 5432. Mapped the container to 5433 instead.
3. **Redis connection string**: Used `localhost` instead of the service name `redis`. Containers have their own network namespace --- `localhost` is the container itself.
4. **Build context size**: Had a `__pycache__` directory and `.git` in the build context. Added `.dockerignore` (not included here, but should have been from the start).

## Running

```bash
make build    # Build the Docker image
make run      # Start all services
make test     # Run a quick smoke test
make logs     # Tail container logs
make clean    # Stop and remove everything
```

## Cost

$0 --- all local development with Docker Desktop.
# Lab improvements
