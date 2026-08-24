# Libvirt Map

This describes the current libvirt deployment.

```mermaid
flowchart LR
    UserRequest["External User\nWeb browser"]
    CloudflareDNS["Cloudflare\nDNS / edge proxy"]
    TunnelUser["External User\nTunnel route"]
    TunnelCloudflare["Cloudflare\nTunnel edge"]
    cloudflared["cloudflared\nTunnel connector"]
    gatewayTunnel["Cilium Gateway Tunnel\nEnvoy origin\nHTTPS 443"]
    Firewall["Unifi Cloud Gateway\nFirewall / router"]
    admin["Administrator workstation"]
    hypervisor["Arch libvirt host\n192.168.88.210\nqemu+ssh transport"]
    bridge["Linux bridge: br-vlan2"]
    lan["VLAN 2 / L2 network\n192.168.2.0/24\nGateway and DNS: 192.168.2.1"]

    jump["jump-01\n192.168.2.20\nAnsible control host"]
    control["ctrl-01\n192.168.2.21\nKubeadm control plane\nAPI: 6443"]
    worker1["wrkr-01\n192.168.2.31\nKubernetes worker"]
    worker2["wrkr-02\n192.168.2.32\nKubernetes worker"]

    pool["Cilium LB IPAM pool\n192.168.2.70–192.168.2.127"]
    gateway["Cilium Gateway / Envoy\nVIP: 192.168.2.71\nHTTP 80 / HTTPS 443"]
    teleport["Teleport LoadBalancer\nVIP: 192.168.2.72"]
    app["cheesecake namespace\nHTTPRoute → Service → Pods"]

    
    admin -->|"SSH, OpenTofu uses qemu+ssh"| hypervisor
    admin -->|"SSH / Ansible"| jump
    UserRequest -->|"HTTPS request"| CloudflareDNS
    CloudflareDNS -->|"HTTPS for teleporthome.devbycory.com"| Firewall
    Firewall -->|"TCP 443 to 192.168.2.72"| teleport
    TunnelUser -->|"HTTPS request"| TunnelCloudflare
    TunnelCloudflare <-->|"outbound tunnel"| cloudflared
    cloudflared -->|"HTTPS origin"| gatewayTunnel
    gatewayTunnel --> gateway
    hypervisor --- bridge
    bridge --- lan

    lan --- jump
    lan --- control
    lan --- worker1
    lan --- worker2

    control -->|"kubeadm API, Cilium control plane"| worker1
    control -->|"kubeadm API, Cilium control plane"| worker2

    pool --> gateway
    pool --> teleport
    worker1 -.->|"L2 lease\n(gARP)"| gateway
    worker2 -.->|"L2 lease\n(gARP)"| gateway
    gateway --> app
    lan --> teleport
```

## Network facts

Each VM has one virtio NIC on `br-vlan2`. Cloud-init gives it a static
`192.168.2.x/24` address, default route, DNS server, and `lab.local` search
domain. These VMs and the Cilium VIPs sit on the physical VLAN, not libvirt
NAT on `virbr0`.

The L2 announcement policy leaves out the control-plane node. A worker
advertises each LoadBalancer IP, and the other worker can take over the lease.
The DHCP range excludes `192.168.2.70` through `.127`. `.71` is for the HTTPS
Gateway and `.72` is for Teleport.

The tunnel path is optional. `cloudflared` opens an outbound connection to
Cloudflare, which forwards the application request to the Cilium Gateway
origin. It avoids a second inbound WAN port-forward for the application.
