# Azure RBAC Scope Reduction - POC

This project demonstrates how to reduce Azure RBAC permissions for Terraform deployments by analyzing actual usage patterns and generating minimal custom roles.

- [Azure RBAC Scope Reduction - POC](#azure-rbac-scope-reduction---poc)
  - [Overview](#overview)
  - [Project Structure](#project-structure)
  - [Demo Application](#demo-application)
  - [Prerequisites](#prerequisites)
  - [Quick Start](#quick-start)
    - [1. Azure Setup](#1-azure-setup)
    - [2. Configure Terraform Backend](#2-configure-terraform-backend)
    - [3. Deploy Demo Application](#3-deploy-demo-application)
  - [Logging Setup](#logging-setup)
    - [Deploy Logging Infrastructure](#deploy-logging-infrastructure)
    - [Analyze Permissions](#analyze-permissions)
    - [Available Analysis Queries](#available-analysis-queries)
  - [Security Benefits](#security-benefits)

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

## Logging Setup

Before analyzing permissions, establish comprehensive activity logging to capture all Azure operations:

### Deploy Logging Infrastructure

```bash
# Install required Azure CLI extensions
./scripts/install-az-extensions.sh

# Deploy Log Analytics workspace and diagnostic settings
./scripts/deploy-logging.sh

# Validate the setup
./scripts/validate-logging.sh
```

### Analyze Permissions

After deploying your demo application, wait 5-10 minutes for logs to populate, then analyze:

```bash
# Query permissions used by your service principal
./scripts/query-logs.sh -s YOUR_SERVICE_PRINCIPAL_ID

# Use custom queries for specific analysis
./scripts/query-logs.sh -q terraform-specific.kql -s YOUR_SERVICE_PRINCIPAL_ID

# Export results for further analysis
./scripts/query-logs.sh -s YOUR_SERVICE_PRINCIPAL_ID -o json -f results.json
```

### Available Analysis Queries

- **`permission-analysis.kql`** - General permission usage patterns
- **`terraform-specific.kql`** - Terraform deployment-specific operations

**Cost**: Logging infrastructure costs ~$3-6/month (Log Analytics + Storage)

## Security Benefits

- **Principle of Least Privilege**: Only grant permissions actually needed
- **Reduced Blast Radius**: Limit potential damage from compromised credentials
- **Compliance**: Meet security frameworks requiring minimal permissions
- **Auditability**: Clear documentation of why each permission is needed
