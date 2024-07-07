variable "ecs_bastion_cluster_name" {
  type        = string
  description = "The name of the ECS cluster where the bastion service is running"
}

variable "ecs_bastion_service_name" {
  type        = string
  description = "The name of the ECS service running the bastion"
}

variable "target_host" {
  type        = string
  description = "The host to forward traffic to"
}

variable "target_port" {
  type        = number
  description = "The port to forward traffic to"
}

variable "local_port" {
  type        = number
  description = "The local port where the tunnel will listen"
}

variable "ssm_document_name" {
  type        = string
  default     = "AWS-StartPortForwardingSessionToRemoteHost"
  description = "The name of the SSM document to use to start the tunnel"
}

variable "separate_plan_apply" {
  type        = bool
  default     = false
  description = "Set to true if you run `plan` and `apply` separately (`terraform plan -out=...` and `terraform apply ...` rather than a single `terraform apply`). This will ensure the tunnel is available on both stages."
}

variable "assume_role_arn" {
  type        = string
  default     = null
  description = "If set, the module will assume this role before starting the tunnel. If both this variable and `assume_role_with_web_identity_role_arn` are set, the module will do role chaining, assuming the Web Identity role first and then this one"
}

variable "assume_role_session_name" {
  type        = string
  default     = "terraform-aws-ssm-tunnel"
  description = "The name of the session when assuming the role"
}

variable "assume_role_with_web_identity_role_arn" {
  type        = string
  default     = null
  description = "If set, the module will assume this role with the Web Identity token"
}

variable "assume_role_with_web_identity_role_session_name" {
  type        = string
  default     = "terraform-aws-ssm-tunnel"
  description = "The name of the session when assuming the role with the Web Identity token"
}

variable "assume_role_with_web_identity_token_env_var_name" {
  type        = string
  default     = null
  description = "If set, the module will assume the role with the Web Identity token stored in the environment variable with this name. Mutually exclusive with `assume_role_with_web_identity_token_file_path`"
}

variable "assume_role_with_web_identity_token_file_path" {
  type        = string
  default     = null
  description = "If set, the module will assume the role with the Web Identity token stored in the specified file. Mutually exclusive with `assume_role_with_web_identity_token_env_var_name`"
}

variable "aws_profile" {
  type        = string
  default     = null
  description = "If set, the module will use this AWS profile to start the tunnel"
}