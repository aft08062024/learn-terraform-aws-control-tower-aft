# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  alias   = "management"
  # Use "aws configure" to create the "management" profile with the Management account credentials
  profile = "management" 
}

provider "aws" {
  alias   = "audit"
  # Use "aws configure" to create the "audit" profile with the Audit account credentials
  profile = "audit" 
}

provider "aws" {
  alias   = "controller"
  # Use "aws configure" to create the "controller" profile with the Audit account credentials
  profile = "controller" 
}

terraform {
  backend "s3" {
    region = "us-east-1"                     # aft main region
    bucket = "terraform-states-058264455607" # s3 bucket name
    key    = "aft-setup.tfstate"
  }
}

module "aft" {
  source                      = "github.com/aft08062024/terraform-aws-control_tower_account_factory"
  ct_management_account_id    = var.ct_management_account_id
  log_archive_account_id      = var.log_archive_account_id
  audit_account_id            = var.audit_account_id
  aft_management_account_id   = var.aft_management_account_id
  ct_home_region              = var.ct_home_region
  tf_backend_secondary_region = var.tf_backend_secondary_region

vcs_provider                                  = "github"
  account_request_repo_name                     = "${var.github_username}/learn-terraform-aft-account-request"
  global_customizations_repo_name               = "${var.github_username}/learn-terraform-aft-global-customizations"
  account_customizations_repo_name              = "${var.github_username}/learn-terraform-aft-account-customizations"
  account_provisioning_customizations_repo_name = "${var.github_username}/learn-terraform-aft-account-provisioning-customizations"
}

# Security Hub
data "aws_caller_identity" "audit" {
  provider = aws.audit
}

resource "aws_securityhub_account" "audit" {
  provider                 = aws.audit
  enable_default_standards = false
}

resource "aws_securityhub_organization_admin_account" "this" {
  provider         = aws.management
  admin_account_id = data.aws_caller_identity.audit.account_id
  depends_on       = [aws_securityhub_account.audit]
}

module "security-hub" {
  # STANDALONE FOR MPA
  source  = "aws-ia/security-hub/aws"
  version = "0.0.1"

  enable_default_standards  = false
  control_finding_generator = "STANDARD_CONTROL"
  auto_enable_controls      = false

  standards_config = {
    aws_foundational_security_best_practices = {
      enable = true
      status = "ENABLED"
    }
    cis_aws_foundations_benchmark_v120 = {
      enable = false
    }
    cis_aws_foundations_benchmark_v140 = {
      enable = false
      # status = "ENABLED"
    }
    nist_sp_800_53_rev5 = {
      enable = false
    }
    pci_dss = {
      enable = false
    }
  }

  action_target = [{
    name        = "Send to Amazon SNS"
    identifier  = "SendToSNS"
    description = "This is a custom action to send findings to SNS Topic"
  }]
}

# aggregators in audit
resource "aws_securityhub_finding_aggregator" "this" {
  provider     = aws.audit
  linking_mode = "SPECIFIED_REGIONS"
  specified_regions = ["us-west-2"]
  depends_on   = [aws_securityhub_account.audit]
}

# makes an account a security hub member
module "security-hub_organizations_member" {
  source  = "aws-ia/security-hub/aws//modules/organizations_member"
  version = "0.0.1"

  providers = {
    aws.member = aws.controller
  }

  member_config = [{
  account_id = "637423428355"
  email      = "controller@aws-lab.business"
    invite     = false
  }]

  depends_on = [module.security-hub]
}