# AI Gateway tier: service account, instance template, regional managed instance
# group (2 zones, as in the AWS reference), autoscaler (scale-out only), health
# check, and a global external Application Load Balancer on 443.

resource "google_service_account" "aig" {
  account_id   = "${var.name_prefix}-aig"
  display_name = "AI Gateway instances (${var.name_prefix})"
}

resource "google_project_iam_member" "aig_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.aig.email}"
}

resource "google_project_iam_member" "aig_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.aig.email}"
}

resource "google_compute_health_check" "aig" {
  name                = "${var.name_prefix}-aig-hc"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  # TCP, not HTTPS: the gateway returns 401 on every path without credentials,
  # and GCP only counts HTTP 200 as healthy, so an HTTPS check can never pass.
  tcp_health_check {
    port = 443
  }
}

resource "google_compute_instance_template" "aig" {
  name_prefix  = "${var.name_prefix}-aig-"
  machine_type = var.machine_type
  tags         = ["aig-gateway"]

  disk {
    source_image = var.aig_image
    disk_size_gb = var.boot_disk_size_gb
    disk_type    = var.boot_disk_type
    boot         = true
    auto_delete  = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    # No access_config block: the instance has no external IP.
  }

  service_account {
    email  = google_service_account.aig.email
    scopes = ["cloud-platform"]
  }

  # OS Login off and SSH keys in metadata, as the Netskope GCP instructions
  # require for nsadmin (AIG-CLI) and nsdebug (debug bundles).
  metadata = {
    "enable-oslogin"         = "FALSE"
    "block-project-ssh-keys" = "TRUE"
    "ssh-keys"               = "nsadmin:${var.ssh_public_key}\nnsdebug:${var.ssh_public_key}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_instance_group_manager" "aig" {
  name               = "${var.name_prefix}-aig-mig"
  base_instance_name = "${var.name_prefix}-aig"
  region             = var.region

  distribution_policy_zones = var.zones
  target_size               = var.desired_capacity

  version {
    instance_template = google_compute_instance_template.aig.id
  }

  named_port {
    name = "https"
    port = 443
  }

  # Long delay: a new VM is unenrolled until the manual AIG-CLI enrollment and
  # certificate steps are done, and a repair recreates the VM and loses both.
  auto_healing_policies {
    health_check      = google_compute_health_check.aig.id
    initial_delay_sec = 1800
  }

  # Template changes do not roll instances automatically (matches the AWS reference,
  # which has no UpdatePolicy). Replacements pick up the new template.
  update_policy {
    type                  = "OPPORTUNISTIC"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 0
    max_unavailable_fixed = 1
  }

  lifecycle {
    ignore_changes = [target_size]
  }
}

resource "google_compute_region_autoscaler" "aig" {
  name   = "${var.name_prefix}-aig-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.aig.id

  autoscaling_policy {
    min_replicas    = 1
    max_replicas    = var.max_capacity
    cooldown_period = 600
    mode            = "ONLY_SCALE_OUT"

    cpu_utilization {
      target = var.cpu_scale_out_threshold / 100
    }
  }
}

resource "google_compute_backend_service" "aig" {
  name                  = "${var.name_prefix}-aig-backend"
  protocol              = "HTTPS"
  port_name             = "https"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks         = [google_compute_health_check.aig.id]

  backend {
    group           = google_compute_region_instance_group_manager.aig.instance_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }
}

resource "google_compute_url_map" "aig" {
  name            = "${var.name_prefix}-aig-urlmap"
  default_service = google_compute_backend_service.aig.id
}

resource "google_compute_target_https_proxy" "aig" {
  name             = "${var.name_prefix}-aig-https-proxy"
  url_map          = google_compute_url_map.aig.id
  ssl_certificates = [google_compute_ssl_certificate.aig.id]
}

resource "google_compute_global_address" "aig" {
  name = "${var.name_prefix}-aig-ip"
}

resource "google_compute_global_forwarding_rule" "aig" {
  name                  = "${var.name_prefix}-aig-https"
  ip_protocol           = "TCP"
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.aig.address
  target                = google_compute_target_https_proxy.aig.id
}
