terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = ">= 1.22"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

provider "postgresql" {
  host            = module.tunnel_rds.local_host
  port            = module.tunnel_rds.local_port
  database        = "postgres"
  username        = aws_db_instance.this.username
  password        = aws_db_instance.this.password
  sslmode         = "require"
  connect_timeout = 15
}

locals {
  stack_name = "ssm-tunnels-rds-postgres-example"
}

module "tunnel_rds" {
  source                   = "../../"
  ecs_bastion_cluster_name = module.ssm_bastion_fargate.ecs_cluster_name
  ecs_bastion_service_name = module.ssm_bastion_fargate.ecs_service_name
  target_host              = aws_db_instance.this.address
  target_port              = 5432
  local_port               = 5432
  separate_plan_apply      = true
  depends_on               = [time_sleep.wait_for_bastion] # Not needed if provisioning the ECS bastion in a separate module
}

resource "postgresql_database" "test_db" {
  name = "test_db"
}

resource "aws_security_group" "rds" {
  name   = "${local.stack_name}-rds"
  vpc_id = aws_vpc.this.id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.ssm_bastion_fargate.default_security_group_id]
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.stack_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags = {
    Name = local.stack_name
  }
}

resource "aws_db_instance" "this" {
  identifier             = "${local.stack_name}-db"
  engine                 = "postgres"
  engine_version         = "16.1"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp3"
  username               = "myuser"
  password               = "mypassword"
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
}

## Requirements, typically deployed elsewhere only once
resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = local.stack_name
  }
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
  tags = {
    Name = "${local.stack_name}-public-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.${count.index + 3}.0/24"
  availability_zone = "eu-west-1${element(["a", "b", "c"], count.index)}"
  tags = {
    Name = "${local.stack_name}-private-${count.index}"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "${local.stack_name}-private"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

module "ssm_bastion_fargate" {
  source           = "github.com/nativelycloud/terraform-aws-ssm-bastion-fargate?ref=v0.1.2"
  name             = local.stack_name
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