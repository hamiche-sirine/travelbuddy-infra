# TravelBuddy — Infrastructure as Code (Azure + Terraform)

[![CI](https://github.com/hamiche-sirine/travelbuddy-infra/actions/workflows/ci.yml/badge.svg)](https://github.com/hamiche-sirine/travelbuddy-infra/actions/workflows/ci.yml)
[![CD](https://github.com/hamiche-sirine/travelbuddy-infra/actions/workflows/cd.yml/badge.svg)](https://github.com/hamiche-sirine/travelbuddy-infra/actions/workflows/cd.yml)
[![Terraform](https://img.shields.io/badge/Terraform-1.15.8-7B42BC?logo=terraform&logoColor=white)](https://developer.hashicorp.com/terraform)
[![azurerm](https://img.shields.io/badge/azurerm-~%3E%204.0-0078D4?logo=microsoftazure&logoColor=white)](https://registry.terraform.io/providers/hashicorp/azurerm/latest)

Ce dépôt contient **l'infrastructure**, et uniquement l'infrastructure, de l'application
[TravelBuddy](https://github.com/Thinhinane-AKRICHE/PA4IABD) — un assistant de voyage conversationnel
(agent LangGraph + RAG) développé dans le cadre du cursus 4A IABD de l'ESGI.

Le code applicatif vit dans un dépôt séparé. **Cette séparation est volontaire** : l'infrastructure et
l'application n'ont ni le même rythme de changement, ni le même périmètre de droits, ni les mêmes
relecteurs.

---

## Sommaire

- [Architecture déployée](#architecture-déployée)
- [Prérequis](#prérequis)
- [Amorçage du backend d'état](#amorçage-du-backend-détat)
- [Utilisation en local](#utilisation-en-local)
- [Structure du dépôt](#structure-du-dépôt)
- [Chaîne CI/CD](#chaîne-cicd)
- [Gestion des secrets](#gestion-des-secrets)
- [Décisions d'architecture](#décisions-darchitecture)
- [Contraintes de l'abonnement étudiant](#contraintes-de-labonnement-étudiant)
- [Limites connues](#limites-connues)
- [Règles d'équipe](#règles-déquipe)

---

## Architecture déployée

```
                        ┌──────────────────────────────┐
                        │   rg-tfstate  (hors Terraform)│
                        │   Storage Account + conteneur │
                        │   → travelbuddy.tfstate       │
                        └──────────────┬───────────────┘
                                       │ état verrouillé (lease blob)
                                       │
   ┌───────────────────────────────────┴──────────────────────────────────┐
   │                     rg-travelbuddy-dev  (Terraform)                   │
   │                                                                       │
   │   Container Registry ──── images ────► Container Apps Environment      │
   │        (ACR)                            ├── Container App backend :8000│
   │                                         └── Container App frontend:3000│
   │                                                    │                   │
   │   Key Vault ──── secrets ──────────────────────────┘                   │
   │        │                                                               │
   │   PostgreSQL Flexible Server ◄── chaîne de connexion                   │
   │                                                                        │
   │   Log Analytics Workspace ◄── journaux des deux applications           │
   └────────────────────────────────────────────────────────────────────────┘
```

| Ressource | Type Azure | Rôle |
|---|---|---|
| `acrtravelbuddydev` | Container Registry (Basic) | Stocke les images backend et frontend |
| `log-travelbuddy-dev` | Log Analytics Workspace | Collecte les journaux des conteneurs |
| `cae-travelbuddy-dev` | Container Apps Environment | Plan d'hébergement partagé |
| `ca-backend-travelbuddy-dev` | Container App | API FastAPI, port 8000 |
| `ca-frontend-travelbuddy-dev` | Container App | Interface Next.js, port 3000 |
| `psql-travelbuddy-dev` | PostgreSQL Flexible Server | Utilisateurs, profils, mémoire de l'agent |
| `kv-travelbuddy-<suffixe>` | Key Vault (RBAC) | 7 secrets applicatifs |

**Région : `swedencentral`** — imposée par une Azure Policy de l'abonnement (voir
[Contraintes](#contraintes-de-labonnement-étudiant)) et compatible RGPD.

> Le nom de domaine public des Container Apps (`<préfixe>.swedencentral.azurecontainerapps.io`)
> **change à chaque recréation de l'environnement**. Il n'est jamais écrit en dur : le code le
> référence via `azurerm_container_app_environment.main.default_domain` et le republie en sortie.

---

## Prérequis

| Outil | Version validée |
|---|---|
| Terraform | 1.15.8 |
| Azure CLI | 2.88.0 |
| Docker | 29.2.1 |

Un compte Azure disposant du rôle `Contributor` sur l'abonnement, plus — et ce point n'est pas
évident — les rôles de **plan de données** décrits dans [Décisions d'architecture](#décisions-darchitecture).

Fournisseurs de ressources à enregistrer une fois par abonnement :

```powershell
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.KeyVault
```

---

## Amorçage du backend d'état

L'état Terraform ne peut pas héberger le stockage de sa propre existence : il faut bien que le
conteneur de blobs existe *avant* le premier `init`. Ces trois ressources sont donc créées **à la
main, une seule fois**, dans un groupe distinct qui n'est jamais géré par Terraform.

```powershell
az group create --name rg-tfstate --location swedencentral

az storage account create `
  --name sttfstatetb0808 --resource-group rg-tfstate `
  --location swedencentral --sku Standard_LRS --kind StorageV2 `
  --min-tls-version TLS1_2 --allow-blob-public-access false

az storage container create `
  --name tfstate --account-name sttfstatetb0808 --auth-mode login
```

Protections activées sur le compte : TLS 1.2 minimum, accès anonyme désactivé, versioning des blobs,
suppression réversible pendant 7 jours.

Le rôle **`Storage Blob Data Contributor`** est indispensable en plus de `Contributor` — voir la note
sur le plan de contrôle et le plan de données.

---

## Utilisation en local

```powershell
cd travelbuddy-infra

terraform init
terraform fmt      # AVANT tout commit : la CI échoue sur `fmt -check`
terraform validate
terraform plan
terraform apply
```

Les valeurs propres à l'environnement (`subscription_id`, `backend_image`, `frontend_image`…) sont
passées par un fichier `terraform.tfvars` **non versionné**, ou par des variables d'environnement
`TF_VAR_*`.

Reconstruire et publier les images applicatives :

```powershell
az acr login --name acrtravelbuddydev
cd ..\PA4IABD
docker build -t acrtravelbuddydev.azurecr.io/travelbuddy-backend:v1 -f backend/Dockerfile ./backend
docker push acrtravelbuddydev.azurecr.io/travelbuddy-backend:v1
docker build -t acrtravelbuddydev.azurecr.io/travelbuddy-frontend:v1 -f frontend/Dockerfile ./frontend
docker push acrtravelbuddydev.azurecr.io/travelbuddy-frontend:v1
```

En fin de session, pour préserver le crédit étudiant :

```powershell
terraform destroy
```

---

## Structure du dépôt

```
travelbuddy-infra/
├── .github/workflows/
│   ├── ci.yml            Validation : fmt, init, validate, tfsec, plan -out, artefact
│   └── cd.yml            Déploiement : workflow_run + approbation + apply du tfplan
├── providers.tf          Providers azurerm / random, backend distant azurerm
├── variables.tf          Variables d'entrée (aucune valeur secrète)
├── main.tf               Groupe de ressources et étiquettes communes
├── registry.tf           Azure Container Registry
├── container-apps.tf     Log Analytics, environnement, deux applications, lectures Key Vault
├── database.tf           Serveur PostgreSQL, mot de passe généré, base, pare-feu
├── key-vault.tf          Key Vault en mode RBAC, suffixe aléatoire de nom
├── outputs.tf            acr_login_server, backend_url, frontend_url
└── .gitignore            *.tfstate, .terraform/, *.tfplan, *.tfvars
```

Le découpage par fichier n'a aucun effet technique — Terraform concatène tout le répertoire. Il sert
la lecture humaine et la revue de code.

---

## Chaîne CI/CD

### `ci.yml` — sur chaque *push* et chaque *pull request*

| Étape | Ce qu'elle vérifie |
|---|---|
| `terraform fmt -check` | La **forme** : indentation, alignement |
| `terraform init` | L'accès au backend distant et aux providers |
| `terraform validate` | Le **sens** : syntaxe, types, références existantes |
| `tfsec` | Les défauts de configuration de sécurité — **non bloquant** |
| `terraform plan -out=tfplan` | Calcule les changements et **publie le plan en artefact** |

Durée typique : environ 45 secondes.

### `cd.yml` — déclenché par la réussite de la CI

Le déclencheur est `workflow_run`, pas un `push` : la CD ne peut pas s'exécuter sur du code qui n'a
pas été validé. Elle télécharge l'artefact `tfplan`, s'arrête sur l'environnement GitHub
**`production`** protégé par *required reviewers*, puis exécute `terraform apply tfplan`.

**Pourquoi appliquer l'artefact et non recalculer un plan :** sans lui, le plan approuvé par le
relecteur ne serait pas nécessairement celui qui est exécuté. L'empreinte SHA-256 de l'artefact
garantit l'identité bit à bit entre ce qui a été lu et ce qui est appliqué.

> Corollaire : un `tfplan` vieillit. S'il est approuvé longtemps après son calcul et que
> l'infrastructure a bougé entre-temps, l'`apply` échoue — c'est un garde-fou, pas un défaut.

---

## Gestion des secrets

| Secret | Origine |
|---|---|
| `openai-api-key` | déposé manuellement |
| `geoapify-api-key` | déposé manuellement |
| `serpapi-api-key` | déposé manuellement |
| `mistral-api-key` | déposé manuellement |
| `restcountries-api-key` | déposé manuellement |
| `jwt-secret-key` | déposé manuellement |
| `postgres-admin-password` | **généré par Terraform** (`random_password`) |

Les six premiers sont lus par des blocs `data` : Terraform les consomme mais ne les possède pas.
Le septième est le cas inverse — personne, y compris nous, n'a jamais lu ce mot de passe.

Côté pipeline, l'authentification repose sur un **service principal** (`sp-travelbuddy-github`) dont
les identifiants sont stockés dans le secret GitHub `AZURE_CREDENTIALS`.

Redéposer un secret :

```powershell
az keyvault secret set --vault-name <nom-du-coffre> --name openai-api-key --value 'VALEUR'
```

---

## Décisions d'architecture

**L'état est amorcé manuellement et isolé.** Il ne peut pas se gérer lui-même, et le mettre dans le
groupe de ressources applicatif l'exposerait à la destruction de ce groupe. Cette décision a été
validée par l'incident : une suppression accidentelle de `rg-travelbuddy-dev` a détruit huit
ressources — le `rg-tfstate` était intact, et un seul `terraform apply` de dix minutes a tout
reconstruit.

**L'état ne rejoint jamais le dépôt.** Il contient des valeurs sensibles en clair. Il est partagé à
quatre, donc il réside dans un stockage central qui fournit un **verrouillage natif** — le backend
`azurerm` utilise le mécanisme de *lease* des blobs, là où le backend S3 d'AWS exige une table
DynamoDB dédiée.

**`use_azuread_auth = true`** sur le backend : l'authentification passe par l'identité Azure AD, ce
qui évite de faire circuler la clé d'accès du compte de stockage.

**Plan de contrôle ≠ plan de données.** Être `Contributor`, voire propriétaire, permet de créer un
Storage Account ou un Key Vault sans pour autant lire ce qu'ils contiennent. Il a fallu attribuer
explicitement `Storage Blob Data Contributor` et `Key Vault Secrets Officer`, à l'utilisateur comme
au service principal.

**Le graphe de dépendances remplace la séquence.** Aucun ordre de création n'est écrit : Terraform le
déduit des références entre blocs. Et un second `plan` retourne `No changes` — l'idempotence est la
différence de fond avec un script de déploiement impératif.

**Terraform n'est pas un concurrent d'ARM.** Il produit des appels à l'API Azure Resource Manager ;
c'est une couche d'abstraction au-dessus, multi-cloud et avec gestion d'état.

---

## Contraintes de l'abonnement étudiant

**Azure Policy `Allowed resource deployment regions`.** Seules `uaenorth`, `spaincentral`,
`polandcentral`, `swedencentral` et `norwayeast` sont autorisées ; `francecentral` et
`germanywestcentral` renvoient `RequestDisallowedByAzure`. La liste s'obtient par :

```powershell
az policy assignment list --query "[].parameters"
```

Détail instructif : la création du *groupe de ressources* passait, celle des *ressources* non. Un
groupe est un objet logique de gestion et échappe à cette policy.

**ACR Tasks indisponibles.** `az acr build` renvoie `TasksOperationsNotAllowed`. Les images sont donc
construites localement puis poussées avec `docker push`.

---

## Limites connues

- **`tfsec` signale que le Storage Account de l'état accepte toutes les adresses IP.** Assumé et
  documenté : les agents GitHub hébergés changent d'adresse à chaque exécution, un filtrage IP
  casserait le pipeline. La réponse de production serait un *private endpoint* avec un agent
  auto-hébergé.
- **Key Vault ne protège pas le state.** Une valeur lue depuis le coffre et injectée dans une
  ressource se retrouve en clair dans le fichier d'état. Key Vault protège le dépôt Git, le backend
  chiffré protège l'état — les deux sont nécessaires, aucun ne remplace l'autre.
- **Environnement unique (`dev`).** La variable `environment` existe et préfixe les noms, mais un
  second environnement demanderait des espaces de travail ou des répertoires distincts.
- **Authentification depuis l'interface frontend en cours d'investigation.** L'API répond
  correctement en direct (JWT valide) ; le parcours passant par le navigateur est en cours de
  diagnostic, piste principale : variable `NEXT_PUBLIC_API_URL` figée à la construction de l'image
  Next.js plutôt qu'injectée à l'exécution.

---

## Règles d'équipe

**Une seule personne exécute `terraform apply` à la fois.** Le verrou d'état le fait respecter
techniquement — une commande locale lancée pendant l'exécution du pipeline a été refusée, le journal
identifiant l'agent GitHub comme détenteur du verrou — mais la convention évite d'y arriver.

**`terraform fmt` avant chaque commit.** La CI échoue sinon dès la première étape.

**Aucune valeur sensible dans le dépôt.** `*.tfvars`, `*.tfstate`, `*.tfplan` et `.terraform/` sont
exclus par `.gitignore`.

---

## Équipe

Groupe 7 — ESGI 4A IABD

| Membre | |
|---|---|
| Sirine HAMICHE | |
| Khaoula CHETIOUI | |
| Thinhinane AKRICHE | |
| Aymen BOULAHIA | |
