output "local_host" {
  value       = "localhost${data.external.plan.result == null ? "" : ""}${data.external.apply[*].result == null ? "" : ""}"
  description = "The local host to connect to"
}

output "local_port" {
  value       = var.local_port + (data.external.plan.result == null ? 0 : 0) + (data.external.apply[*].result == null ? 0 : 0)
  description = "The local port to connect to"
}