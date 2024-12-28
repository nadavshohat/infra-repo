# Infrastructure Repository

This repository contains the infrastructure as code for the MicroStore project using Terraform and Terragrunt.

## Structure

- `environments/` - Environment-specific configurations
  - `dev/` - Development environment
  - `prod/` - Production environment
- `modules/` - Reusable Terraform modules
  - `eks-platform/` - EKS cluster and platform services

## Prerequisites

- Terraform >= 1.0
- Terragrunt >= 0.45
- AWS CLI configured with appropriate credentials

## Usage

To apply infrastructure changes:

```bash
cd environments/dev
terragrunt run-all plan    # Review changes
terragrunt run-all apply   # Apply changes
``` 