variable "project" {
  description = "Project to deploy resources for"
  type        = string
}

variable "project_env" {
  description = "Project environment to deploy resources for"
  type        = string
}

variable "confluent_environment" {
  description = "ID of the Confluent Cloud environment environment"
  type        = string
}

variable "confluent_kafka_cluster" {
  description = "ID of the Confluent Cloud cluster to leverage (lkc)"
  type        = string
}

variable "confluent_schema_registry" {
  description = "ID of the Confluent Cloud SR cluster to leverage (lsr)"
  type        = string
}