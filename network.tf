# VPC with one private subnet for AI Gateway instances (no external IPs), a
# proxy-only subnet required by the global external Application Load Balancer,
# Cloud NAT for outbound traffic to Netskope and LLM providers, and firewall rules.

resource "google_compute_network" "aig" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "private" {
  name                     = "${var.name_prefix}-private"
  region                   = var.region
  network                  = google_compute_network.aig.id
  ip_cidr_range            = "10.10.0.0/24"
  private_ip_google_access = true
}

# Required by the global external Application Load Balancer (Envoy proxies run here).
resource "google_compute_subnetwork" "proxy_only" {
  name          = "${var.name_prefix}-proxy-only"
  region        = var.region
  network       = google_compute_network.aig.id
  ip_cidr_range = "10.10.2.0/23"
  purpose       = "GLOBAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

resource "google_compute_router" "nat" {
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.aig.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.name_prefix}-nat"
  router                             = google_compute_router.nat.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Load balancer health checks and client traffic from Google's front ends and the
# proxy-only subnet. Only instances tagged aig-gateway are reachable.
resource "google_compute_firewall" "lb_to_aig" {
  name    = "${var.name_prefix}-allow-lb-to-aig"
  network = google_compute_network.aig.name

  direction     = "INGRESS"
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16", google_compute_subnetwork.proxy_only.ip_cidr_range]
  target_tags   = ["aig-gateway"]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

# SSH only through Identity-Aware Proxy, so instances never need a public IP.
# Used for the manual AIG-CLI enrollment step.
resource "google_compute_firewall" "iap_ssh" {
  name    = "${var.name_prefix}-allow-iap-ssh"
  network = google_compute_network.aig.name

  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["aig-gateway"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
