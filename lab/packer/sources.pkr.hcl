
# -- Local variables for socket and log paths
locals {
  vm_name     = "image.qcow2"
  run_dir     = "${var.cache_dir}/run"
  vfsd_sock   = "${local.run_dir}/{{ .Name }}-{{ .SSHHostPort }}.sock"
  serial_sock = "${local.run_dir}/{{ .Name }}-{{ .SSHHostPort }}-serial.sock"
  serial_log  = "${local.run_dir}/{{ .Name }}-{{ .SSHHostPort }}-serial.log"
}

# -- Source blocks

source "qemu" "almalinux-97" {
  iso_url          = var.image_maps["almalinux-97"].iso_url
  iso_checksum     = var.image_maps["almalinux-97"].iso_checksum
  use_backing_file = true
  disk_image       = true
  vm_name          = local.vm_name

  # -- Guest hardware
  cpus        = 2
  memory      = 2048
  format      = "qcow2"
  accelerator = "kvm"
  qemu_binary = var.virtiofsd_wrapper

  qemuargs = [
    ["-cpu", "host"],
    ["-object", "memory-backend-memfd,id=mem,size=2048M,share=on"],
    ["-numa", "node,memdev=mem"],
    ["-chardev", "socket,id=vfsd,path=${local.vfsd_sock}"],
    ["-device", "vhost-user-fs-pci,chardev=vfsd,tag=shared-vfsd"],
    ["-chardev", "socket,id=serial,path=${local.serial_sock},server,nowait,logfile=${local.serial_log}"],
    ["-serial", "chardev:serial"],
    ["-netdev", "user,hostname={{ .Name }}-{{ .SSHHostPort }},hostfwd=tcp::{{ .SSHHostPort }}-:22,id=forward"],
    ["-device", "virtio-net,netdev=forward,id=net0"],
    ["-smbios", "type=1,serial=ds=nocloud;h={{ .Name }}-{{ .SSHHostPort }}"]
  ]

  # -- Cloud-init via config drive (CIDATA)
  cd_label = "cidata"
  cd_content = {
    "meta-data" = <<-EOF
      instance_id: "{{ .Name }}-{{ .SSHHostPort }}"
    EOF

    "user-data" = <<-EOF
      #cloud-config

      users:
        - name: ${var.admin_user}
          uid: ${var.host_uid}
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${data.sshkey.build.public_key}
      runcmd:
        - setenforce 0
        - mkdir -p /var/run/shared-vfsd
        - mount -t virtiofs shared-vfsd /var/run/shared-vfsd
    EOF
  }

  # -- SSH communicator (key from sshkey plugin)
  communicator         = "ssh"
  ssh_username         = var.admin_user
  ssh_private_key_file = data.sshkey.build.private_key_path
  ssh_timeout          = "5m"
  headless             = true
}

source "qemu" "almalinux-810" {
  iso_url          = var.image_maps["almalinux-810"].iso_url
  iso_checksum     = var.image_maps["almalinux-810"].iso_checksum
  use_backing_file = true
  disk_image       = true
  vm_name          = local.vm_name
  # -- Guest hardware
  cpus        = 2
  memory      = 2048
  format      = "qcow2"
  accelerator = "kvm"
  qemu_binary = var.virtiofsd_wrapper

  # -- QEMU arguments
  qemuargs = [
    ["-cpu", "host"],
    ["-object", "memory-backend-memfd,id=mem,size=2048M,share=on"],
    ["-numa", "node,memdev=mem"],
    ["-chardev", "socket,id=vfsd,path=${local.vfsd_sock}"],
    ["-device", "vhost-user-fs-pci,chardev=vfsd,tag=shared-vfsd"],
    ["-chardev", "socket,id=serial,path=${local.serial_sock},server,nowait,logfile=${local.serial_log}"],
    ["-serial", "chardev:serial"],
    ["-netdev", "user,hostname={{ .Name }}-{{ .SSHHostPort }},hostfwd=tcp::{{ .SSHHostPort }}-:22,id=forward"],
    ["-device", "virtio-net,netdev=forward,id=net0"],
    ["-smbios", "type=1,serial=ds=nocloud;h={{ .Name }}-{{ .SSHHostPort }}"]
  ]

  # -- Cloud-init via config drive (CIDATA)
  cd_label = "cidata"
  cd_content = {
    "meta-data" = <<-EOF
      instance_id: "{{ .Name }}-{{ .SSHHostPort }}"
    EOF

    "user-data" = <<-EOF
      #cloud-config

      users:
        - name: ${var.admin_user}
          uid: ${var.host_uid}
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${data.sshkey.build.public_key}
      runcmd:
        - setenforce 0
        - mkdir -p /var/run/shared-vfsd
        - mount -t virtiofs shared-vfsd /var/run/shared-vfsd
    EOF
  }

  # -- SSH communicator (key from sshkey plugin)
  communicator         = "ssh"
  ssh_username         = var.admin_user
  ssh_private_key_file = data.sshkey.build.private_key_path
  ssh_timeout          = "5m"
  headless             = true
}