# EKS Cluster Setup Guide

## Prerequisites
- AWS CLI configured with proper credentials
- Terraform installed (>= 1.0)
- kubectl installed
- Sufficient AWS permissions (VPC, EKS, EC2, IAM)

## Quick Start

### 1. Configure Variables
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 2. Initialize and Deploy
```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy (takes ~15 minutes)
terraform apply
```

### 3. Configure kubectl
```bash
# Get the command from outputs
terraform output configure_kubectl

# Or run directly
aws eks update-kubeconfig --region ap-south-1 --name my-eks-cluster
```

### 4. Verify Cluster
```bash
# Check nodes
kubectl get nodes

# Check pods
kubectl get pods -A

# Check cluster info
kubectl cluster-info
```

## What Gets Created

### VPC Resources
- VPC with CIDR 10.0.0.0/16
- 3 Public subnets (for load balancers)
- 3 Private subnets (for EKS nodes)
- 1 NAT Gateway (single NAT for cost optimization)
- Internet Gateway
- Route tables and associations

### EKS Resources
- EKS Control Plane (Kubernetes 1.28)
- Managed Node Group with 2 t3.medium instances
- IAM roles and policies for cluster and nodes
- Security groups for cluster and nodes
- OIDC provider for IRSA

### Add-ons
- CoreDNS (DNS resolution)
- kube-proxy (networking)
- VPC CNI (pod networking)

## Costs Estimate

- **EKS Control Plane**: ~$73/month ($0.10/hour)
- **EC2 Nodes (2x t3.medium)**: ~$60/month
- **NAT Gateway**: ~$32/month
- **Data Transfer**: Variable

**Total**: ~$165/month for dev environment

## Customization

### Change Node Size
```hcl
# In terraform.tfvars
node_desired_size = 3
node_min_size     = 2
node_max_size     = 5
```

### Change Instance Type
```hcl
# In terraform.tfvars
node_instance_types = ["t3.large"]
```

### Change Kubernetes Version
```hcl
# In terraform.tfvars
cluster_version = "1.29"
```

## Important Commands

### View Outputs
```bash
terraform output
terraform output cluster_endpoint
```

### Check Cluster Status
```bash
aws eks describe-cluster --name my-eks-cluster --region ap-south-1
```

### Scale Nodes
```bash
# Update desired_size in terraform.tfvars
terraform apply
```

## Cleanup

⚠️ **Important**: Delete Kubernetes resources first to avoid orphaned AWS resources (like Load Balancers)

```bash
# Delete all services with type LoadBalancer
kubectl get svc --all-namespaces
kubectl delete svc <service-name> -n <namespace>

# Delete all PVCs
kubectl get pvc --all-namespaces
kubectl delete pvc --all --all-namespaces

# Then destroy Terraform resources
terraform destroy
```

## Troubleshooting

### Nodes Not Joining Cluster
```bash
# Check node group status
aws eks describe-nodegroup \
  --cluster-name my-eks-cluster \
  --nodegroup-name <nodegroup-name> \
  --region ap-south-1
```

### Cannot Connect to Cluster
```bash
# Update kubeconfig
aws eks update-kubeconfig --region ap-south-1 --name my-eks-cluster

# Verify AWS credentials
aws sts get-caller-identity
```

### Pod Networking Issues
```bash
# Check VPC CNI pods
kubectl get pods -n kube-system | grep aws-node

# Check CoreDNS
kubectl get pods -n kube-system | grep coredns
```

## Security Best Practices

✅ Cluster endpoint is public but secured with IAM authentication
✅ Nodes are in private subnets
✅ Security groups restrict access
✅ IRSA enabled for pod-level IAM permissions
✅ Encryption at rest can be enabled

## Next Steps

1. **Install AWS Load Balancer Controller** for ingress
2. **Set up monitoring** with CloudWatch Container Insights
3. **Configure autoscaling** with Cluster Autoscaler
4. **Deploy sample application** to test cluster
5. **Set up CI/CD** pipeline for deployments

## Module Documentation

- [EKS Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)
- [VPC Module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
