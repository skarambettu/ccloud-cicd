terraform {
  backend "local" {
    path = "Users/skarambettu/desktop/abcd.dev.tfstate"
  }
}

provider "confluent" {
  cloud_api_key    = jsondecode(data.azurerm_key_vault_secret.cloud_secrets.value)["id"]
  cloud_api_secret = jsondecode(data.azurerm_key_vault_secret.cloud_secrets.value)["secret"]
}

provider "azurerm" {
  features {}
}

##
## FETCHING DATA
##

data "azurerm_resource_group" "rg" {
  name  = "sandesh-testgroup"
}

data "azurerm_client_config" "current" {}

locals {
  current_user_id = data.azurerm_client_config.current.object_id
}

data "azurerm_key_vault" "vault" {
  name                       = "sandesh-tf-kv"
  resource_group_name        = data.azurerm_resource_group.rg.name
}

data "azurerm_key_vault_secret" "cloud_secrets" {
  name         = "cloud-secrets"
  key_vault_id = data.azurerm_key_vault.vault.id
}

data "azurerm_key_vault_secret" "cluster-admin" {
  name         = "ccloud-cluster-admin"
  key_vault_id = data.azurerm_key_vault.vault.id
}

data "azurerm_key_vault_secret" "cluster-admin-sr" {
  name         = "ccloud-cluster-admin-sr-apikey"
  key_vault_id = data.azurerm_key_vault.vault.id
}

data "confluent_kafka_cluster" "kafka_cluster_id" {
  id = var.confluent_kafka_cluster
  environment {
    id = var.confluent_environment
  }
}

data "confluent_schema_registry_cluster" "schema_cluster_id" {
  id = var.confluent_schema_registry
  environment {
    id = var.confluent_environment
  }
}

locals {
  topics = jsondecode(file("../env/dev/${var.project}/${var.project_env}/topics.json"))
  rbacs  = jsondecode(file("../env/dev/${var.project}/${var.project_env}/rbacs.json"))
  sas    = jsondecode(file("../env/dev/${var.project}/${var.project_env}/sas.json"))
  schemas    = jsondecode(file("../env/dev/${var.project}/${var.project_env}/schemas.json"))
  apikeys    = jsondecode(file("../env/dev/${var.project}/${var.project_env}/apikeys.json"))
  acls    = jsondecode(file("../env/dev/${var.project}/${var.project_env}/acls.json"))
  connectors    = jsondecode(file("../env/dev/${var.project}/${var.project_env}/connectors.json"))
}

##
## CREATING TOPIC
##

locals {
  topics_with_names = [ for topic in local.topics.topics : topic if topic.name != "" ]
}

module "topic" {
  for_each = { for topic in local.topics_with_names : topic.name => topic }
  source   = "./modules/topic"
  env_id   = var.confluent_environment
  kafka_id = var.confluent_kafka_cluster
  topic    = each.value
  admin_sa = {
    api_key    = jsondecode(data.azurerm_key_vault_secret.cluster-admin.value)["id"]
    api_secret = jsondecode(data.azurerm_key_vault_secret.cluster-admin.value)["secret"]
  }
}

locals {
  schemas_with_subject = [ for schema in local.schemas.schemas : schema if schema.subject != "" ]
}

module "schema" {
  for_each = { for schema in local.schemas_with_subject : schema.subject => schema }
  source   = "./modules/schema"
  env_id   = var.confluent_environment
  schema_id = var.confluent_schema_registry
  schema    = each.value
  admin_sa = {
    api_key    = jsondecode(data.azurerm_key_vault_secret.cluster-admin-sr.value)["id"]
    api_secret = jsondecode(data.azurerm_key_vault_secret.cluster-admin-sr.value)["secret"]
  }
}

locals {
  sas_with_name = [ for sa in local.sas.sas : sa if sa.name != "" ]
}

module "sa" {
  for_each = { for sa in local.sas_with_name : sa.name => sa }
  source   = "./modules/sa"
  sa       = each.value
}

locals {
  rbacs_with_topics = [ for rbac in local.rbacs.rbacs.topics : rbac if rbac.resource != "" ]
}

module "rbac_topics" {
  for_each             = { for rbac in local.rbacs_with_topics : format("%s/%s/%s", rbac.resource, rbac.role, rbac.principal) => rbac }
  source               = "./modules/rbac"
  crn                  = "${data.confluent_kafka_cluster.kafka_cluster_id.rbac_crn}/kafka=${data.confluent_kafka_cluster.kafka_cluster_id.id}/topic=${each.value.resource}"
  role                 = each.value.role
  principal            = each.value.principal
}

locals {
  rbacs_with_groups = [ for rbac in local.rbacs.rbacs.group : rbac if rbac.resource != "" ]
}

module "rbac_group" {
  for_each             = { for rbac in local.rbacs_with_groups : format("%s/%s/%s", rbac.resource, rbac.role, rbac.principal) => rbac }
  source               = "./modules/rbac"
  crn                  = "${data.confluent_kafka_cluster.kafka_cluster_id.rbac_crn}/kafka=${data.confluent_kafka_cluster.kafka_cluster_id.id}/group=${each.value.resource}"
  role                 = each.value.role
  principal            = each.value.principal
}

locals {
  rbacs_with_schema_registry = [ for rbac in local.rbacs.rbacs.schema_registry : rbac if rbac.resource != "" ]
}

module "rbac_schema_registry" {
  for_each             = { for rbac in local.rbacs_with_schema_registry : format("%s/%s/%s", rbac.resource, rbac.role, rbac.principal) => rbac }
  source               = "./modules/rbac"
  crn                  = "${data.confluent_schema_registry_cluster.schema_cluster_id.resource_name}/subject=${each.value.resource}"
  role                 = each.value.role
  principal            = each.value.principal
}

locals {
  apikeys_with_principals = [ for apikey in local.apikeys.apikeys.kafka : apikey if apikey.principal != "" ]
}

module "apikey_kafka" {
  for_each = { for apikey in local.apikeys_with_principals : apikey.principal => apikey }
  source   = "./modules/apikey"
  env_id   = var.confluent_environment
  kafka_id = var.confluent_kafka_cluster
  apikey   = each.value
}

locals {
  sr_apikeys_with_principals = [ for apikey in local.apikeys.apikeys.schema_registry : apikey if apikey.principal != "" ]
}

module "apikey_schema_registry" {
  for_each = { for apikey in local.sr_apikeys_with_principals : apikey.principal => apikey }
  source   = "./modules/sr-apikey"
  env_id   = var.confluent_environment
  schema_id = var.confluent_schema_registry
  apikey   = each.value
}

locals {
  acls_with_principals = [ for acl in local.acls.acls : acl if acl.principal != "" ]
}

module "acl" {
  for_each        = { for acl in local.acls_with_principals : format("%s/%s/%s/%s/%s", acl.principal, acl.resource_type, acl.resource_name, acl.operation, acl.permission) => acl }
  source          = "./modules/acl"
  env_id          = var.confluent_environment
  kafka_id        = var.confluent_kafka_cluster
  principal       = each.value.principal
  resource_type   = each.value.resource_type
  resource_name   = each.value.resource_name
  operation       = each.value.operation
  host            = each.value.host
  pattern_type    = each.value.pattern_type
  permission      = each.value.permission
  admin_sa = {
    api_key    = jsondecode(data.azurerm_key_vault_secret.cluster-admin.value)["id"]
    api_secret = jsondecode(data.azurerm_key_vault_secret.cluster-admin.value)["secret"]
  }
}

