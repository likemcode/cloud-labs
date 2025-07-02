# Lab 02: Terraform AWS VPC

## Objective

Build a production-style VPC from scratch with public and private subnets, NAT gateway, and proper routing. Understand how AWS networking actually works instead of relying on the default VPC.

## Architecture

```
                        +-------------------+
                        |    Internet       |
                        +--------+----------+
                                 |
                        +--------+----------+
                        |  Internet Gateway  |
                        +--------+----------+
                                 |
         +-----------------------+-----------------------+
         |                                               |
+--------+----------+                        +-----------+---------+
|  Public Subnet    |                        |  Public Subnet      |
|  10.0.1.0/24      |                        |  10.0.2.0/24        |
|  us-east-1a       |                        |  us-east-1b         |
|                   |                        |                     |
|  +-------------+  |                        |                     |
|  | NAT Gateway |  |                        |                     |
|  +------+------+  |                        |                     |
+---------+---------+                        +---------------------+
          |
+---------+---------+                        +---------------------+
|  Private Subnet   |                        |  Private Subnet     |
|  10.0.10.0/24     |                        |  10.0.20.0/24       |
|  us-east-1a       |                        |  us-east-1b         |
|                   |                        |                     |
|  (App servers,    |                        |  (App servers,      |
|   databases)      |                        |   databases)        |
+-------------------+                        +---------------------+
```

## What I Learned

### NAT Gateway placement
The NAT gateway goes in a PUBLIC subnet, not a private one. This seems obvious in retrospect but I spent 2 hours debugging why instances in my private subnet couldn't reach the internet. The private subnet's route table points 0.0.0.0/0 at the NAT gateway, and the NAT gateway itself routes through the internet gateway via the public subnet's route table.

### Route table associations
Each subnet needs to be explicitly associated with a route table. If you don't associate it, it uses the VPC's main route table (which is private by default). This is actually a good security default.

### AZ distribution
Spreading subnets across AZs is critical for high availability. If us-east-1a goes down, resources in us-east-1b keep running. Terraform's data source for AZs makes this dynamic.

## Estimated Cost

| Resource | Cost |
|----------|------|
| NAT Gateway | ~$0.045/hr (~$32/month) |
| Elastic IP | Free (when attached) |
| VPC, subnets, route tables | Free |
| Data processing (NAT) | $0.045/GB |

**GOTCHA**: The NAT gateway costs money even when idle. Always `terraform destroy` when you're done experimenting. I learned this the hard way --- $47 on a bill because I forgot to tear it down over a weekend. Set a billing alarm.

## Running

```bash
make init     # Initialize Terraform
make plan     # Preview changes
make apply    # Create infrastructure
make destroy  # Tear it all down (DO THIS WHEN DONE)
```
