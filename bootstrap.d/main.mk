# bootstrap.d/main.mk -- Bootstrap subproject pipeline targets.
# Included by the top-level Makefile via: include bootstrap.d/main.mk
# Targets here are not annotated with #@ and do not appear in `make help`.

.PHONY: target-guard bootstrapd preflight execute tasks scoreboard finalize cleanup

# -- Guard: abort if not running inside a bootstrap environment (/opt/bss bind mount)
target-guard:
	@test -f /opt/bss/exports || {
		printf 'ERROR: /opt/bss/exports not found.\n' >&2
		printf '       Bootstrap must run inside a bootstrap container.\n' >&2
		printf '       Start one with: .agent/skills/compose/bin/start --mount /opt/bss ...\n' >&2
		printf '==-\n\n' >&2
		exit 1
	}

# -- Full pipeline: preflight gates execute; finalize and cleanup always run.
bootstrapd: target-guard bootstrap.d/exports
	@{ $(MAKE) --no-print-directory preflight && $(MAKE) --no-print-directory execute; } || true
	$(MAKE) --no-print-directory finalize
	$(MAKE) --no-print-directory cleanup

preflight: bootstrap.d/exports
	@echo "==- bootstrap::preflight -=="
	source bootstrap.d/exports
	bootstrap.d/bin/preflight

# -- execute: all tasks run in parallel; continues on individual failure
execute: tasks

tasks:

# -- finalize: always runs; collect results and emit report
finalize: bootstrap.d/exports
	@echo "==- bootstrap::finalize -=="
	source bootstrap.d/exports
	bootstrap.d/bin/scoreboard

# -- cleanup: always runs; remove temp artifacts
cleanup:
	@echo "==- bootstrap::cleanup -=="
	source bootstrap.d/exports
	rm -rf "${BSS_TMP}/scores"
