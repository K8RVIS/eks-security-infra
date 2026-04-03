output "namespace_names" {
  description = "Created team namespace names."
  value       = sort([for namespace in kubernetes_namespace_v1.teams : namespace.metadata[0].name])
}
