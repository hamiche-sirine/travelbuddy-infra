variable "subscription_id" {
  type        = string
  description = "Identifiant de l'abonnement Azure cible"
  default     = "4a523202-bb04-4dda-bbbc-57aaa621b4a3"
}

variable "location" {
  type        = string
  description = "Region Azure de deploiement"
  default     = "swedencentral"
}

variable "project" {
  type        = string
  description = "Nom court du projet"
  default     = "travelbuddy"
}

variable "environment" {
  type        = string
  description = "Environnement cible : dev, test ou prod"
  default     = "dev"
}