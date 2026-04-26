# Packer configuration

packer {
  required_plugins {
    sshkey = {
      version = ">= 0.1.0"
      source  = "github.com/ivoronin/sshkey"
    }
    qemu = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}