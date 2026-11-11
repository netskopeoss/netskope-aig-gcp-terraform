# Netskope AI Gateway on GCP: lab deployment (Terraform)

This Terraform deploys a Netskope AI Gateway (AIG) on Google Cloud for lab use. It creates a
VPC, a managed instance group of AI Gateway VMs with no external IPs, a global external HTTPS
load balancer, and an autoscaler that only scales out. Enrollment is a manual step with
AIG-CLI, as in the AWS reference.

Not included yet: DLP On Demand (waiting on the GCP image) and the optional TPU tier.

> **Lab only.** The self-signed certificate, the placeholder hostname, and the defaults are for
> testing. Run `terraform destroy` when you finish.

## What gets created

| Resource | Purpose |
|---|---|
| VPC, private subnet (10.10.0.0/24) | Holds the AI Gateway VMs. Private Google Access on. |
| Proxy-only subnet (10.10.2.0/23) | Required by the global external Application LB. |
| Cloud Router + Cloud NAT | Outbound access to Netskope and LLM providers. |
| Firewall rules | LB and health checks to tcp/443 on `aig-gateway` tagged VMs. IAP SSH to tcp/22. |
| Service account `aigw-lab-aig` | Logging and metrics writer only. |
| Instance template + regional MIG | `n2-standard-16`, 400 GB pd-balanced boot disk, two zones. |
| Autoscaler | Min 1, max 4, CPU target 70%, scale-out only (`ONLY_SCALE_OUT`). |
| HTTPS health check | `GET /` on 443, healthy on HTTP 200 only. Auto-heal enabled. |
| Global LB | Static IP, self-signed certificate, HTTPS forwarding rule on 443. |

## Prerequisites

- [ ] Terraform 1.5 or later (tested with 1.14.8)
- [ ] Google Cloud CLI (`gcloud`) signed in as an account with Owner or Editor on the project
- [ ] Application Default Credentials for Terraform (see step 2 below)
- [ ] Access to the AI Gateway image in the project (`ai-gateway-v1-9-63` by default)
- [ ] A Netskope tenant admin login (for the registration token)
- [ ] An SSH key pair (`ssh-keygen -t ed25519`)

### APIs

The following APIs must be enabled on the project. Run this once on a new project:

```bash
gcloud services enable compute.googleapis.com iam.googleapis.com logging.googleapis.com monitoring.googleapis.com cloudresourcemanager.googleapis.com --project=your-project-id
```

No other APIs are required for the AI Gateway tier. Secret Manager, Cloud Functions, and Eventarc
are not used here, because enrollment is manual.

## Deploy

### 1. Configure variables

```bash
cd aig-gcp-lab
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`. Set `ssh_public_key` to one line of your public key. Keep the defaults
unless you have a reason to change them.

### 2. Authenticate for Terraform

```bash
gcloud auth application-default login
gcloud config set project your-project-id
```

