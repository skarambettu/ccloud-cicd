data "confluent_kafka_cluster" "kafka_cluster" {
  id = var.kafka_id
  environment {
    id = var.env_id
  }
}

data "confluent_service_account" "sa" {
  display_name = var.principal
}

resource "confluent_connector" "snowflake-sink" {
  environment {
    id = var.env_id
  }
  kafka_cluster {
    id = data.confluent_kafka_cluster.kafka_cluster.id
  }

  // Block for custom *sensitive* configuration properties that are labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-snowflake-sink.html#configuration-properties
  config_sensitive = {
    "snowflake.private.key" = var.key
  }

  // Block for custom *nonsensitive* configuration properties that are *not* labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-snowflake-sink.html#configuration-properties
  config_nonsensitive = {
    "topics"                   = var.topics
    "input.data.format"        = var.format
    "connector.class"          = var.class
    "name"                     = var.name
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = data.confluent_service_account.sa.id
    "snowflake.url.name"       = var.url
    "snowflake.user.name"      = var.user
    "snowflake.database.name"  = var.db_name
    "snowflake.schema.name"    = var.schema_name
    "tasks.max"                = "1"
  }
}