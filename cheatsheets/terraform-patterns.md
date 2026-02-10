# Terraform Patterns I Reuse

Not a Terraform tutorial. Just patterns I've found useful and keep coming back to.

## Remote State with Locking

Always set this up first. Local state will bite you eventually.

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "project/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

# Create the S3 bucket and DynamoDB table manually first (chicken-and-egg problem)
# or use a separate bootstrap terraform config
```

## Variable Validation

Catch mistakes early instead of waiting for API errors.

```hcl
variable "environment" {
  type    = string
  default = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "cidr_block" {
  type = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "Must be a valid CIDR block."
  }
}
```

## Data Sources for Dynamic Values

Don't hardcode things that can be looked up.

```hcl
# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get available AZs (instead of hardcoding us-east-1a, us-east-1b)
data "aws_availability_zones" "available" {
  state = "available"
}

# Get latest Amazon Linux AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_subnet" "public" {
  count             = 2
  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  vpc_id            = aws_vpc.main.id
}
```

## Dynamic Blocks

When you need to create multiple similar nested blocks.

```hcl
variable "ingress_rules" {
  type = list(object({
    port        = number
    description = string
    cidr_blocks = list(string)
  }))
  default = [
    { port = 80,  description = "HTTP",  cidr_blocks = ["0.0.0.0/0"] },
    { port = 443, description = "HTTPS", cidr_blocks = ["0.0.0.0/0"] },
    { port = 22,  description = "SSH",   cidr_blocks = ["10.0.0.0/8"] },
  ]
}

resource "aws_security_group" "web" {
  name_prefix = "web-"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ingress.value.cidr_blocks
      description = ingress.value.description
    }
  }
}
```

## Modules for Reuse

Keep modules simple. One module = one logical thing.

```hcl
# modules/vpc/main.tf
module "vpc" {
  source = "./modules/vpc"

  environment = var.environment
  vpc_cidr    = "10.0.0.0/16"
  az_count    = 2
}

# Use outputs from the module
resource "aws_instance" "app" {
  subnet_id = module.vpc.private_subnet_ids[0]
}
```

## Workspaces

Same config, different state files. Good for dev/staging/prod with small differences.

```bash
terraform workspace new dev
terraform workspace new prod
terraform workspace select dev
terraform workspace list
```

```hcl
# Use workspace name in config
locals {
  env = terraform.workspace

  instance_type = {
    dev  = "t3.micro"
    prod = "t3.large"
  }
}

resource "aws_instance" "app" {
  instance_type = local.instance_type[local.env]
}
```

## Tagging Pattern

Consistent tags everywhere. Use default_tags in the provider.

```hcl
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "my-project"
      Environment = var.environment
      ManagedBy   = "terraform"
      Team        = "platform"
    }
  }
}

# These tags are automatically applied to all resources.
# Add resource-specific tags on top:
resource "aws_instance" "app" {
  tags = {
    Name = "app-server"    # merged with default_tags
  }
}
```

## Output Formatting

Make outputs useful for other configs or scripts.

```hcl
output "summary" {
  description = "Summary of created resources"
  value = {
    vpc_id      = aws_vpc.main.id
    subnet_ids  = aws_subnet.public[*].id
    endpoint    = "https://${aws_lb.main.dns_name}"
  }
}

# Sensitive outputs (won't show in terminal)
output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
```

## Lifecycle Rules

Prevent accidental destruction of important resources.

```hcl
resource "aws_db_instance" "main" {
  # ...

  lifecycle {
    prevent_destroy = true          # terraform destroy will fail
    create_before_destroy = true    # create new before deleting old
    ignore_changes = [password]     # don't detect drift on password
  }
}
```
## Workspaces
terraform workspace new staging
