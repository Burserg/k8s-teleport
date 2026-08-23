# The provider speaks the libvirt API directly — no Proxmox-style REST
# endpoint or API token. Over qemu+ssh:// the only host-side requirement is
# that the SSH user can open the libvirt socket (usermod -aG libvirt <user>).
#
# Host is Arch Linux: no AppArmor/SELinux policy ships for libvirt there, so
# the Debian/Ubuntu "Permission denied opening the qcow2" MAC gotcha does not
# apply — volume access is plain DAC. Host prep notes are in README.md.
provider "libvirt" {
  uri = var.libvirt_uri
}
