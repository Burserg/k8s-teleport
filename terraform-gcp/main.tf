locals {
  controls = { for name, node in var.nodes : name => node if node.role == "control" }
  workers  = { for name, node in var.nodes : name => node if node.role == "worker" }
  jumps    = { for name, node in var.nodes : name => node if node.role == "jump" }

  jump_name = one(keys(local.jumps))
  ssh_keys  = join("\n", [for key in var.admin_ssh_public_keys : trimspace(key)])
  health_check_source_ranges = [
    "35.191.0.0/16",
    "209.85.204.0/22",
  ]
}

resource "google_compute_network" "lab" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "lab" {
  name                     = "${var.name_prefix}-subnet"
  region                   = var.region
  network                  = google_compute_network.lab.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
}

resource "google_compute_router" "nat" {
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.lab.id
}

resource "google_compute_router_nat" "lab" {
  name                               = "${var.name_prefix}-nat"
  router                             = google_compute_router.nat.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_address" "bastion" {
  name   = "${var.name_prefix}-bastion-ip"
  region = var.region
}

resource "google_compute_address" "gateway" {
  name   = "${var.name_prefix}-gateway-ip"
  region = var.region
}

resource "google_compute_disk" "etcd" {
  for_each = {
    for name, node in local.controls : name => node
    if node.etcd_disk_size_gb != null
  }

  name = "${var.name_prefix}-${each.key}-etcd"
  type = var.boot_disk_type
  zone = var.zone
  size = each.value.etcd_disk_size_gb
}

resource "google_compute_instance" "node" {
  for_each = var.nodes

  name           = "${var.name_prefix}-${each.key}"
  zone           = var.zone
  machine_type   = coalesce(each.value.machine_type, "custom-${each.value.cores}-${each.value.memory}")
  can_ip_forward = each.value.role == "jump" ? false : true
  tags = compact([
    "${var.name_prefix}-all",
    each.value.role == "jump" ? "${var.name_prefix}-bastion" : "${var.name_prefix}-cluster",
    each.value.role == "worker" ? "${var.name_prefix}-gateway" : "",
  ])

  boot_disk {
    initialize_params {
      image = var.source_image
      size  = coalesce(each.value.disk_size_gb, var.default_disk_size_gb)
      type  = var.boot_disk_type
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.lab.id

    dynamic "access_config" {
      for_each = each.value.role == "jump" ? [google_compute_address.bastion.address] : []
      content {
        nat_ip = access_config.value
      }
    }
  }

  dynamic "attached_disk" {
    for_each = each.value.role == "control" && each.value.etcd_disk_size_gb != null ? [google_compute_disk.etcd[each.key].id] : []
    content {
      source      = attached_disk.value
      device_name = "etcd"
      mode        = "READ_WRITE"
    }
  }

  metadata = {
    block-project-ssh-keys = "true"
    startup-script = templatefile("${path.module}/templates/startup-script.sh.tftpl", {
      ci_user             = var.ci_user
      ssh_authorized_keys = local.ssh_keys
    })
  }

  labels = {
    managed_by = "opentofu"
    role       = each.value.role
  }
}

resource "google_compute_instance_group" "gateway_workers" {
  name      = "${var.name_prefix}-gateway-workers"
  zone      = var.zone
  instances = [for name, instance in google_compute_instance.node : instance.self_link if var.nodes[name].role == "worker"]

  named_port {
    name = "https"
    port = 443
  }
}

resource "google_compute_region_health_check" "gateway" {
  name   = "${var.name_prefix}-gateway-https"
  region = var.region

  tcp_health_check {
    port = 443
  }
}

resource "google_compute_region_backend_service" "gateway" {
  name                  = "${var.name_prefix}-gateway"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  health_checks         = [google_compute_region_health_check.gateway.self_link]

  backend {
    group = google_compute_instance_group.gateway_workers.self_link
  }
}

resource "google_compute_forwarding_rule" "gateway" {
  name                  = "${var.name_prefix}-gateway"
  region                = var.region
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
  ports                 = ["80", "443"]
  ip_address            = google_compute_address.gateway.address
  backend_service       = google_compute_region_backend_service.gateway.self_link
}

resource "google_compute_firewall" "internal" {
  name          = "${var.name_prefix}-allow-internal"
  network       = google_compute_network.lab.id
  direction     = "INGRESS"
  source_ranges = [var.subnet_cidr]
  target_tags   = ["${var.name_prefix}-all"]

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }
}

resource "google_compute_firewall" "ssh_bastion" {
  name          = "${var.name_prefix}-allow-ssh-bastion"
  network       = google_compute_network.lab.id
  direction     = "INGRESS"
  source_ranges = var.allowed_admin_ssh_cidrs
  target_tags   = ["${var.name_prefix}-bastion"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "gateway_clients" {
  name          = "${var.name_prefix}-allow-gateway-clients"
  network       = google_compute_network.lab.id
  direction     = "INGRESS"
  source_ranges = var.allowed_web_cidrs
  target_tags   = ["${var.name_prefix}-gateway"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

resource "google_compute_firewall" "gateway_health_checks" {
  name          = "${var.name_prefix}-allow-gateway-health-checks"
  network       = google_compute_network.lab.id
  direction     = "INGRESS"
  source_ranges = local.health_check_source_ranges
  target_tags   = ["${var.name_prefix}-gateway"]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}