### 3. Initialize and plan

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
```

Review the plan. On a first apply it should show only additions, with 0 to change and 0 to destroy.

### 4. Apply

```bash
terraform apply
```

The instance group and load balancer can take several minutes to settle. Backend health may stay
failed until enrollment finishes. That is not verified yet, so check the health status after
enrollment if it stays unhealthy.

## Enroll the gateway (manual, AIG-CLI)

Enrollment has two parts: a registration token from the Netskope portal, then the AI Gateway
Configuration Wizard on the VM. The token expires 24 hours after it is generated, so generate it
just before you start.

### a. Generate the registration token in the portal

1. Sign in to your Netskope tenant.
2. Go to **Settings > Security Cloud Platform > VM Onboarding**.
3. Click **Deploy VM**, then **Register VM**.
4. **Step 1 (Configure):** set **VM Name (AI Gateway)** to `aigw-lab`. Set **Hostname** to the
   value of `aig_hostname` in `terraform.tfvars` (default `aig.aigw.internal`). Choose the
   HTTPS and HTTP protocol and port settings.
5. Click **Continue**. In **Step 2 (Register)**, click **Copy** or **Download** to save the
   token.
6. Click **Finish**.

### b. Point the hostname at the load balancer (for clients)

```bash
terraform output aig_load_balancer_ip
```

Create a DNS A record for `aig_hostname` that points to that IP. For a quick lab test without
DNS, add a line to your hosts file. Clients must trust the self-signed certificate
(`terraform output -raw aig_certificate_pem`) or skip verification.

### c. Open an SSH session to the gateway

```bash
terraform output list_instances_command
```

Run the printed command, then SSH using the INSTANCE_NAME and ZONE it lists:

```bash
gcloud compute ssh nsadmin@INSTANCE_NAME --zone=ZONE --project=your-project-id --tunnel-through-iap
```

Running `ssh` with no command opens the interactive AIG-CLI console.

### d. Configure networking, then enroll

1. Open the **AI Gateway Configuration Wizard** from the CLI. The docs do not show the exact
   command, so confirm it on first login.
2. Select **Network Configuration**. The Netskope docs say CLI network configuration is
   supported only on ESXi, so on GCP leave DHCP in place and check that the wizard lets you
   continue.
3. Select **Enroll this AI Gateway**. Pre-enrollment takes a few minutes.
4. When prompted, paste the registration token on the **AI Gateway Enrollment** page.
5. The CLI shows the enrollment status and the **Gateway ID**. Note the Gateway ID.

### e. Confirm enrollment

- In the CLI, check that enrollment succeeded.
- In the portal, go to **Settings > Security Cloud Platform > VM Onboarding**. A green icon
  next to `aigw-lab` means registration succeeded.
- Once the wizard finishes, check the load balancer: `terraform output aig_url`, then check that
  `https://<aig_load_balancer_ip>/` responds. Expect HTTP 200 for the health check to pass.

### Scaling

The autoscaler adds instances when average CPU is above 70% for the cooldown window. Each new
instance needs its own registration token and manual enrollment, as above. There is no automatic
scale-in.

## Teardown

```bash
terraform destroy
```

This deletes everything Terraform created. Afterwards, check **VM Onboarding** in the portal and
remove the `aigw-lab` entry if it remains. The docs do not say whether it is removed
automatically.

## Known gaps and risks

- **TCP health check.** GCP accepts only HTTP 200, and AIG returns 401 on every path without
  credentials, so an HTTPS check can never pass. The health check is TCP on 443. It proves the
  port is open, not that the gateway is enrolled or working.
- **Autohealing recreates unenrolled VMs.** A repair rebuilds the VM from the image and loses the
  enrollment and the portal SSL certificate. A new VM must be enrolled and have its certificate
  installed within the 1800 second initial delay, or it is recreated.
- **Portal SSL certificate step.** After enrollment, VM Onboarding shows "Create certificate to
  finish setup". Sign the CSR from the AIG-CLI certificate wizard and install the certificate, or
  the gateway does not serve traffic.
- **Self-signed certificate.** Good for a lab only.
- **Image choice.** The default `aig_image` is a placeholder (`your-image-project-id`). Set it to
  the project and image you can see, for example `ai-gateway-v1-9-63`, and confirm it matches the
  Marketplace listing you subscribed to.
- **No automatic enrollment.** The AWS reference automates enrollment through Secrets Manager. The
  GCP docs describe only manual enrollment, so this template does too.
- **Update policy.** Changing the template does not roll existing instances, matching the AWS
  reference. Replacements pick up the new template.

## Files

| File | Contents |
|---|---|
| `versions.tf` | Terraform and provider versions |
| `providers.tf` | Google provider, default labels |
| `variables.tf` | All inputs with defaults and validation |
| `locals.tf` | Label map (from Tags.json) |
| `network.tf` | VPC, subnets, NAT, firewall rules |
| `certificate.tf` | Self-signed certificate for the load balancer |
| `gateway.tf` | Service account, instance template, MIG, autoscaler, load balancer |
| `outputs.tf` | IP, URL, certificate, and helper commands |
| `terraform.tfvars.example` | Template for your variables |
