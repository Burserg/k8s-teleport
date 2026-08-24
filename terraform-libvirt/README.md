# Terraform on the libvirt/QEMU host (Arch Linux)

This configuration sits beside `../terraform-proxmox/`. Keep the Proxmox state
there so its old VMs can still be destroyed from that directory. Set the
network plan and Cilium pool in `terraform.tfvars` and
`../ansible/group_vars/all.yml`. They must agree.

## One-time host prep (Arch)

You already have libvirt + QEMU running (`virsh version` works), so most of
this is verification rather than installation.

### Packages

```bash
pacman -S --needed qemu-base libvirt dnsmasq
# qemu-base is the headless build. Install qemu-full only for GUI/SPICE.
# dnsmasq is only needed for a libvirt NAT network. The lab uses
# a host bridge instead.
```

### Daemon sockets for REMOTE access

Local `virsh` working does not prove remote works. The provider connects over
`qemu+ssh://` to the classic socket `/var/run/libvirt/libvirt-sock`. With the
monolithic daemon:

```bash
systemctl enable --now libvirtd.service
```

If you run the modular daemons (virtqemud, virtstoraged, ...) instead, that
socket does not exist until the proxy is up:

```bash
systemctl enable --now virtproxyd.socket
```

Check: `test -S /var/run/libvirt/libvirt-sock && echo ok`

### Unprivileged access for the Terraform SSH user

The Arch libvirt package ships a polkit rule granting the `libvirt` group
full access. No sudo or root SSH:

```bash
usermod -aG libvirt <ssh-user>
# verify from your workstation:
virsh -c qemu+ssh://<ssh-user>@<host>/system list --all
```

That `virsh -c` command is the preflight for `tofu plan`. If it works, the
provider connects.

### Storage pool

```bash
virsh pool-list --all
# if 'default' is missing:
virsh pool-define-as default dir --target /var/lib/libvirt/images
virsh pool-build default && virsh pool-start default && virsh pool-autostart default
```

### Bridge (systemd-networkd)

The VMs need a bridge that enslaves the physical NIC, so they appear directly
on `192.168.2.0/24`. Cilium's L2 announcements are link-local and do not cross
libvirt NAT on `virbr0`. Get the NIC name with `ip -br link`:

```ini
# /etc/systemd/network/10-br0.netdev
[NetDev]
Name=br0
Kind=bridge
```

```ini
# /etc/systemd/network/20-uplink.network
[Match]
Name=eno1

[Network]
Bridge=br0
```

```ini
# /etc/systemd/network/30-br0.network
[Match]
Name=br0

[Network]
Address=192.168.2.5/24
Gateway=192.168.2.1
DNS=192.168.2.1
```

```bash
systemctl enable --now systemd-networkd
```

The host's IP moves onto the bridge. Do this from console or IPMI, because the
SSH session will drop. A NetworkManager host needs the same layout through
`nmcli con add type bridge ...`.

### Router

Exclude the node IPs (`.10-.22`) and the Cilium pool (`.71-.127`) from the
router's DHCP range.

## Run

```bash
# fill in libvirt_uri (and network_bridge if not br0) in terraform.tfvars
make init && make plan && make apply   # from the repo root, TF_DIR points here
```

Apply writes `../ansible/Inventory/hosts.ini`, then the Ansible flow is
unchanged: `make cluster`.
