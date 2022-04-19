# Inject credentials via the AWS_PROFILE environment variable and shared credentials file
# and/or EC2 metadata service
terraform {
  backend "s3" {
    encrypt = "true"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Inject credentials via the AWS_PROFILE environment variable and shared credentials file and/or EC2 metadata service
#
provider "aws" {}

#done
module "cdis_vpc" {
  source                         = "../modules/vpc"
  ami_account_id                 = var.ami_account_id
  squid_image_search_criteria    = var.squid_image_search_criteria
  vpc_cidr_block                 = var.vpc_cidr_block
  secondary_cidr_block           = var.secondary_cidr_block
  vpc_name                       = var.vpc_name
  ssh_key_name                   = aws_key_pair.automation_dev.key_name
  peering_cidr                   = var.peering_cidr
  csoc_account_id                = var.csoc_account_id
  organization_name              = var.organization_name
  csoc_managed                   = var.csoc_managed
  peering_vpc_id                 = var.peering_vpc_id
  vpc_flow_logs                  = var.vpc_flow_logs
  vpc_flow_traffic               = var.vpc_flow_traffic
  branch                         = var.branch
  fence-bot_bucket_access_arns   = var.fence-bot_bucket_access_arns
  deploy_ha_squid                = var.deploy_ha_squid
  deploy_single_proxy            = var.deploy_single_proxy
  squid_cluster_desired_capasity = var.ha-squid_cluster_desired_capasity
  squid_cluster_min_size         = var.ha-squid_cluster_min_size
  squid_cluster_max_size         = var.ha-squid_cluster_max_size
  squid_instance_type            = var.ha-squid_instance_type
  squid_instance_drive_size      = var.ha-squid_instance_drive_size
  squid_bootstrap_script         = var.ha-squid_bootstrap_script
  squid_extra_vars               = var.ha-squid_extra_vars
  single_squid_instance_type     = var.single_squid_instance_type
  fips                           = var.fips
  network_expansion              = var.network_expansion
  activation_id                  = var.activation_id
  customer_id                    = var.customer_id
  slack_webhook                  = var.slack_webhook
}

# logs bucket for elb logs
#done
module "elb_logs" {
  source          = "../modules/s3-logs"
  log_bucket_name = "logs-${var.vpc_name}-gen3"
  environment     = var.vpc_name
}


#done
module "config_files" {
  source                        = "../../shared/modules/k8s_configs"
  vpc_name                      = var.vpc_name
  db_fence_address              = aws_db_instance.db_fence.address
  db_fence_password             = var.db_password_fence
  db_fence_name                 = aws_db_instance.db_fence.name
  db_sheepdog_address           = aws_db_instance.db_sheepdog.address
  db_sheepdog_username          = aws_db_instance.db_sheepdog.username
  db_sheepdog_password          = var.db_password_sheepdog
  db_sheepdog_name              = aws_db_instance.db_sheepdog.name
  db_peregrine_password         = var.db_password_peregrine
  db_indexd_address             = aws_db_instance.db_indexd.address
  db_indexd_username            = aws_db_instance.db_indexd.username
  db_indexd_password            = var.db_password_indexd
  db_indexd_name                = aws_db_instance.db_indexd.name
  hostname                      = var.hostname
  google_client_secret          = var.google_client_secret
  google_client_id              = var.google_client_id
  hmac_encryption_key           = var.hmac_encryption_key
  sheepdog_secret_key           = var.sheepdog_secret_key
  sheepdog_indexd_password      = var.sheepdog_indexd_password
  sheepdog_oauth2_client_id     = var.sheepdog_oauth2_client_id
  sheepdog_oauth2_client_secret = var.sheepdog_oauth2_client_secret
  kube_bucket_name              = aws_s3_bucket.kube_bucket.id
  logs_bucket_name              = module.elb_logs.log_bucket_name
  gitops_path                   = var.gitops_path
  ssl_certificate_id            = var.aws_cert_name
  aws_user_key                  = module.cdis_vpc.es_user_key
  aws_user_key_id               = module.cdis_vpc.es_user_key_id
  indexd_prefix                 = var.indexd_prefix

## mailgun creds
  mailgun_api_key             = var.mailgun_api_key
  mailgun_api_url             = var.mailgun_api_url
  mailgun_smtp_host           = var.mailgun_smtp_host

}

#done
module "cdis_alarms" {
  count                       = var.deploy_alarms ? 1 : 0
  source                      = "../modules/commons-alarms"
  slack_webhook               = var.slack_webhook
  secondary_slack_webhook     = var.secondary_slack_webhook
  vpc_name                    = var.vpc_name
  alarm_threshold             = var.alarm_threshold
  db_fence_size               = aws_db_instance.db_fence.allocated_storage
  db_indexd_size              = aws_db_instance.db_indexd.allocated_storage
  db_sheepdog_size            = aws_db_instance.db_sheepdog.allocated_storage
  db_fence                    = aws_db_instance.db_fence.identifier
  db_indexd                   = aws_db_instance.db_indexd.identifier
  db_sheepdog                 = aws_db_instance.db_sheepdog.identifier
}


resource "aws_route_table" "private_kube" {
  vpc_id                      = module.cdis_vpc.vpc_id

  tags = {
    Name                      = "private_kube"
    Environment               = var.vpc_name
    Organization              = var.organization_name
  }
}

resource "aws_route" "for_peering" {
  count                     = var.csoc_managed ? 1 : 0
  route_table_id            = aws_route_table.private_kube.id
  destination_cidr_block    = var.peering_cidr
  vpc_peering_connection_id = module.cdis_vpc.vpc_peering_id
  depends_on                = [aws_route_table.private_kube]
}

resource "aws_route_table_association" "private_kube" {
  subnet_id                   = aws_subnet.private_kube.id
  route_table_id              = aws_route_table.private_kube.id
}

resource "aws_subnet" "private_kube" {
  vpc_id                      = module.cdis_vpc.vpc_id
  cidr_block                  = var.network_expansion ? cidrsubnet(var.vpc_cidr_block,5,0) : cidrsubnet(var.vpc_cidr_block,4,2)
  map_public_ip_on_launch     = false
  availability_zone           = data.aws_availability_zones.available.names[0]
  tags                        = map("Name", "int_services", "Organization", var.organization_name, "Environment", var.vpc_name )

  lifecycle {
    # allow user to change tags interactively - ex - new kube-aws cluster
    ignore_changes = ["tags", "availability_zone"]
  }
}

resource "aws_subnet" "private_db_alt" {
  vpc_id                      = module.cdis_vpc.vpc_id
  cidr_block                  = var.network_expansion ? cidrsubnet(var.vpc_cidr_block,5,1) : cidrsubnet(var.vpc_cidr_block,4,3)
  availability_zone           = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch     = false

  tags = {
    Name                      = "private_db_alt"
    Environment               = var.vpc_name
    Organization              = var.organization_name
  }

  lifecycle {
    # allow user to change tags interactively - ex - new kube-aws cluster
    ignore_changes = ["tags", "availability_zone"]
  }
}

resource "aws_db_subnet_group" "private_group" {
  name                        = "${var.vpc_name}_private_group"
  subnet_ids                  = [aws_subnet.private_kube.id, aws_subnet.private_db_alt.i]

  tags = {
    Name                      = "Private subnet group"
    Environment               = var.vpc_name
    Organization              = var.organization_name
  }

  description                 = "Private subnet group"
}

