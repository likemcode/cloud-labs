# Lab 03: Kubernetes Deployment

## Objective

Deploy a real application on Kubernetes with proper resource management, health checks, auto-scaling, and ingress. Learn the object hierarchy and how the pieces fit together.

## What I Learned

### Pods vs Deployments confused me at first

Pods vs Deployments confused me at first. A Pod is just a wrapper around one or more containers --- it's the smallest deployable unit. But you almost never create pods directly because they don't self-heal. If a pod dies, it stays dead. A Deployment manages ReplicaSets which manage Pods. When you update a deployment, it creates a new ReplicaSet, scales it up, and scales the old one down (rolling update). The naming convention makes sense once you see it: `myapp-7d9f5b4c6-x2k4m` is `deployment-replicaset-pod`.

### Resource limits are not optional

Learned this the hard way when my laptop fans went nuclear. Without resource limits, a container can consume all available CPU and memory. Kubernetes requests are what the scheduler uses to place pods (guaranteed minimum). Limits are the hard ceiling. If a container exceeds its memory limit, it gets OOMKilled. If it exceeds CPU, it gets throttled. Rule of thumb: set requests to actual usage, limits to 1.5-2x that.

### Liveness vs Readiness probes

Liveness: "Is the process alive?" If this fails, Kubernetes restarts the container. Readiness: "Can this pod serve traffic?" If this fails, the pod is removed from the Service's endpoints but not restarted. Use readiness for dependencies (database not ready yet) and liveness for deadlocks/hangs.

### Rolling updates

The `maxUnavailable` and `maxSurge` settings control how aggressive the rollout is. `maxUnavailable: 0` + `maxSurge: 1` means "always keep all old pods running, add one new pod at a time" --- safest but slowest. I use 25% for both as a reasonable default.

## Architecture

```
  Internet
      |
  [Ingress Controller]  (nginx)
      |
  [Service]  (ClusterIP)
      |
  [Deployment]  (3 replicas)
   |    |    |
  Pod  Pod  Pod
```

## Running

```bash
# Apply everything
kubectl apply -k .

# Watch the rollout
kubectl -n lab-app rollout status deployment/lab-app

# Port forward to test locally
kubectl -n lab-app port-forward svc/lab-app 8080:80

# Scale manually (or let HPA do it)
kubectl -n lab-app scale deployment/lab-app --replicas=5
```
