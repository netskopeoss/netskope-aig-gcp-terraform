output "aig_load_balancer_ip" {
  description = "Public IP of the AI Gateway load balancer. Point the DNS record for aig_hostname here."
  value       = google_compute_global_address.aig.address
}

output "aig_url" {
  description = "HTTPS endpoint (self-signed certificate)."
  value       = "https://${google_compute_global_address.aig.address}"
}

output "aig_hostname" {
  description = "Hostname to enter in the portal registration (VM Onboarding > Deploy VM > Register VM)."
  value       = var.aig_hostname
}

output "aig_certificate_pem" {
  description = "Self-signed certificate. Import it into clients that need to trust the gateway."
  value       = tls_self_signed_cert.aig.cert_pem
}

output "aig_instance_group" {
  description = "Regional managed instance group name."
  value       = google_compute_region_instance_group_manager.aig.name
}

output "list_instances_command" {
  description = "Run this to find the AI Gateway instance names."
  value       = "gcloud compute instances list --project ${var.project_id} --filter=\"name~^${var.name_prefix}-aig\" --format=\"table(name,zone,status,networkInterfaces[0].networkIP)\""
}

output "ssh_command_template" {
  description = "Replace INSTANCE_NAME and ZONE with a row from list_instances_command. Connects as nsadmin through IAP."
  value       = "gcloud compute ssh nsadmin@INSTANCE_NAME --zone=ZONE --project=${var.project_id} --tunnel-through-iap"
}

output "network_name" {
  value = google_compute_network.aig.name
}
