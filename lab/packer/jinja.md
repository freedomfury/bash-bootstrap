# Packer Template Rendering with MiniJinja

## Overview

`builder.pkr.hcl` is a **generated file** — do not edit it directly. It is
rendered from a Jinja template using a JSON input file. The workflow is:

1. **Validate** the input JSON against its schema
2. **Render** the Jinja template to produce `builder.pkr.hcl`
3. **Validate** the rendered HCL with Packer (optional)

---

## File Layout

```
lab/packer/
├── builder.json              ← Input: consumer-provided build definition
├── builder.pkr.hcl           ← Output: rendered HCL (generated, do not edit)
├── builder.pkr.tpl           ← Jinja template for the build block
├── jinja.toml                ← MiniJinja delimiter config (ERB-style <% %>)
├── macros/
│   └── provisioners.jinja    ← Generic provisioner rendering macro
└── schema/
    ├── builder.schema.json   ← JSON Schema for builder.json
    └── provisoner/
        ├── shell.schema.json
        ├── shell-local.schema.json
        └── ansible.schema.json
```

---

## The Jinja Delimiter Config (`jinja.toml`)

Packer HCL uses `${...}` for its own interpolation. To avoid collisions,
MiniJinja is configured to use ERB-style delimiters:

```toml
[syntax]
block-start    = "<%"
block-end      = "%>"
variable-start = "<%="
variable-end   = "%>"
comment-start  = "<%#"
comment-end    = "%>"
```

This means Packer's `${var.cache_dir}` passes through untouched.

---

## The Input File (`builder.json`)

The consumer creates a `builder.json` describing their build. It defines:

- `build.name` — an arbitrary label for the build block
- `build.sources` — list of images to build against (must exist in `images.auto.pkrvars.hcl`)
- `build.provisioners` — ordered list of provisioners injected between the fixed `initialize` and `cleanup` blocks

### Example

```json
{
  "build": {
    "name": "my-custom-build",
    "sources": [
      { "image_name": "almalinux-97",  "source_name": "alma-shell-1" },
      { "image_name": "almalinux-810", "source_name": "alma-shell-2" }
    ],
    "provisioners": [
      {
        "type": "shell",
        "name": "install-ntp",
        "inline_shebang": "/bin/sh",
        "inline": [
          "sudo dnf install -y chrony",
          "sudo systemctl enable --now chronyd"
        ],
        "timeout": "10m"
      },
      {
        "type": "shell",
        "name": "validate-ntp",
        "inline": ["systemctl is-active chronyd"],
        "valid_exit_codes": [0]
      }
    ]
  }
}
```

### Supported provisioner types

| `type` | Schema |
|---|---|
| `shell` | `schema/provisoner/shell.schema.json` |
| `shell-local` | `schema/provisoner/shell-local.schema.json` |
| `ansible` | `schema/provisoner/ansible.schema.json` |

All provisioner objects require a `name` field (Packer meta-label). All other
fields are optional and rendered only if present.

### Image name validation

`image_name` values are not validated by the JSON schema — they are
self-validating: if an image name doesn't exist in `images.auto.pkrvars.hcl`,
Packer will fail at the source definition with a clear error.

---

## The Template (`builder.pkr.tpl`)

The template is a sandwich:

```
import macros
build {
  <fixed sources loop>
  provisioner "shell" { name = "initialize" ... }   ← always first
  <injected provisioners via generic render_provisioner macro>
  post-processor "shell-local" { name = "cleanup" } ← always last
}
```

The `initialize` and `cleanup` blocks are fixed verbatim HCL — they are not
configurable via `builder.json`.

### Macro import

The template imports a single generic macro from `macros/provisioners.jinja`:

```jinja
<%- from 'macros/provisioners.jinja' import render_provisioner -%>
```

`import` (not `include`) is used so the macro is registered as a callable
function. `include` would paste the file contents inline without making the
macro name available.

The provisioner loop calls the generic macro for each provisioner:

```jinja
<%- for p in build.provisioners %>
<%= render_provisioner(p) %>
<%- endfor %>
```

---

## The Macro Library (`macros/provisioners.jinja`)

A single generic `render_provisioner` macro that handles all provisioner types.
It iterates over all keys in the provisioner object (excluding `type`) and
renders each field based on its value type:

- **String** → `"value"`
- **Sequence (array)** → `["val1", "val2", ...]`
- **Mapping (object)** → `{ key = "value" }`
- **Other (int, bool)** → bare value

The provisioner type is used for the block header (`provisioner "shell" { ... }`),
and all remaining fields are rendered generically. This means new provisioner
types work without modifying the macro.

---

## Full Workflow

### Using `hcl-render`

The `bin/hcl-render` script handles validation and rendering in one command:

```bash
source exports && lab/packer/bin/hcl-render \
    -i lab/packer/builder.json \
    -t lab/packer/builder.pkr.tpl \
    -o lab/packer/builder.pkr.hcl --force
```

This:
1. Validates `builder.json` against `schema/builder.schema.json`
2. Renders the Jinja template using `jinja.toml` config
3. Writes the output to `builder.pkr.hcl`

Options:
- `--fmt` (`-f`): Run `packer fmt` on the output directory after rendering
- `--force` (`-F`): Overwrite an existing output file
- `--schema` (`-s`): Override the default schema path
- `--config` (`-c`): Override the default Jinja config path

### Manual Steps

```bash
# Step 1 — validate input
jsonschema validate schema/builder.schema.json builder.json

# Step 2 — render template
jinja --safe-path . --config-file jinja.toml builder.pkr.tpl builder.json -o builder.pkr.hcl

# Step 3 — validate rendered HCL
HOST_UID=$(id -u) \
VIRTIOFSD_WRAPPER=./bin/qemu-virtiofsd \
PACKER_CACHE_DIR=./.packer_cache \
EPOCHREALTIME=$EPOCHREALTIME \
  packer validate --evaluate-datasources .
```

### Notes

- `--safe-path .` is required for `jinja` to resolve the `macros/` import path
- `--evaluate-datasources` is required for Packer to resolve the `sshkey` data
  source used in `sources.pkr.hcl` (otherwise SSH key validation fails)
- `EPOCHREALTIME` is a Bash 5 internal variable — it is never in the process
  environment by default. It must be explicitly exported before calling Packer.
  `run-mvp` handles this via `export EPOCHREALTIME`

---

## Example Rendered Output

Given the example `builder.json` above, `builder.pkr.hcl` renders as:

```hcl
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
    name           = "install-ntp"
    inline_shebang  = "/bin/sh"
    inline = [
      "sudo dnf install -y chrony",
      "sudo systemctl enable --now chronyd",
    ]
    timeout         = "10m"
  }
  provisioner "shell" {
    name           = "validate-ntp"
    inline = [
      "systemctl is-active chronyd",
    ]
    valid_exit_codes = [0]
  }

  post-processor "shell-local" {
    name   = "cleanup"
    inline = [
      "echo 'Cleaning up output folder ${var.cache_dir}/pk-${source.name} ...'",
      "rm -rf ${var.cache_dir}/pk-${source.name}",
    ]
  }
}
```
