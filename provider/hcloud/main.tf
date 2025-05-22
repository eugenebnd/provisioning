variable "token" {
  description = "Hetzner Cloud API token."
  type        = string
  sensitive   = true
}

variable "hosts" {
  description = "Number of server hosts to create."
  type        = number
  default     = 0
}

variable "hostname_format" {
  description = "Format string for generating hostnames (e.g., 'server-%d')."
  type        = string
}

variable "location" {
  description = "Location for the servers (e.g., 'nbg1', 'fsn1'). See Hetzner Cloud documentation for available locations."
  type        = string
}

variable "type" {
  description = "Server type for the hosts (e.g., 'cpx11', 'cax11', 'ccx13'). Includes standard, Arm-based (CAX), and dedicated vCPU (CCX) types."
  type        = string
}

variable "image" {
  description = "OS image for the servers (e.g., 'ubuntu-22.04', 'debian-11'). See Hetzner Cloud documentation for available images."
  type        = string
}

variable "ssh_keys" {
  description = "List of SSH key IDs or names to allow access to the servers."
  type        = list(string)
}

variable "apt_packages" {
  description = "List of additional apt packages to install on each server."
  type        = list(string)
  default     = []
}

variable "cluster_name" {
  description = "Name for the Kubernetes cluster, used for naming related resources like network and firewall."
  type        = string
  default     = "my-k8s-cluster"
}

variable "volume_size" {
  description = "Size of the data volume in GB for each server that has a volume."
  type        = number
  default     = 10
}

variable "volume_count_per_server" {
  description = "Number of data volumes to create and attach per server. Set to 0 to disable volume creation."
  type        = number
  default     = 0
}

variable "create_managed_firewall" {
  description = "Boolean flag to create a managed firewall for the cluster."
  type        = bool
  default     = true
}

variable "enable_api_load_balancer" {
  description = "Boolean flag to enable a load balancer for the Kubernetes API server (conceptual for now)."
  type        = bool
  default     = false
}

variable "api_lb_type" {
  description = "Type of load balancer for the API server (e.g., 'lb11')."
  type        = string
  default     = "lb11"
}

provider "hcloud" {
  token = var.token
}

resource "hcloud_server" "host" {
  name        = format(var.hostname_format, count.index + 1)
  location    = var.location
  image       = var.image
  server_type = var.type
  ssh_keys    = var.ssh_keys

  count = var.hosts

  connection {
    user    = "root"
    type    = "ssh"
    timeout = "2m"
    host    = self.ipv4_address
  }

  provisioner "remote-exec" {
    inline = [
      "while fuser /var/{lib/{dpkg,apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do sleep 1; done",
      "apt-get update",
      # Consider removing ufw if hcloud_firewall is comprehensive
      "apt-get install -yq ufw ${join(" ", var.apt_packages)}",
    ]
  }

  networks {
    network_id = hcloud_network.private_network.id
    ip         = cidrhost(hcloud_network_subnet.private_subnet.ip_range, count.index + 10) # Start IPs from .10 to avoid conflicts, ensure subnet is large enough
  }
  depends_on = [hcloud_network_subnet.private_subnet] # Ensure subnet is created before server tries to use it
}

