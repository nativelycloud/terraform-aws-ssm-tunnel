# AWS SSM tunnel into VPC from inside Terraform
This Terraform module opens tunnels to your VPC resources using AWS Systems Manager Session Manager, right from your Terraform code. This enables you to provision VPC resources (e.g. databases in RDS, etc.) from wherever your Terraform code runs on the Internet without manually provisioning a bastion host, arranging VPN access or splitting your Terraform code into more modules.

Although designed for seamless use with our [terraform-aws-ssm-bastion-fargate](https://github.com/nativelycloud/terraform-aws-ssm-bastion-fargate) module, it can be used with any ECS service with ECS Exec enabled.

This module was inspired by flaupretre's [terraform-ssh-tunnel](https://github.com/flaupretre/terraform-ssh-tunnel/).

### Features
- Opens a tunnel to any host/port, relayed through an existing ECS task running in your VPC through AWS SSM Session Manager
- Finds the bastion ECS task automatically using the provided ECS cluster and service names
- Supports all TCP port forwarding use cases
- Supports doing `plan` and `apply` separately (`terraform plan -out=...` and `terraform apply ...`), including in different CI/CD stages, by opening the tunnel in both stages (optional, set `separate_plan_apply` to enable)
- Uses [default AWS CLI authentication mechanisms](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html#configure-precedence) to automatically authenticate with AWS
- Supports using an AWS profile for authentication
- Supports additional AssumeRole/AssumeRoleWithWebIdentity (with a token supplied in a file or an environment variable). Both can be combined in role chaining scenarios

### Usage
```hcl
module "tunnel_rds" {
  source                   = "github.com/nativelycloud/terraform-aws-ssm-tunnel?ref=v0.1.0"
  ecs_bastion_cluster_name = "my-ecs-cluster"
  ecs_bastion_service_name = "my-bastion-service"
  target_host              = aws_db_instance.this.address
  target_port              = 5432
  local_port               = 5432
}

provider "postgresql" {
  # Use at least one of the module's outputs or depends_on it to ensure the tunnel is setup before connecting
  host            = module.tunnel_rds.local_host 
  port            = module.tunnel_rds.local_port
  database        = "postgres"
  username        = aws_db_instance.this.username
  password        = aws_db_instance.this.password
}
```
See the [examples](./examples) directory for full usage examples.

### Comparisons
**`terraform-aws-ssm-tunnel` versus other similar modules**
- **Do one thing and do it well** — this module is focused on SSM Session Manager tunneling only and does not support other tunneling methods
- **Simpler architecture** — we start the tunnel with AWS CLI directly, without using an intermediate SSH session
- **Support for separate plan/apply stages** — this module supports running `plan` and `apply` separately, including in completely different CI/CD stages

### Requirements
We try to keep requirements on the environment running Terraform at a minimum. The module requires `sh`, the AWS CLI, the `session-manager-plugin` for AWS CLI, `printenv`, `grep`, and `cut` to be available in the environment.

The principal running the module must have at least the following IAM permissions:
- `ecs:ListTasks` on the target ECS cluster
- `ecs:DescribeTasks` on the target ECS cluster
- `ssm:StartSession` on the target task for the "AWS-StartPortForwardingSessionToRemoteHost" SSM document

### Costs
This module does not incur any additional costs beyond the existing bastion ECS task cost and possible outbound data transfer costs for tunneled data.

### Known issues
- When doing separate `plan` and `apply`, destroys using `plan -destroy` are not supported. A workaround is to remove resources from the Terraform code and run a regular `plan` and `apply` cycle, or to do a `terraform destroy` without a `plan`.

### Upcoming features
- EC2 bastion support
- Ability to specify the bastion ECS task ARN directly
- Smarter bastion ECS task selection (ignore tasks that are not running)
- Better logging
- Windows support (not planned yet)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |
| <a name="requirement_external"></a> [external](#requirement\_external) | >= 1.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.0 |
| <a name="provider_external"></a> [external](#provider\_external) | >= 1.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [external_external.apply](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |
| [external_external.plan](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_assume_role_arn"></a> [assume\_role\_arn](#input\_assume\_role\_arn) | If set, the module will assume this role before starting the tunnel. If both this variable and `assume_role_with_web_identity_role_arn` are set, the module will do role chaining, assuming the Web Identity role first and then this one | `string` | `null` | no |
| <a name="input_assume_role_session_name"></a> [assume\_role\_session\_name](#input\_assume\_role\_session\_name) | The name of the session when assuming the role | `string` | `"terraform-aws-ssm-tunnel"` | no |
| <a name="input_assume_role_with_web_identity_role_arn"></a> [assume\_role\_with\_web\_identity\_role\_arn](#input\_assume\_role\_with\_web\_identity\_role\_arn) | If set, the module will assume this role with the Web Identity token | `string` | `null` | no |
| <a name="input_assume_role_with_web_identity_role_session_name"></a> [assume\_role\_with\_web\_identity\_role\_session\_name](#input\_assume\_role\_with\_web\_identity\_role\_session\_name) | The name of the session when assuming the role with the Web Identity token | `string` | `"terraform-aws-ssm-tunnel"` | no |
| <a name="input_assume_role_with_web_identity_token_env_var_name"></a> [assume\_role\_with\_web\_identity\_token\_env\_var\_name](#input\_assume\_role\_with\_web\_identity\_token\_env\_var\_name) | If set, the module will assume the role with the Web Identity token stored in the environment variable with this name. Mutually exclusive with `assume_role_with_web_identity_token_file_path` | `string` | `null` | no |
| <a name="input_assume_role_with_web_identity_token_file_path"></a> [assume\_role\_with\_web\_identity\_token\_file\_path](#input\_assume\_role\_with\_web\_identity\_token\_file\_path) | If set, the module will assume the role with the Web Identity token stored in the specified file. Mutually exclusive with `assume_role_with_web_identity_token_env_var_name` | `string` | `null` | no |
| <a name="input_aws_profile"></a> [aws\_profile](#input\_aws\_profile) | If set, the module will use this AWS profile to start the tunnel | `string` | `null` | no |
| <a name="input_ecs_bastion_cluster_name"></a> [ecs\_bastion\_cluster\_name](#input\_ecs\_bastion\_cluster\_name) | The name of the ECS cluster where the bastion service is running | `string` | n/a | yes |
| <a name="input_ecs_bastion_service_name"></a> [ecs\_bastion\_service\_name](#input\_ecs\_bastion\_service\_name) | The name of the ECS service running the bastion | `string` | n/a | yes |
| <a name="input_local_port"></a> [local\_port](#input\_local\_port) | The local port where the tunnel will listen | `number` | n/a | yes |
| <a name="input_separate_plan_apply"></a> [separate\_plan\_apply](#input\_separate\_plan\_apply) | Set to true if you run `plan` and `apply` separately (`terraform plan -out=...` and `terraform apply ...` rather than a single `terraform apply`). This will ensure the tunnel is available on both stages. | `bool` | `false` | no |
| <a name="input_ssm_document_name"></a> [ssm\_document\_name](#input\_ssm\_document\_name) | The name of the SSM document to use to start the tunnel | `string` | `"AWS-StartPortForwardingSessionToRemoteHost"` | no |
| <a name="input_target_host"></a> [target\_host](#input\_target\_host) | The host to forward traffic to | `string` | n/a | yes |
| <a name="input_target_port"></a> [target\_port](#input\_target\_port) | The port to forward traffic to | `number` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_local_host"></a> [local\_host](#output\_local\_host) | The local host to connect to |
| <a name="output_local_port"></a> [local\_port](#output\_local\_port) | The local port to connect to |
<!-- END_TF_DOCS -->