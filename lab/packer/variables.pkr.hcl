# Variable schema

variable "host_uid" {
  type        = string
  default     = env("HOST_UID")
  description = "Host UID for guest user mapping (from HOST_UID env var)"

  validation {
    condition     = length(var.host_uid) > 0
    error_message = "HOST_UID environment variable must be set and non-empty."
  }
}

variable "virtiofsd_wrapper" {
  type        = string
  default     = env("VIRTIOFSD_WRAPPER")
  description = "Path to QEMU wrapper that starts per-build virtiofsd (from VIRTIOFSD_WRAPPER env var)"

  validation {
    condition     = length(var.virtiofsd_wrapper) > 0
    error_message = "VIRTIOFSD_WRAPPER environment variable must be set and non-empty."
  }
}

variable "cache_dir" {
  type        = string
  default     = env("PACKER_CACHE_DIR")
  description = "Packer cache directory for ephemeral run artifacts (from PACKER_CACHE_DIR env var)"

  validation {
    condition     = length(var.cache_dir) > 0
    error_message = "PACKER_CACHE_DIR environment variable must be set and non-empty."
  }
}

variable "epoch_timestamp" {
  type        = string
  default     = env("EPOCHREALTIME")
  description = "Current timestamp for build reproducibility (default: current time)"
  validation {
    condition     = length(var.epoch_timestamp) > 0
    error_message = "EPOCHREALTIME environment variable must be set and non-empty."
  }
}

variable "admin_user" {
  type        = string
  default     = "sysadm"
  description = "Admin username to create in the guest for SSH access (default: sysadm)"
}

variable "image_maps" {
  type = map(object({
    iso_url      = string
    iso_checksum = string
  }))
  description = "Map of image names to their ISO URLs and checksums for build sources."
  validation {
    condition     = length(var.image_maps) > 0
    error_message = "Variable image_maps must contain at least one image definition."
  }
}

data "sshkey" "build" {
  name = "build"
}
