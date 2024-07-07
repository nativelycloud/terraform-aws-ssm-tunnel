terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11"
    }
  }
}

provider "aws" {
  region = "eu-west-1"

  #assume_role_with_web_identity {
  # role_arn = "arn:aws:iam::012345678901:role/ssm-bastion-role"
  # web_identity_token =  "eyJr..."
  #}
}

module "tunnel_rds" {
  source                   = "../../"
  ecs_bastion_cluster_name = module.ssm_bastion_fargate.ecs_cluster_name
  ecs_bastion_service_name = module.ssm_bastion_fargate.ecs_service_name
  target_host              = "checkip.amazonaws.com"
  target_port              = 80
  local_port               = 8080
  #assume_role_arn = "arn:aws:iam::012345678901:role/ssm-bastion-role"
  #assume_role_with_web_identity_role_arn = "arn:aws:iam::012345678901:role/ssm-bastion-role"
  #assume_role_with_web_identity_token_env_var_name = "GITLAB_OIDC_TOKEN"
  #assume_role_with_web_identity_token_file_path = "/gitlab_oidc_token.txt"
  depends_on = [time_sleep.wait_for_bastion] # Not needed if provisioning the ECS bastion in a separate module
}

data "http" "checkip" {
  url = "http://${module.tunnel_rds.local_host}:${module.tunnel_rds.local_port}"
}

output "bastion_public_ip" {
  value = data.http.checkip.response_body
}

## Requirements, typically deployed elsewhere only once
resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_route" "public_default" {
  route_table_id         = aws_vpc.this.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_subnet" "public" {
  count             = 3
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = "eu-west-1${element(["a", "b", "c"], count.index)}"
}

module "ssm_bastion_fargate" {
  source           = "github.com/nativelycloud/terraform-aws-ssm-bastion-fargate?ref=v0.1.2"
  name             = "ssm-bastion"
  vpc_id           = aws_vpc.this.id
  subnets          = aws_subnet.public[*].id
  assign_public_ip = true

  depends_on = [aws_route.public_default]
}

# Sleep 30 seconds to allow the bastion to start
resource "time_sleep" "wait_for_bastion" {
  depends_on      = [module.ssm_bastion_fargate]
  create_duration = "30s"
}