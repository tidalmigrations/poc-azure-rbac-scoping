# Azure RBAC Scope Reduction - POC

This project demonstrates how to reduce Azure RBAC permissions for Terraform deployments by analyzing actual usage patterns and generating minimal custom roles.

## Overview

The goal is to move from broad permissions (like Contributor) to minimal, scoped permissions by:

1. Deploying infrastructure with broad permissions while logging all activities
2. Analyzing the logs to identify actually used permissions
3. Generating a custom RBAC role with only the required permissions
4. Validating the minimal permissions work for the same deployment

## Project Structure

```
azure-terraform-policy-generator/
├── terraform/
│   ├── demo-app/          # Demo application infrastructure
│   ├── logging-setup/     # Log Analytics and monitoring setup
│   └── modules/           # Reusable Terraform modules
├── scripts/               # Automation scripts for analysis and deployment
├── policies/              # Generated RBAC policies and roles
├── docs/                  # Additional documentation
├── plans/                 # Implementation plans and design docs
└── README.md
```

## Demo Application

The POC includes a cost-optimized demo application (~$30/month) featuring:

- **Linux Web App** with Node.js runtime
- **PostgreSQL Flexible Server** (cost-effective database)
- **Storage Account** with container
- **Key Vault** for secrets management
- **Application Insights** for monitoring

This combination generates diverse Azure API calls across multiple resource providers for comprehensive permission analysis.

## Prerequisites

- Azure CLI installed and configured
- Terraform >= 1.0
- PowerShell or Bash
- Azure subscription with appropriate permissions to create service principals

## Quick Start

### 1. Azure Setup

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Run automated setup
./scripts/azure-setup.sh
```

### 2. Configure Terraform Backend

```bash
# Create storage account for Terraform state
./scripts/setup-backend.sh
```

### 3. Deploy Demo Application

```bash
# Source environment variables
source .env.terraform
source .env

# Deploy infrastructure
cd terraform/demo-app
terraform init
terraform plan
terraform apply
```

## Security Benefits

- **Principle of Least Privilege**: Only grant permissions actually needed
- **Reduced Blast Radius**: Limit potential damage from compromised credentials
- **Compliance**: Meet security frameworks requiring minimal permissions
- **Auditability**: Clear documentation of why each permission is needed
