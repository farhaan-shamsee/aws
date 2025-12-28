# Terraform AWS Learning - Concepts & Troubleshooting Guide

## Table of Contents
1. [AWS Credentials Setup](#aws-credentials-setup)
2. [S3 Bucket Configuration](#s3-bucket-configuration)
3. [Remote Backend Setup](#remote-backend-setup)
4. [Provider Version Management](#provider-version-management)
5. [State File Management](#state-file-management)
6. [Common Errors & Solutions](#common-errors--solutions)

---

## AWS Credentials Setup

### Secure Ways to Configure Credentials (No Export)

#### 1. AWS CLI Configuration (Recommended for Learning)
```bash
aws configure
```
- Stores credentials in `~/.aws/credentials` (encrypted)
- Terraform automatically uses these credentials
- Simple and straightforward

#### 2. Named Profiles
```ini
# ~/.aws/credentials
[dev]
aws_access_key_id = YOUR_KEY
aws_secret_access_key = YOUR_SECRET

[prod]
aws_access_key_id = YOUR_KEY
aws_secret_access_key = YOUR_SECRET
```

Reference in Terraform:
```hcl
provider "aws" {
  region  = var.aws_region
  profile = "dev"
}
```

#### 3. AWS SSO (For Organizations)
```bash
aws configure sso
aws sso login --profile your-profile
```

#### 4. AWS Vault (Most Secure)
```bash
# Install
brew install aws-vault  # macOS

# Add credentials
aws-vault add your-profile

# Use with Terraform
aws-vault exec your-profile -- terraform plan
```

#### 5. IAM Instance Profile (Best for EC2)
- Attach IAM role to EC2 instance
- No credentials needed in code
- Terraform automatically uses instance metadata

---

## S3 Bucket Configuration

### Basic S3 Bucket with Best Practices

```hcl
resource "aws_s3_bucket" "main" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy  # Allows deletion with objects

  tags = {
    Name        = var.bucket_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Enable versioning for backup/recovery
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access (security best practice)
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

### Force Destroy Configuration

**Using Variable (Recommended):**
```hcl
# variables.tf
variable "force_destroy" {
  description = "Allow deletion of bucket with objects (use with caution in production)"
  type        = bool
  default     = false
}
```

**Pass via Environment Variable:**
```bash
export TF_VAR_force_destroy=true
terraform destroy
```

**Pass via Command Line:**
```bash
terraform destroy -var="force_destroy=true"
```

**Pass via tfvars File:**
```hcl
# terraform.tfvars
force_destroy = true
```

---

## Remote Backend Setup

### Why Use Remote Backend?
- **Centralized state management** - Team collaboration
- **State locking** - Prevents concurrent modifications
- **Versioning** - State history and rollback capability
- **Security** - Encrypted state storage

### Backend Infrastructure (00.backend/)

Create S3 bucket and DynamoDB table for state management:

```hcl
# S3 bucket for state storage
resource "aws_s3_bucket" "main" {
  bucket = var.bucket_name
  # ... with versioning and encryption
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_lock" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

**Cost:** DynamoDB state locking typically costs ~$0.01-0.50/month

### Using Remote Backend in Projects

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "farhaan-terraform-backend"
    key            = "dev/ec2/terraform.tfstate"  # Unique per project
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

### State File Organization

```
S3 Bucket Structure:
terraform-state-bucket/
├── dev/
│   ├── ec2/terraform.tfstate
│   ├── s3/terraform.tfstate
│   └── vpc/terraform.tfstate
├── staging/
│   ├── ec2/terraform.tfstate
│   └── s3/terraform.tfstate
└── prod/
    ├── ec2/terraform.tfstate
    └── s3/terraform.tfstate
```

**Important:** Each project must have a unique `key` to prevent state conflicts!

### Backend Without DynamoDB (Not Recommended)

S3 doesn't support native state locking. Options:
1. **Skip locking** - Risk: concurrent runs corrupt state
2. **Use versioning only** - Recovery but no prevention
3. **Keep DynamoDB** - Recommended (minimal cost)

---

## Provider Version Management

### Version Constraint Formats

```hcl
# Range (for development)
version = "~> 6.0"  # Any 6.x version

# Exact version (for production)
version = "= 6.27.0"  # Only this specific version

# Minimum version
version = ">= 6.0.0"

# Complex constraints
version = ">= 6.0.0, < 7.0.0"
```

### Development vs Production Versioning

**Development:**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"  # Flexible, allows minor updates
    }
  }
}
```

**Production:**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.27.0"  # Exact version, no surprises
    }
  }
}
```

### Production-Safe Provider Upgrade Process

1. **Review Changelog:**
   - Check https://github.com/hashicorp/terraform-provider-aws/releases
   - Identify breaking changes
   - Note deprecations

2. **Test in Non-Prod:**
   ```bash
   # Create separate branch
   git checkout -b upgrade-aws-provider
   
   # Update version in dev environment
   # Update providers.tf
   
   terraform init -upgrade
   terraform plan  # Review ALL changes
   terraform apply
   ```

3. **Validate:**
   - Monitor for issues
   - Check logs and metrics
   - Ensure no unexpected behavior

4. **Gradual Rollout:**
   - Dev → Staging → Production
   - Wait between environments
   - Have rollback plan ready

5. **Never Skip Testing:**
   - Always run `terraform plan` after upgrade
   - Look for resource replacements
   - Check for deprecation warnings

### Lock File Management

**Why Commit `.terraform.lock.hcl`?**

1. **Consistency Across Team:**
   - Everyone uses same provider version
   - No "works on my machine" issues

2. **Reproducible CI/CD:**
   - Pipelines use exact same versions
   - No surprise updates

3. **Security:**
   - Contains provider checksums
   - Detects tampering
   - Multi-platform hashes

4. **Controlled Upgrades:**
   ```bash
   terraform init          # Uses locked version
   terraform init -upgrade # Explicitly upgrades
   ```

**Best Practice:**
```bash
# Always commit lock files
git add .terraform.lock.hcl
git commit -m "Lock AWS provider to version 6.27.0"
```

---

## State File Management

### Migrating State to Different Key

When changing the backend `key` (e.g., from `ec2/` to `dev/ec2/`):

**Option 1: Terraform Migration (Recommended):**
```bash
# 1. Update key in backend.tf
# 2. Run migration
terraform init -migrate-state

# Terraform prompts: "Copy existing state?"
# Answer: yes

# 3. Verify
terraform plan  # Should show "No changes"
```

**Option 2: Manual S3 Copy:**
```bash
# Copy state to new location
aws s3 cp \
  s3://bucket/ec2/terraform.tfstate \
  s3://bucket/dev/ec2/terraform.tfstate

# Update backend.tf
# Reinitialize
terraform init -reconfigure
terraform plan
```

**Option 3: Local Backup (Most Cautious):**
```bash
# Pull current state
terraform state pull > backup-state.json

# Update backend.tf key
terraform init -reconfigure

# Push to new location
terraform state push backup-state.json

# Verify
terraform plan
```

### State Commands

```bash
# View current state
terraform state list

# Show specific resource
terraform state show aws_s3_bucket.main

# Pull state to local file
terraform state pull > terraform.tfstate.backup

# Push state from local file
terraform state push terraform.tfstate.backup

# Remove resource from state (doesn't delete actual resource)
terraform state rm aws_s3_bucket.main

# Move resource within state
terraform state mv aws_s3_bucket.old aws_s3_bucket.new
```

---

## Common Errors & Solutions

### Error 1: BucketNotEmpty on Destroy

**Error Message:**
```
Error: deleting S3 Bucket (bucket-name): operation error S3: DeleteBucket,
api error BucketNotEmpty: The bucket you tried to delete is not empty.
You must delete all versions in the bucket.
```

**Cause:** S3 buckets must be empty before deletion. With versioning enabled, all object versions must be deleted.

**Solution:**
```hcl
resource "aws_s3_bucket" "main" {
  bucket        = var.bucket_name
  force_destroy = true  # Automatically deletes all objects on destroy
}
```

Or use variable:
```bash
terraform destroy -var="force_destroy=true"
```

### Error 2: Provider Version Lock Conflict

**Error Message:**
```
Error: Failed to query available provider packages

Could not retrieve the list of available versions for provider hashicorp/aws:
locked provider registry.terraform.io/hashicorp/aws 6.27.0 does not match
configured version constraint ~> 5.0; must use terraform init -upgrade
```

**Cause:** Lock file has version 6.x but code requires 5.x (or vice versa)

**Solution 1: Upgrade Provider Version**
```bash
terraform init -upgrade
```

**Solution 2: Update Code to Match Lock File**
```hcl
# Change version constraint in providers.tf
version = "~> 6.0"
```

**Prevention:**
- Commit `.terraform.lock.hcl` to version control
- Use consistent versions across all projects
- Review lock file before running `init -upgrade`

### Error 3: Backend Initialization Failed

**Error Message:**
```
Error: Failed to get existing workspaces: S3 bucket does not exist.
```

**Cause:** Backend S3 bucket doesn't exist yet

**Solution:**
```bash
# Deploy backend infrastructure first
cd 00.backend/
terraform init
terraform apply

# Then configure other projects to use it
cd ../01.s3/
terraform init
```

### Error 4: State Lock Timeout

**Error Message:**
```
Error: Error acquiring the state lock

Lock Info:
  ID:        abc123...
  Path:      bucket/key/terraform.tfstate
  Operation: OperationTypeApply
  Who:       user@hostname
```

**Cause:** Someone else is running Terraform, or previous run didn't release lock

**Solution 1: Wait for Lock Release**
```bash
# Wait for other operation to complete
```

**Solution 2: Force Unlock (Dangerous)**
```bash
# Only if you're sure no one else is running Terraform
terraform force-unlock abc123
```

**Prevention:** Use DynamoDB table for proper state locking

### Error 5: Duplicate Resource

**Error Message:**
```
Error: [ERR]: Error creating S3 bucket: BucketAlreadyExists:
The requested bucket name is not available
```

**Cause:** S3 bucket names are globally unique across all AWS accounts

**Solution:**
```hcl
# Use unique bucket name
variable "bucket_name" {
  default = "your-company-unique-name-dev-s3"
}
```

---

## Project Structure

```
aws/
├── 00.backend/              # Backend infrastructure
│   ├── main.tf             # S3 bucket + DynamoDB table
│   ├── providers.tf        # AWS provider config
│   ├── variables.tf        # Input variables
│   ├── outputs.tf          # Output values
│   └── terraform.tfvars    # Variable values
│
├── 01.s3/                  # S3 bucket project
│   ├── main.tf             # S3 resources
│   ├── backend.tf          # Remote state config
│   ├── providers.tf        # AWS provider
│   ├── variables.tf        # Variables
│   ├── outputs.tf          # Outputs
│   └── terraform.tfvars    # Values
│
├── 02.ec2/                 # EC2 instance project
│   ├── main.tf
│   ├── backend.tf          # Different key than 01.s3
│   ├── provider.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars
│
└── README.md               # This file
```

---

## Best Practices Summary

### Security
- ✅ Never commit credentials to version control
- ✅ Use AWS CLI or IAM roles for authentication
- ✅ Enable S3 bucket encryption
- ✅ Block public access to S3 buckets
- ✅ Enable versioning on state bucket

### State Management
- ✅ Use remote backend for team collaboration
- ✅ Enable state locking with DynamoDB
- ✅ Use unique keys for each project
- ✅ Commit `.terraform.lock.hcl` to version control
- ✅ Test state migrations in dev first

### Provider Versioning
- ✅ Use exact versions in production (`= 6.27.0`)
- ✅ Use ranges in development (`~> 6.0`)
- ✅ Review changelog before upgrading
- ✅ Test upgrades in non-prod first
- ✅ Commit lock files

### Code Organization
- ✅ Separate backend infrastructure from applications
- ✅ Use variables for reusability
- ✅ Add meaningful tags to resources
- ✅ Use descriptive outputs
- ✅ Keep projects isolated with separate state files

### Workflow
- ✅ Always run `terraform plan` before `apply`
- ✅ Review changes carefully
- ✅ Use `-var` or tfvars for different environments
- ✅ Backup state before major changes
- ✅ Use version control for all Terraform code

---

## Quick Reference Commands

```bash
# Initialize Terraform
terraform init

# Upgrade providers
terraform init -upgrade

# Migrate state to new backend
terraform init -migrate-state

# Reconfigure backend without migrating
terraform init -reconfigure

# Preview changes
terraform plan

# Preview with variable
terraform plan -var="force_destroy=true"

# Apply changes
terraform apply

# Apply with auto-approve (use carefully)
terraform apply -auto-approve

# Destroy resources
terraform destroy

# Destroy with variable
terraform destroy -var="force_destroy=true"

# Format code
terraform fmt -recursive

# Validate configuration
terraform validate

# Show current state
terraform show

# List resources in state
terraform state list

# View specific resource
terraform state show aws_s3_bucket.main

# Output values
terraform output

# Refresh state
terraform refresh
```

---

## Additional Resources

- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Backend Configuration](https://www.terraform.io/language/settings/backends/s3)
- [AWS Provider Changelog](https://github.com/hashicorp/terraform-provider-aws/releases)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)

---

**Date Created:** December 28, 2025  
**Last Updated:** December 28, 2025
