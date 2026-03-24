# Cloud Labs

My cloud infrastructure lab notebook. Each lab is a self-contained exercise I built to learn a specific concept. Includes my notes on what went wrong and what I learned.

## Why This Exists

I got tired of reading docs without building anything. Every lab here is something I actually set up, broke, debugged, and (eventually) got working. The mistakes are documented on purpose --- future me will thank past me.

## Labs

| Lab | Topic | Status |
|-----|-------|--------|
| [lab-01](./lab-01-docker-fundamentals/) | Docker Fundamentals | Done |
| [lab-02](./lab-02-terraform-aws-vpc/) | Terraform AWS VPC | Done |
| [lab-03](./lab-03-kubernetes-deployment/) | Kubernetes Deployment | Done |
| [lab-04](./lab-04-github-actions-cicd/) | GitHub Actions CI/CD | Done |
| [lab-05](./lab-05-monitoring-stack/) | Monitoring Stack | Done |
| [lab-06](./lab-06-serverless-api/) | Serverless API | Done |

## Cheatsheets

- [Docker Commands](./cheatsheets/docker-commands.md)
- [kubectl Commands](./cheatsheets/kubectl-commands.md)
- [Terraform Patterns](./cheatsheets/terraform-patterns.md)

## How I Use This

1. Pick a concept I want to understand better
2. Build something minimal but real
3. Break it on purpose, see what happens
4. Write down what I learned in the lab README and the [logbook](./LOGBOOK.md)

## Tools I'm Using

- Docker Desktop (local dev)
- Terraform v1.7+
- kubectl + minikube for local K8s
- AWS free tier (carefully)
- VS Code with Remote Containers

## Notes to Self

- Always tear down AWS resources when done. That $47 bill in August was painful.
- Test Terraform plans in a sandbox account first.
- K8s resource limits matter. My laptop fans learned that the hard way.

## Status: Active
