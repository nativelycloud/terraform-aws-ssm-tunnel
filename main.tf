data "aws_region" "current" {}

locals {
  program = concat([
    "${path.module}/start-ssm-tunnel.sh",
    "--aws-region", data.aws_region.current.name,
    "--ecs-cluster-name", var.ecs_bastion_cluster_name,
    "--ecs-service-name", var.ecs_bastion_service_name,
    "--ssm-document-name", var.ssm_document_name,
    "--target-host", var.target_host,
    "--target-port", var.target_port,
    "--local-port", var.local_port
    ],
    var.assume_role_arn != null ? [
      "--assume-role-arn", var.assume_role_arn,
      "--assume-role-session-name", var.assume_role_session_name,
    ] : [],
    var.assume_role_with_web_identity_role_arn != null ? [
      "--assume-role-with-web-identity-role-arn", var.assume_role_with_web_identity_role_arn,
      "--assume-role-with-web-identity-role-session-name", var.assume_role_with_web_identity_role_session_name,
    ] : [],
    var.assume_role_with_web_identity_token_env_var_name != null ? [
      "--assume-role-with-web-identity-token-env-var-name", var.assume_role_with_web_identity_token_env_var_name
    ] : [],
    var.assume_role_with_web_identity_token_file_path != null ? [
      "--assume-role-with-web-identity-token-file-path", var.assume_role_with_web_identity_token_file_path
    ] : [],
  var.aws_profile != null ? ["--aws-profile", var.aws_profile] : [])
}

data "external" "plan" {
  program = local.program
}

data "external" "apply" {
  count = var.separate_plan_apply ? 1 : 0

  program = local.program

  query = {
    dummy_trigger = timestamp()
  }
}
