# Schema Sources

This document records the authoritative upstream sources for all provisioner schemas.
When updating a schema, fetch the current docs from these URLs first.

---

## `provisoner/shell.schema.json`

**Packer built-in provisioner**

- Docs: https://developer.hashicorp.com/packer/docs/provisioners/shell
- Fields sourced: all documented required + optional parameters, plus common provisioner parameters (`pause_before`, `max_retries`, `only`, `timeout`)
- Intentionally excluded: `override` (nested per-builder object, not supported by this templating system)

---

## `provisoner/shell-local.schema.json`

**Packer built-in provisioner**

- Docs: https://developer.hashicorp.com/packer/docs/provisioners/shell-local
- Fields sourced: all documented required + optional parameters, plus common provisioner parameters
- Intentionally excluded: `override`
- Note: `execute_command` is an **array of strings** for shell-local (unlike shell, where it is a plain string)

---

## `provisoner/ansible.schema.json`

**HashiCorp Ansible plugin provisioner**

- Docs: https://developer.hashicorp.com/packer/integrations/hashicorp/ansible/latest/components/provisioner/ansible
- Plugin repo: https://github.com/hashicorp/packer-plugin-ansible
- Fields sourced: all documented required + optional parameters, plus common provisioner parameters
- Intentionally excluded: `override`

---

## Notes for Updating

- The Packer docs version selector is at the top of each page — always check against the version being deployed
- "Parameters common to all provisioners" (`pause_before`, `max_retries`, `only`, `timeout`) appear at the bottom of every provisioner page and must be added to each schema manually
- `override` is a deeply nested per-builder object that this system does not render; do not add it
- The `provisoner/` directory name is intentionally misspelled to match the existing path — do not rename
