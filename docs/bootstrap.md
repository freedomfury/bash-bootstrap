# Bootstrap Subproject

`bootstrap.d` configures a freshly provisioned machine: packages, config files,
services — reliably and idempotently. It is modelled on Ansible roles: each
service or subsystem is a self-contained **task** with its own lifecycle.

The pipeline runs via `make bootstrap` from the monolith root.

---

## Documentation

| Document | Purpose |
|---|---|
| [`bootstrap.d/BOOTSTRAP.md`](../bootstrap.d/BOOTSTRAP.md) | Full technical specification: pipeline, fact model, task anatomy, scoreboard, secrets |
| [`bootstrap.d/README.md`](../bootstrap.d/README.md) | Convention overrides specific to this subproject |
| [`bootstrap.d/PROGRESS.md`](../bootstrap.d/PROGRESS.md) | Work in progress: implementation backlog and open decisions |
| [`docs/facts.md`](facts.md) | Global fact generators used by preflight |
| [`docs/age.md`](age.md) | Secrets management with age encryption |
