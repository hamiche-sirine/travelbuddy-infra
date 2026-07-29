resource "random_password" "postgres" {
  length  = 24
  special = true
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                          = "psql-${var.project}-${var.environment}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  version                       = "16"
  administrator_login           = "tbadmin"
  administrator_password        = random_password.postgres.result
  sku_name                      = "B_Standard_B1ms"
  storage_mb                    = 32768
  zone                          = "1"
  backup_retention_days         = 7
  public_network_access_enabled = true

  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgres-admin-password"
  value        = random_password.postgres.result
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = "travelbuddy"
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}