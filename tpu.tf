# TPU AI Guardrails tier (Vertex AI endpoint on TPU v5e, fronted by Cloud Run and API Gateway).
#
# Everything here is gated by enable_tpu_tier (default false), so the GPU-free AI Gateway
# stack in the other files plans exactly as before until you turn it on.
#
# Steps this file cannot do (no Terraform resource in the google provider 6.50):
#   - Uploading the model: gcloud ai models upload (done; model id goes in tpu_model_id)
#   - Deploying the model to the endpoint: the deployed_models attribute is computed
#     (output only), so use gcloud ai endpoints deploy-model (see outputs)
#   - Creating the API Gateway: no google_api_gateway_* resources. Use gcloud (see outputs)
#   - Pushing the container image to Artifact Registry: docker/crane push (see README)

variable "enable_tpu_tier" {
  description = "Create the TPU guardrails resources. Leave false until the TPU quota is approved and the image is pushed."
  type        = bool
  default     = false
}

variable "tpu_model_id" {
  description = "Numeric model id from gcloud ai models list (the aisecurity-llm model uploaded to Vertex AI). Used only in output commands."
  type        = string
  default     = ""
}

variable "tpu_proxy_image" {
  description = "Container image for the Cloud Run proxy. The guide does not name one. Leave empty to skip the proxy."
  type        = string
  default     = ""
}

variable "tpu_quota_id" {
  description = "Quota id of 'Custom model serving TPU V5e cores per region' (Agent Platform API). Read it from the quota details panel in the console."
  type        = string
  default     = ""
}

variable "tpu_quota_preferred_cores" {
  description = "Requested TPU v5e cores in the region. One ct5lp-hightpu-1t replica uses 1 core."
  type        = number
  default     = 8
}

variable "tpu_quota_contact_email" {
  description = "Contact email Google uses for the quota request. Required; no default, so it is not stored in the repo."
  type        = string
  default     = ""
}

variable "tpu_quota_justification" {
  description = "Justification text for the quota request."
  type        = string
  default     = "Deployment of AI Guardrails on Vertex AI TPU v5e in us-east1: one endpoint replica."
}

locals {
  tpu_enabled       = var.enable_tpu_tier ? 1 : 0
  tpu_proxy_enabled = var.enable_tpu_tier && var.tpu_proxy_image != "" ? 1 : 0
  tpu_quota_enabled = var.enable_tpu_tier && var.tpu_quota_id != "" && var.tpu_quota_contact_email != "" ? 1 : 0
}

# ---------------------------------------------------------------- APIs

resource "google_project_service" "tpu" {
  for_each = var.enable_tpu_tier ? toset([
    "aiplatform.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "apigateway.googleapis.com",
    "servicemanagement.googleapis.com",
    "servicecontrol.googleapis.com",
    "cloudquotas.googleapis.com",
  ]) : toset([])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------- Container registry

resource "google_artifact_registry_repository" "tpu" {
  count         = local.tpu_enabled
  location      = var.region
  repository_id = "aisecurity-tpu"
  format        = "DOCKER"
  description   = "AI Guardrails TPU container images"

  depends_on = [google_project_service.tpu]
}

# ---------------------------------------------------------------- Identities

resource "google_service_account" "tpu_proxy" {
  count        = local.tpu_proxy_enabled
  account_id   = "aisecurity-tpu-proxy"
  display_name = "AI Guardrails TPU proxy (Cloud Run)"

  depends_on = [google_project_service.tpu]
}

resource "google_project_iam_member" "tpu_proxy_aiplatform" {
  count   = local.tpu_proxy_enabled
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.tpu_proxy[0].email}"
}

resource "google_service_account" "tpu_gateway_identity" {
  count        = local.tpu_proxy_enabled
  account_id   = "aisecurity-gateway-identity"
  display_name = "AI Gateway identity that calls the TPU proxy"

  depends_on = [google_project_service.tpu]
}

# Only the gateway identity may invoke the proxy. The proxy is not publicly reachable.
resource "google_cloud_run_v2_service_iam_member" "tpu_proxy_invoker" {
  count    = local.tpu_proxy_enabled
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.tpu_proxy[0].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.tpu_gateway_identity[0].email}"
}

# ---------------------------------------------------------------- Vertex AI endpoint

resource "google_vertex_ai_endpoint" "tpu" {
  count        = local.tpu_enabled
  project      = var.project_id
  name         = "aisecurity-tpu-endpoint"
  location     = var.region
  display_name = "aisecurity-tpu-endpoint"
  description  = "AI Guardrails on TPU v5e. Model is deployed with gcloud (see outputs)."

  depends_on = [google_project_service.tpu]
}

# ---------------------------------------------------------------- Cloud Run proxy

resource "google_cloud_run_v2_service" "tpu_proxy" {
  count    = local.tpu_proxy_enabled
  name     = "aisecurity-tpu-proxy"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  deletion_protection = false

  template {
    service_account = google_service_account.tpu_proxy[0].email

    containers {
      image = var.tpu_proxy_image

      env {
        name  = "ENDPOINT_ID"
        value = element(split("/", google_vertex_ai_endpoint.tpu[0].id), 5)
      }

      env {
        name  = "LOCATION"
        value = var.region
      }
    }
  }

  depends_on = [google_project_service.tpu]
}

# ---------------------------------------------------------------- Quota request

# Submits the TPU v5e quota increase. Google decides whether to approve it, and that can
# take days, so this resource stays off until tpu_quota_id and tpu_quota_contact_email are set.
resource "google_cloud_quotas_quota_preference" "tpu_v5e" {
  count    = local.tpu_quota_enabled
  parent   = "projects/${var.project_id}"
  service  = "aiplatform.googleapis.com"
  quota_id = var.tpu_quota_id

  dimensions = {
    location = var.region
  }

  quota_config {
    preferred_value = var.tpu_quota_preferred_cores
  }

  contact_email = var.tpu_quota_contact_email
  justification = var.tpu_quota_justification

  depends_on = [google_project_service.tpu]
}

# ---------------------------------------------------------------- Manual steps (gcloud)

output "tpu_endpoint_name" {
  description = "Full resource name of the Vertex AI endpoint (empty until enable_tpu_tier = true)."
  value       = one(google_vertex_ai_endpoint.tpu[*].id)
}

output "tpu_deploy_model_command" {
  description = "Run after the TPU quota is approved. Deploys the uploaded model to the endpoint."
  value       = var.tpu_model_id == "" ? "Set tpu_model_id first (gcloud ai models list --region=${var.region})." : "gcloud ai endpoints deploy-model ENDPOINT_ID --region=${var.region} --model=${var.tpu_model_id} --display-name=aisecurity-tpu --machine-type=ct5lp-hightpu-1t --min-replica-count=1 --max-replica-count=1 --project=${var.project_id}"
}

output "tpu_api_gateway_note" {
  description = "API Gateway has no Terraform resource in this provider. Create it with gcloud after the proxy exists."
  value       = "gcloud api-gateway apis create aisecurity-tpu-api --project=${var.project_id}   # then api-configs create (openapi.yaml) and gateways create. See README."
}
