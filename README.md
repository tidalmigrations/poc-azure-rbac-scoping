# Azure RBAC Scope Reduction - POC

This project demonstrates how to reduce Azure RBAC permissions for Terraform deployments by analyzing actual usage patterns and generating minimal custom roles.

- [Azure RBAC Scope Reduction - POC](#azure-rbac-scope-reduction---poc)
  - [Overview](#overview)
  - [Project Structure](#project-structure)
  - [Demo Application](#demo-application)
  - [Prerequisites](#prerequisites)
  - [Quick Start](#quick-start)
    - [Azure Setup](#azure-setup)
    - [Configure Terraform Backend](#configure-terraform-backend)
    - [Deploy Demo Application](#deploy-demo-application)
    - [Deploy Logging Infrastructure](#deploy-logging-infrastructure)
    - [Baseline Deployment \& Capture](#baseline-deployment--capture)
  - [Sample Files](#sample-files)
  - [Configuration Options](#configuration-options)
  - [Security Benefits](#security-benefits)

## Overview

The goal is to move from broad permissions (like Contributor) to minimal, scoped permissions by:

1. Deploying infrastructure with broad permissions while logging all activities
2. Analyzing the logs to identify actually used permissions
3. Generating a custom RBAC role with only the required permissions
4. Validating the minimal permissions work for the same deployment

## Project Structure

```
poc-azure-rbac-scoping/
├── terraform/
│   ├── demo-app/          # Demo application infrastructure
│   ├── logging-setup/     # Log Analytics and monitoring setup
│   └── modules/           # Reusable Terraform modules
├── scripts/               # Automation scripts for analysis and deployment
├── config/                # Configuration files and examples
├── logs/                  # Generated analysis reports and logs
├── docs/                  # Detailed documentation
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
- Bash shell (macOS/Linux) or WSL on Windows
- Azure subscription with appropriate permissions to create service principals
- jq (for JSON processing)

## Quick Start

### Azure Setup

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Run automated setup (if available)
./scripts/azure-setup.sh
```

### Configure Terraform Backend

```bash
# Create storage account for Terraform state
./scripts/setup-backend.sh
```

### Deploy Demo Application

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

### Deploy Logging Infrastructure

Before analyzing permissions, establish comprehensive activity logging to capture all Azure operations:

```bash
# Install required Azure CLI extensions
./scripts/install-az-extensions.sh

# Deploy Log Analytics workspace and diagnostic settings
./scripts/deploy-logging.sh

# Validate the setup
./scripts/validate-logging.sh
```

### Baseline Deployment & Capture

```bash
./scripts/deploy-and-monitor.sh

# This will:
# 1. Load configuration from available sources
# 2. Clean existing resources for accurate capture
# 3. Deploy demo application with monitoring
# 4. Extract and analyze permissions used
# 5. Generate multiple report formats

# Validate everything worked correctly
./scripts/validate-phase3.sh

# Extract permissions for specific time range
./scripts/extract-permissions.sh "2024-01-15T10:00:00Z" "2024-01-15T11:00:00Z"
```

**Generated files:**
- `logs/deployment-*.log` - Complete deployment log with timestamps
- `logs/activity-logs-*.json` - Raw Azure activity data (47+ events)
- `logs/permissions-analysis-*.json` - Processed permissions analysis
- `logs/permissions-*.csv` - Spreadsheet-compatible export
- `logs/permissions-summary-*.txt` - Human-readable report
- `logs/minimal-role-template-*.json` - Initial custom role definition

## Sample Files

The `logs/` directory includes anonymized sample files that demonstrate the output format without exposing sensitive information:

- **`deployment-sample.log`** - Example Terraform deployment log showing the complete infrastructure creation process
- **`activity-logs-sample.json`** - Sample Azure Activity Log events with anonymized GUIDs and identifiers
- **`permissions-analysis-sample.json`** - Example processed permissions data showing operation frequency
- **`permissions-sample.csv`** - Spreadsheet-friendly sample export for manual analysis
- **`permissions-summary-sample.txt`** - Human-readable sample summary report
- **`minimal-role-template-sample.json`** - Example generated Azure RBAC role definition

These samples are safe to commit to version control and can be used for:
- Understanding output formats before running the POC
- Testing analysis scripts and tools
- Documentation and training purposes
- Sharing examples without exposing real Azure resources

See [`logs/README-samples.md`](logs/README-samples.md) for detailed information about the sample files and anonymization patterns used.

## Configuration Options

The project supports flexible configuration loading with automatic variable mapping:

**Supported Configuration Files:**
1. `config/azure-config.env` (highest precedence)
2. `.env.terraform` (medium precedence) 
3. `.env` (lowest precedence)

**Automatic Variable Mapping:**
- `ARM_SUBSCRIPTION_ID` → `AZURE_SUBSCRIPTION_ID`
- `ARM_CLIENT_ID` → `SERVICE_PRINCIPAL_ID`
- `ARM_TENANT_ID` → `AZURE_TENANT_ID`
- `ARM_CLIENT_SECRET` → `SERVICE_PRINCIPAL_SECRET`

**Key Features:**
- ✅ Multi-source configuration loading
- ✅ Terraform ARM_* variable support
- ✅ Service Principal Object ID resolution
- ✅ Masked sensitive values in logs
- ✅ Backward compatibility with existing setups

## Security Benefits

- **Principle of Least Privilege**: Only grant permissions actually needed
- **Reduced Blast Radius**: Limit potential damage from compromised credentials
- **Compliance**: Meet security frameworks requiring minimal permissions
- **Auditability**: Clear documentation of why each permission is needed
- **Cost Optimization**: Reduced monitoring and compliance overhead

---

## Attribution

Provided by Tidal <support@tidalcloud.com>
