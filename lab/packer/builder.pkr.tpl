<%- from 'macros/provisioners.jinja' import render_provisioner -%>
build {
  name = "<%= build.name %>"

  <%- for src in build.sources %>
  source "source.qemu.<%= src.image_name %>" {
    name             = "<%= src.source_name %>"
    output_directory = "${var.cache_dir}/pk-${source.name}"
  }
  <%- endfor %>

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

  <%- for p in build.provisioners %>
  <%= render_provisioner(p) %>
  <%- endfor %>

  post-processor "shell-local" {
    name   = "cleanup"
    inline = [
      "echo 'Cleaning up output folder ${var.cache_dir}/pk-${source.name} ...'",
      "rm -rf ${var.cache_dir}/pk-${source.name}",
    ]
  }
}
