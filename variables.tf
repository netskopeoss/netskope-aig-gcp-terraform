variable "project_id" {
  description = "GCP project to deploy into. Required."
  type        = string
}

variable "region" {
  description = "GCP region for all regional resources."
  type        = string
  default     = "us-east1"
}

variable "zones" {
  description = "Zones the AI Gateway managed instance group spans. Both zones must exist in var.region."
  type        = list(string)
  default     = ["us-east1-b", "us-east1-c"]
}

variable "name_prefix" {
  description = "Prefix for every resource name. Keep it short (lowercase letters, digits, dashes)."
  type        = string
  default     = "aigw"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,20}$", var.name_prefix))
    error_message = "name_prefix must start with a letter and contain only lowercase letters, digits, and dashes (max 21 characters)."
  }
}

variable "aig_image" {
  description = <<-EOT
    Self link of the AI Gateway boot image, for example
    projects/<image-project>/global/images/ai-gateway-v1-9-63. Set it to the project that
    holds the image you can see, or to the Marketplace image you subscribed to.
  EOT
  type        = string
  default     = "projects/your-image-project-id/global/images/ai-gateway-v1-9-63"
}

variable "machine_type" {
  description = "Machine type for AI Gateway instances. n2-standard-16 matches the AWS m5.4xlarge (16 vCPU / 64 GB)."
  type        = string
  default     = "n2-standard-16"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB. The AWS reference used 400 GB."
  type        = number
  default     = 400
}

variable "boot_disk_type" {
  description = "Boot disk type. pd-balanced is the closest match to the AWS gp3 volume."
  type        = string
  default     = "pd-balanced"
}

variable "desired_capacity" {
  description = "Desired AI Gateway instances at deploy time (1-4). The autoscaler takes over after that."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_capacity >= 1 && var.desired_capacity <= 4
    error_message = "desired_capacity must be between 1 and 4."
  }
}

variable "max_capacity" {
  description = "Maximum AI Gateway instances (the minimum is fixed at 1, as in the AWS reference)."
  type        = number
  default     = 4
}

variable "cpu_scale_out_threshold" {
  description = "Average CPU percentage that adds an AI Gateway instance. Scale-out only (ONLY_SCALE_OUT), as in the AWS reference."
  type        = number
  default     = 70

  validation {
    condition     = var.cpu_scale_out_threshold >= 1 && var.cpu_scale_out_threshold <= 100
    error_message = "cpu_scale_out_threshold must be between 1 and 100."
  }
}

variable "aig_hostname" {
  description = <<-EOT
    Hostname for the AI Gateway. The same name is used in the portal registration token
    (VM Onboarding > Deploy VM > Register VM) and in the self-signed certificate CN/SAN.
    It must resolve to the load balancer IP for clients. The default is a placeholder.
  EOT
  type        = string
  default     = "aig.aigw.internal"
}

variable "ssh_public_key" {
  description = "SSH public key (one line, e.g. 'ssh-ed25519 AAAA... you@host'). Installed for both nsadmin (AIG-CLI) and nsdebug (debug bundles)."
  type        = string

  validation {
    condition     = can(regex("^ssh-(rsa|ed25519|ecdsa)", var.ssh_public_key))
    error_message = "ssh_public_key must be a single OpenSSH public key line starting with ssh-rsa, ssh-ed25519, or ecdsa."
  }
}

# ── Labels (from Tags.json). GCP label values allow only lowercase letters,
# digits, dashes, and underscores, so the original values are mapped here.

variable "owner" {
  description = "Label: owner. Use your username. Label values allow only lowercase letters, digits, dashes, and underscores."
  type        = string
  default     = "your-username"

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,63}$", var.owner))
    error_message = "Label values may only contain lowercase letters, digits, dashes, and underscores."
  }
}

variable "project_type" {
  description = "Label: project_type."
  type        = string
  default     = "dati"
}

variable "cost_center" {
  description = "Label: cost_center. Original value 'bd-15.1' is not a valid label value (no dots)."
  type        = string
  default     = "bd-15-1"

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,63}$", var.cost_center))
    error_message = "Label values may only contain lowercase letters, digits, dashes, and underscores."
  }
}

variable "stage" {
  description = "Label: stage."
  type        = string
  default     = "prod"
}

variable "sensitivity" {
  description = "Label: sensitivity."
  type        = string
  default     = "none"
}
