# Self-signed certificate for the AI Gateway load balancer. Browsers and
# API clients must trust this certificate or skip verification. For a real
# deployment, replace this with a Certificate Manager certificate.

resource "tls_private_key" "aig" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "aig" {
  private_key_pem = tls_private_key.aig.private_key_pem

  subject {
    common_name  = var.aig_hostname
    organization = "Netskope"
  }

  dns_names             = [var.aig_hostname]
  validity_period_hours = 8760
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

resource "google_compute_ssl_certificate" "aig" {
  name_prefix = "${var.name_prefix}-cert-"
  certificate = tls_self_signed_cert.aig.cert_pem
  private_key = tls_private_key.aig.private_key_pem

  lifecycle {
    create_before_destroy = true
  }
}
