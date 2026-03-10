# kubectl Commands I Actually Use

Grouped by what I'm trying to do, not alphabetically.

## Checking Status

```bash
# What's running?
kubectl get pods -n lab-app
kubectl get pods -A                    # all namespaces
kubectl get pods -o wide               # show node and IP

# Deployments and their status
kubectl get deployments -n lab-app
kubectl get deploy,svc,ingress -n lab-app   # multiple resources at once

# Quick overview of everything
kubectl get all -n lab-app
```

## Debugging

```bash
# Why is my pod not starting?
kubectl describe pod <pod-name> -n lab-app   # check Events section at bottom

# Container logs
kubectl logs <pod-name> -n lab-app
kubectl logs <pod-name> -n lab-app --previous   # logs from crashed container
kubectl logs -f <pod-name> -n lab-app           # follow
kubectl logs -l app=myapp -n lab-app            # all pods with label

# Exec into a pod
kubectl exec -it <pod-name> -n lab-app -- /bin/sh

# Port forward to test locally
kubectl port-forward svc/lab-app 8080:80 -n lab-app
kubectl port-forward pod/<pod-name> 5432:5432 -n lab-app

# Check resource usage
kubectl top pods -n lab-app
kubectl top nodes
```

## Deploying

```bash
# Apply manifests
kubectl apply -f deployment.yaml
kubectl apply -k .                     # kustomize
kubectl apply -f .                     # all yaml in directory

# Watch rollout progress
kubectl rollout status deployment/lab-app -n lab-app

# Rollout history
kubectl rollout history deployment/lab-app -n lab-app

# Rollback
kubectl rollout undo deployment/lab-app -n lab-app
kubectl rollout undo deployment/lab-app --to-revision=3 -n lab-app

# Quick image update (for testing, prefer editing yaml normally)
kubectl set image deployment/lab-app lab-app=myapp:v2 -n lab-app
```

## Scaling

```bash
# Manual scale
kubectl scale deployment/lab-app --replicas=5 -n lab-app

# Check HPA status
kubectl get hpa -n lab-app
kubectl describe hpa lab-app -n lab-app

# Restart all pods in a deployment (rolling)
kubectl rollout restart deployment/lab-app -n lab-app
```

## Configuration

```bash
# View configmaps
kubectl get configmaps -n lab-app
kubectl describe configmap lab-app-config -n lab-app

# View secrets (base64 encoded)
kubectl get secrets -n lab-app
kubectl get secret lab-app-secrets -n lab-app -o jsonpath='{.data.db-password}' | base64 -d

# Edit resource in place (opens editor)
kubectl edit deployment/lab-app -n lab-app
```

## Contexts and Namespaces

```bash
# Switch cluster/context
kubectl config get-contexts
kubectl config use-context minikube

# Set default namespace (so you don't type -n every time)
kubectl config set-context --current --namespace=lab-app

# Current context
kubectl config current-context
```

## Cleanup

```bash
# Delete specific resource
kubectl delete pod <pod-name> -n lab-app
kubectl delete -f deployment.yaml

# Delete everything in a namespace
kubectl delete all --all -n lab-app

# Delete namespace (deletes everything in it)
kubectl delete namespace lab-app
```
## Rollout
kubectl rollout restart deployment/app -n production
