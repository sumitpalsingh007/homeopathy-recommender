variable "region"        { default = "ap-south-1" }
variable "project"       { default = "homeo-ai" }
variable "db_password" {
  sensitive   = true
  default     = ""   # leave empty → auto-generated compliant password via random_password
  description = "RDS master password. Leave blank to auto-generate. Cannot contain / \" @ or space."
}
variable "jwt_secret"    { sensitive = true }
variable "domain_name"   { default = "" }   # optional; leave empty to skip Route53 + ACM
variable "ollama_model"  { default = "llama3.1:8b-instruct-q4_0" }
