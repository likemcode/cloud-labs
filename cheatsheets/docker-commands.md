# Docker Commands I Actually Use

My personal reference. Not comprehensive --- just the stuff I keep looking up.

## Building

```bash
# Build with tag
docker build -t myapp:latest .

# Build with no cache (when things are weird)
docker build --no-cache -t myapp:latest .

# Multi-platform build
docker buildx build --platform linux/amd64,linux/arm64 -t myapp:latest .

# Build from specific Dockerfile
docker build -f Dockerfile.prod -t myapp:prod .
```

## Running

```bash
# Run interactive (good for debugging)
docker run -it --rm myapp:latest /bin/sh

# Run detached with port mapping and env vars
docker run -d -p 8080:5000 -e DATABASE_URL=postgres://... --name myapp myapp:latest

# Run with volume mount (local dev)
docker run -d -v $(pwd)/app:/app -p 5000:5000 myapp:latest

# Run with memory and CPU limits
docker run -d --memory=512m --cpus=1.0 myapp:latest
```

## Debugging

```bash
# Exec into running container
docker exec -it myapp /bin/sh

# View logs (follow + timestamps)
docker logs -f --tail 100 -t myapp

# Inspect container details (env vars, mounts, network)
docker inspect myapp

# See what's eating resources
docker stats

# Check why a container exited
docker inspect --format='{{.State.ExitCode}}' myapp
docker logs myapp 2>&1 | tail -20
```

## Networking

```bash
# List networks
docker network ls

# Create a custom bridge network (containers can resolve each other by name)
docker network create mynet

# Run container on specific network
docker run -d --network mynet --name api myapp:latest

# Connect running container to network
docker network connect mynet myapp

# Inspect network (see which containers are on it)
docker network inspect mynet
```

## Volumes

```bash
# Create named volume
docker volume create pgdata

# Run with named volume
docker run -d -v pgdata:/var/lib/postgresql/data postgres:16

# List volumes
docker volume ls

# Inspect volume (find where data lives on host)
docker volume inspect pgdata

# Remove unused volumes
docker volume prune
```

## Compose

```bash
# Start everything (detached)
docker compose up -d

# Start with rebuild
docker compose up -d --build

# View logs for specific service
docker compose logs -f app

# Run one-off command in service
docker compose exec app python manage.py migrate

# Scale a service
docker compose up -d --scale worker=3

# Stop everything and remove volumes
docker compose down -v
```

## Cleanup

```bash
# Remove stopped containers
docker container prune

# Remove unused images
docker image prune

# Remove everything unused (nuclear option)
docker system prune -a --volumes

# See disk usage
docker system df
```
