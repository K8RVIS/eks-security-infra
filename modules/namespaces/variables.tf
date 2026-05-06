variable "project_name" {
  description = "Project identifier used in namespace labels."
  type        = string
}

variable "team_names" {
  description = "Team namespace names to create."
  type        = list(string)
  default     = ["team-a", "team-b", "team-c", "team-d", "team-dev"]
}