# Private Network
resource "hcloud_network" "private_network" {
  name     = "${var.cluster_name}-network"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "private_subnet" {
  network_id   = hcloud_network.private_network.id
  type         = "cloud"
  network_zone = var.location # Assuming location is a valid network zone, e.g., "eu-central" from "fsn1-dc8"
  ip_range     = "10.0.1.0/24" # Example subnet, ensure it's within the network's ip_range
}

# Volume Provisioning
resource "hcloud_volume" "data_volume" {
  count    = var.volume_count_per_server > 0 ? var.hosts * var.volume_count_per_server : 0
  name     = format("${var.cluster_name}-data-vol-%03d", count.index + 1)
  size     = var.volume_size
  location = var.location // Volumes must be in the same location as the server
  automount = false
  format    = "ext4" // Specify a filesystem format
}

resource "hcloud_volume_attachment" "volume_attachment" {
  count     = var.volume_count_per_server > 0 ? var.hosts * var.volume_count_per_server : 0
  volume_id = hcloud_volume.data_volume[count.index].id
  server_id = hcloud_server.host[floor(count.index / var.volume_count_per_server)].id
}

# Managed Firewall
resource "hcloud_firewall" "cluster_firewall" {
  count = var.create_managed_firewall ? 1 : 0
  name  = "${var.cluster_name}-firewall"

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22" # SSH
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
  # Placeholder for additional K8s rules
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "6443" # Kubernetes API
    source_ips = [
      "0.0.0.0/0", # For simplicity now, should be restricted
      "::/0"
    ]
  }
  # Example etcd rules (if etcd is on master nodes and accessed by workers)
  # rule {
  #   direction = "in"
  #   protocol  = "tcp"
  #   port      = "2379-2380" # etcd client and peer ports
  #   source_ips = [ hcloud_network.private_network.ip_range ] # Restrict to private network
  # }

  # Allow all outbound traffic by default
  rule {
    direction = "out"
    protocol  = "tcp"
    port      = "any"
    destination_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
  rule {
    direction = "out"
    protocol  = "udp"
    port      = "any"
    destination_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
  rule {
    direction = "out"
    protocol  = "icmp"
    destination_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}

resource "hcloud_firewall_attachment" "firewall_attachment" {
  count       = var.create_managed_firewall ? var.hosts : 0
  firewall_id = hcloud_firewall.cluster_firewall[0].id
  server_ids  = [hcloud_server.host[count.index].id]
}

# Load Balancer & Floating IPs (Placeholders)
# resource "hcloud_load_balancer" "api_lb" {
#   count              = var.enable_api_load_balancer ? 1 : 0
#   name               = "${var.cluster_name}-api-lb"
#   load_balancer_type = var.api_lb_type
#   location           = var.location
#   # network_zone    = var.location # If using a network zone compatible LB type
# }

# resource "hcloud_floating_ip" "api_lb_fip" {
#   count = var.enable_api_load_balancer ? 1 : 0
#   type  = "ipv4"
#   # home_location = var.location # Optional: specify home location for the FIP
#   description   = "${var.cluster_name} API Load Balancer FIP"
# }

# resource "hcloud_floating_ip_assignment" "api_lb_fip_assignment" {
#   count          = var.enable_api_load_balancer ? 1 : 0
#   floating_ip_id = hcloud_floating_ip.api_lb_fip[0].id
#   server_id      = hcloud_load_balancer.api_lb[0].id # Assign FIP to Load Balancer
# }

# resource "hcloud_load_balancer_network" "api_lb_network_attachment" {
#   count            = var.enable_api_load_balancer ? 1 : 0
#   load_balancer_id = hcloud_load_balancer.api_lb[0].id
#   network_id       = hcloud_network.private_network.id
#   # ip               = "10.0.0.X" # Specify an IP for the LB in the private network
# }

# resource "hcloud_load_balancer_service" "api_lb_service" {
#   count            = var.enable_api_load_balancer ? 1 : 0
#   load_balancer_id = hcloud_load_balancer.api_lb[0].id
#   protocol         = "tcp"
#   listen_port      = 6443
#   destination_port = 6443
#   # health_check_http { ... } # Define health checks
# }

# resource "hcloud_load_balancer_target" "api_lb_target" {
#   count            = var.enable_api_load_balancer ? var.hosts : 0 # Assuming all hosts are API servers for now
#   load_balancer_id = hcloud_load_balancer.api_lb[0].id
#   type             = "server"
#   server_id        = hcloud_server.host[count.index].id
#   use_private_ip   = true # Target servers via their private IP
#   # depends_on       = [hcloud_load_balancer_network.api_lb_network_attachment]
# }


output "hostnames" {
  value = hcloud_server.host.*.name
}

output "public_ips" {
  value = hcloud_server.host.*.ipv4_address
}

output "private_ips" {
  description = "Private IP addresses of the servers in the cluster network."
  value       = hcloud_server.host[*].network[0].ip // Assuming the first network interface is the private one we attached.
}

output "private_network_interface" {
  description = "The network interface used for private networking. This might be static or dynamic."
  value       = "eth0" # This is a guess, may need to be derived or removed
}

output "network_id" {
  description = "ID of the private network."
  value       = hcloud_network.private_network.id
}

output "firewall_id" {
  description = "ID of the managed firewall (if created)."
  value       = var.create_managed_firewall ? hcloud_firewall.cluster_firewall[0].id : null
}
