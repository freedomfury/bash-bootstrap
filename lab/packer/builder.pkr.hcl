build {
  name = "my-custom-build"
  source "source.qemu.almalinux-97" {
    name             = "alma-shell-1"
    output_directory = "${var.cache_dir}/pk-${source.name}"
  }
  source "source.qemu.almalinux-810" {
    name             = "alma-shell-2"
    output_directory = "${var.cache_dir}/pk-${source.name}"
  }

  provisioner "shell" {
    name           = "initialize"
    inline_shebang  = "/bin/sh"
    inline = [
      "sudo cloud-init status --wait",
      "mountpoint -q /var/run/shared-vfsd || { echo 'FATAL: /var/run/shared-vfsd not mounted'; exit 1; }",
      "echo 'Cloud-init finished and /var/run/shared-vfsd is mounted.'"
    ]
    timeout = "5m"
  }
  provisioner "shell" {
    name = "install-ntp"
    inline_shebang = "/bin/sh"
    inline = [
      "sudo dnf install -y chrony",
      "sudo systemctl enable --now chronyd",
    ]
    timeout = "10m"
  }
  provisioner "shell" {
    name = "validate-ntp"
    inline = [
      "systemctl is-active chronyd",
    ]
    valid_exit_codes = [
      0,
    ]
  }

  post-processor "shell-local" {
    name   = "cleanup"
    inline = [
      "echo 'Cleaning up output folder ${var.cache_dir}/pk-${source.name} ...'",
      "rm -rf ${var.cache_dir}/pk-${source.name}",
    ]
  }
}
