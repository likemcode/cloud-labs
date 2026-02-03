# Lab Logbook

Dated notes on what I built, what broke, and what I learned.

---

## Jun 8, 2025 --- Docker networking finally clicked

Bridge vs host vs overlay --- I'd read about these a dozen times but never really got it until I actually tried to get two containers to talk to each other. Bridge is the default, containers get their own IP on an internal network. Host shares the host's network stack (no port mapping needed, but also no isolation). Overlay is for swarm/multi-host. The thing that tripped me up: containers on the default bridge can't resolve each other by name. You need a custom bridge network for DNS resolution. Spent 45 minutes debugging "connection refused" before figuring that out.

## Jun 15, 2025 --- Multi-stage Docker builds

Got my Flask app image down from 1.2GB to 89MB using multi-stage builds. The trick is separating the build dependencies from the runtime. First stage installs gcc and builds wheels, second stage just copies the wheels and installs them. Also learned that ordering your COPY commands matters for layer caching --- put requirements.txt before the app code so pip install gets cached when you only change application code.

## Jun 29, 2025 --- Docker Compose health checks

Added health checks to my compose file. Postgres was starting but not ready to accept connections, and the Flask app would crash on startup trying to connect. The `depends_on` condition `service_healthy` combined with a pg_isready health check fixed it. Redis was easier --- just `redis-cli ping`. Lesson: "container started" != "service ready".

## Jul 12, 2025 --- First Terraform VPC

Built my first VPC from scratch instead of using the default. Two public subnets, two private subnets across AZs. The internet gateway was straightforward but I forgot that private subnets need a NAT gateway to reach the internet. Spent 2 hours wondering why my EC2 instance in the private subnet couldn't pull packages. The NAT gateway goes in the public subnet and the private subnet's route table points 0.0.0.0/0 at it. Also NAT gateways cost money even when idle --- need to remember to destroy.

## Jul 20, 2025 --- Terraform state locking bit me hard today

Lost 2 hours to a state lock issue. Had two terminals open, both tried to run terraform apply. One failed with a lock error, but the lock didn't release cleanly. Had to manually remove it with `terraform force-unlock`. Lessons: (1) use DynamoDB for state locking from the start, (2) never run concurrent applies, (3) the lock ID is in the error message, read it carefully. Also moved my state to S3 backend with locking. Should have done this on day one.

## Aug 3, 2025 --- Pods vs Deployments vs ReplicaSets

Finally got the K8s object hierarchy straight. A Pod is the smallest unit (one or more containers). A ReplicaSet ensures N copies of a pod are running. A Deployment manages ReplicaSets and handles rolling updates. You almost never create Pods or ReplicaSets directly --- just Deployments. The confusing part was that `kubectl get pods` shows pods created by a deployment, but they have generated names like `myapp-7d9f5b4c6-x2k4m`. The deployment owns the replicaset which owns the pods.

## Aug 17, 2025 --- Kubernetes resource limits matter

My laptop almost caught fire. Deployed 3 replicas with no resource limits and the containers ate all available memory. Minikube was configured with 4GB and the app plus all the sidecar stuff consumed it all. OOMKilled everywhere. Now I always set requests and limits. Requests = what the scheduler guarantees. Limits = hard ceiling. Set requests to what you actually need, limits to maybe 1.5x that. Also learned about LimitRanges to set defaults per namespace.

## Sep 5, 2025 --- CI/CD with GitHub Actions

Built a real pipeline, not just a "hello world" action. Lint with flake8, test with pytest, build Docker image, push to GHCR. The tricky part was getting Docker layer caching working in Actions --- used `docker/build-push-action` with `cache-from` and `cache-to` using GitHub Actions cache backend. Build time went from 4 minutes to 45 seconds on cache hits. Also learned about `concurrency` groups to cancel outdated workflow runs.

## Sep 22, 2025 --- Environment-based deployments

Added a deploy workflow that targets different K8s clusters based on environment. Uses GitHub environment protection rules --- prod requires manual approval. The workflow calls a reusable workflow with the environment name as input. Spent a while figuring out that secrets are scoped to environments, not just the repo. Had to add my kubeconfig to each environment's secrets separately.

## Oct 10, 2025 --- Prometheus makes everything visible

Set up Prometheus + Grafana + Alertmanager. The "aha moment" was seeing actual request latency percentiles for my Flask app. I thought my API was fast but p99 was 2.3 seconds because of a bad database query. Without metrics I never would have noticed --- the average was fine, it was just the tail that was awful. Prometheus scrape configs are fiddly but powerful. PromQL took some getting used to --- `rate()` vs `increase()` tripped me up.

## Oct 28, 2025 --- Alert fatigue is real

Configured alerts and immediately got spammed. CPU > 50%? That fires every 5 minutes on my laptop. Had to tune thresholds and add `for` durations so alerts only fire if the condition persists. Also learned about alert grouping in Alertmanager --- related alerts get batched into one notification. The routing tree concept took a while but makes sense: match labels to route to different receivers (Slack channel for warnings, PagerDuty for critical).

## Nov 15, 2025 --- Serverless first impressions

Built a CRUD API with API Gateway + Lambda + DynamoDB. Cold starts are real --- first request after idle takes 1-2 seconds. But the pricing model is wild for low-traffic apps: basically free under 1M requests/month. SAM CLI made local testing much better than I expected. The event format from API Gateway is verbose but predictable. Main gotcha: Lambda's 15-minute timeout and 10GB memory limit --- not suitable for long-running tasks.

## Dec 7, 2025 --- Cheatsheets for sanity

Started writing personal cheatsheets for commands I keep looking up. Not trying to be comprehensive --- just the stuff I actually use. Realized I google "docker exec into container" at least once a week. Also collected Terraform patterns I reuse: remote state setup, variable validation, output formatting. Having these in the repo means I can grep instead of googling.

## Jan 18, 2026 --- Refactoring the labs

Went back through all labs and added Makefiles everywhere. So much nicer than remembering long docker/terraform/kubectl commands. Also fixed some issues: the compose healthcheck interval was too aggressive (every 5s was unnecessary, changed to 30s), and the Terraform outputs were missing the NAT gateway EIP. Small stuff but it adds up.

## Feb 22, 2026 --- Applying lessons at work

Used what I learned in lab-02 to set up a VPC for a work project. The patterns from the lab translated almost directly. Added a few things I learned on the job: VPC flow logs, more granular security groups, tags for cost allocation. Updated the lab to include these improvements. Also updated the K8s deployment to use pod disruption budgets after a rough prod deploy at work.

## Mar 15, 2026 --- Revisiting monitoring

Came back to lab-05 and improved the Grafana dashboard. Added request rate, error rate, and duration panels (RED method). Also added a panel for container resource usage. The dashboard JSON is huge but it's nice to have it version-controlled. Learned that Grafana provisioning from files is way better than clicking around in the UI --- reproducible and diff-able.

## Apr 5, 2026 --- Ten months in

Looking back at my early Docker lab and cringing slightly. The code works but I'd structure it differently now. That's probably a good sign. Biggest takeaways so far: (1) always version control your infra, (2) monitoring is not optional, (3) break things on purpose to understand failure modes, (4) the gap between "I read about it" and "I built it" is enormous. Planning to add a lab on service mesh next.

## Jan 6, 2026
Revisited the Docker lab after using multi-stage builds in production. Added notes about cache invalidation.

## Feb 3, 2026
Finally understood Terraform workspaces properly. They're not what I thought — they're more like branches for state.
