# Plan: Multi-Scenario System for Packer EITF

## Context

The current `lab/packer/` framework supports a single scenario defined in `builder.json`. The goal is to evolve this into a Molecule-like system where users can define multiple scenarios (each with different provisioners/tests), select which to run, and share all base infrastructure without duplication.

## Approach: "Render Selected Only"

When a scenario is selected, render only that scenario's `builder.json` through the existing template and run Packer directly. No concatenation, no `-only` flag juggling.

**Why not "render all + Packer `-only`":**
- `builder.schema.json` defines a single `build` object — no schema changes needed
- `builder.pkr.tpl` produces one `build {}` block — no template changes needed
- `hcl-render` already accepts `--input` — the tool is already parameterized
- No name coupling between directory names and Packer build names
- No resource waste rendering/validating scenarios you aren't running

## Directory Layout

```
lab/packer/
├── scenarios/                    # NEW
│   └── ntp-test/                 # example scenario
│       ├── builder.json          # scenario-specific build definition
│       └── files/                # optional: scripts, playbooks
│           └── custom-ntp.sh
├── builder.json                  # KEPT as default (backward compatible)
├── builder.pkr.tpl               # UNCHANGED
├── ... (all shared files unchanged)
```

Scenario-local files are automatically accessible inside the guest via the existing virtiofs mount at `/var/run/shared-vfsd/scenarios/<name>/files/`.

## Changes

### 1. Create `scenarios/` directory + seed scenario

- `mkdir -p lab/packer/scenarios/ntp-test/files`
- Copy current `builder.json` to `scenarios/ntp-test/builder.json` as a working example

### 2. Modify `run-mvp` (the only file that changes)

**New CLI flags:**
```
-s, --scenario <name>   Run a specific scenario from scenarios/<name>/builder.json
-l, --list-scenarios    List available scenarios and exit
```

**What changes inside `main()`:**

1. Add `scenario` and `list_scenarios` to the `opts` hash and `case` parser
2. Add `_list_scenarios()` function — iterates `scenarios/*/builder.json`, prints names
3. If `--list-scenarios`, call it and exit
4. **Scenario resolution** — replace the implicit `builder.json` assumption:
   ```bash
   if [[ -n "${opts[scenario]}" ]]; then
     input_json="${_SCRIPT_DIR}/scenarios/${opts[scenario]}/builder.json"
     # validate it exists
   else
     input_json="${_SCRIPT_DIR}/builder.json"
   fi
   ```
5. **Add explicit `hcl-render` call** before `packer build`:
   ```bash
   "${_SCRIPT_DIR}/bin/hcl-render" \
     -i "${input_json}" \
     -t "${_SCRIPT_DIR}/builder.pkr.tpl" \
     -o "${_SCRIPT_DIR}/builder.pkr.hcl" \
     --force
   ```
   `hcl-render` already resolves schema/config paths relative to the template directory, so no extra flags needed.

**What stays the same:** preflight checks, Go wrapper build, `packer init`, `packer build`, result verification — all unchanged.

### 3. Update `lab/packer/main.md`

Add scenarios section to documentation and update the directory tree.

## Files Modified

| File | Change |
|---|---|
| `lab/packer/run-mvp` | Add `-s`/`-l` flags, scenario resolution, `hcl-render` call |
| `lab/packer/main.md` | Document scenarios directory and new flags |
| `lab/packer/scenarios/ntp-test/builder.json` | New — seed scenario (copy of current default) |

**No changes to:** `sources.pkr.hcl`, `variables.pkr.hcl`, `images.auto.pkrvars.hcl`, `packer.pkr.hcl`, `builder.pkr.tpl`, `macros/`, `schema/`, `bin/hcl-render`, `bin/qemu-virtiofsd`

## Verification

1. `run-mvp` — should behave identically to today (uses root `builder.json`)
2. `run-mvp --list-scenarios` — should list `ntp-test`
3. `run-mvp --scenario ntp-test` — should render and run the ntp-test scenario
4. `run-mvp --scenario nonexistent` — should fail with clear error
5. Verify that `scenarios/ntp-test/files/` content is accessible inside the guest at `/var/run/shared-vfsd/scenarios/ntp-test/files/`
