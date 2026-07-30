resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.project}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 60
}

resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.project}-${var.environment}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

data "azurerm_key_vault_secret" "openai" {
  name         = "openai-api-key"
  key_vault_id = azurerm_key_vault.main.id
}

data "azurerm_key_vault_secret" "geoapify" {
  name         = "geoapify-api-key"
  key_vault_id = azurerm_key_vault.main.id
}

data "azurerm_key_vault_secret" "serpapi" {
  name         = "serpapi-api-key"
  key_vault_id = azurerm_key_vault.main.id
}

data "azurerm_key_vault_secret" "mistral" {
  name         = "mistral-api-key"
  key_vault_id = azurerm_key_vault.main.id
}

data "azurerm_key_vault_secret" "jwt" {
  name         = "jwt-secret-key"
  key_vault_id = azurerm_key_vault.main.id
}

data "azurerm_key_vault_secret" "restcountries" {
  name         = "restcountries-api-key"
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_container_app" "backend" {
  name                         = "ca-backend-${var.project}-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"


  secret {
    name  = "acr-password"
    value = azurerm_container_registry.main.admin_password
  }

  secret {
    name  = "database-url"
    value = "postgresql://tbadmin:${random_password.postgres.result}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/travelbuddy?sslmode=require"
  }

  secret {
    name  = "openai-api-key"
    value = data.azurerm_key_vault_secret.openai.value
  }

  secret {
    name  = "geoapify-api-key"
    value = data.azurerm_key_vault_secret.geoapify.value
  }

  secret {
    name  = "serpapi-api-key"
    value = data.azurerm_key_vault_secret.serpapi.value
  }

  secret {
    name  = "mistral-api-key"
    value = data.azurerm_key_vault_secret.mistral.value
  }

  secret {
    name  = "jwt-secret-key"
    value = data.azurerm_key_vault_secret.jwt.value
  }

  secret {
    name  = "restcountries-api-key"
    value = data.azurerm_key_vault_secret.restcountries.value
  }

  registry {
    server               = azurerm_container_registry.main.login_server
    username             = azurerm_container_registry.main.admin_username
    password_secret_name = "acr-password"
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "backend"
      image  = var.backend_image
      cpu    = 1.0
      memory = "2Gi"

      env {
        name        = "DATABASE_URL"
        secret_name = "database-url"
      }
      env {
        name        = "OPENAI_API_KEY"
        secret_name = "openai-api-key"
      }
      env {
        name        = "GEOAPIFY_API_KEY"
        secret_name = "geoapify-api-key"
      }
      env {
        name        = "SERPAPI_API_KEY"
        secret_name = "serpapi-api-key"
      }
      env {
        name        = "MISTRAL_API_KEY"
        secret_name = "mistral-api-key"
      }
      env {
        name        = "JWT_SECRET_KEY"
        secret_name = "jwt-secret-key"
      }
      env {
        name        = "RESTCOUNTRIES_API_KEY"
        secret_name = "restcountries-api-key"
      }
      env {
        name  = "MISTRAL_MODEL"
        value = "mistral-small-latest"
      }
      env {
        name  = "ANONYMIZED_TELEMETRY"
        value = "False"
      }
      env {
        name  = "CORS_ORIGINS"
        value = "[\"https://ca-frontend-${var.project}-${var.environment}.${azurerm_container_app_environment.main.default_domain}\"]"
      }

    }
  }

  ingress {
    external_enabled = true
    target_port      = 8000

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

resource "azurerm_container_app" "frontend" {
  name                         = "ca-frontend-${var.project}-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  secret {
    name  = "acr-password"
    value = azurerm_container_registry.main.admin_password
  }

  registry {
    server               = azurerm_container_registry.main.login_server
    username             = azurerm_container_registry.main.admin_username
    password_secret_name = "acr-password"
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "frontend"
      image  = var.frontend_image
      cpu    = 1.0
      memory = "2Gi"

      env {
        name  = "NEXT_PUBLIC_API_URL"
        value = "https://ca-backend-${var.project}-${var.environment}.${azurerm_container_app_environment.main.default_domain}"
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 3000

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

}
