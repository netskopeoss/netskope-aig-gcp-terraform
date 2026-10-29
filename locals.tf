locals {
  labels = {
    owner        = var.owner
    project_type = var.project_type
    cost_center  = var.cost_center
    stage        = var.stage
    sensitivity  = var.sensitivity
    managed_by   = "terraform"
  }
}
