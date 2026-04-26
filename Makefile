include inc/common.mk
include bootstrap.d/main.mk

# Anchors all the rest of the dependencies.
.PHONY: depends
depends: vendor.lock

# Checks to make sure the toolkit is built.
vendor.lock:
	@printf 'ERROR: Toolkit not built. Please run: ./mks-vendor\n' >&2
	@exit 1


.PHONY: bootstrap 
#@ Run the full bootstrap subproject pipeline.
bootstrap: depends
	@echo "==- bootstrap -=="
	$(MAKE) --no-print-directory -j$(nproc) -f Makefile bootstrapd
#@ Clean all project-level temporary files.

clean:
	@echo "==- clean -=="
	rm -vrf tmp/*

.PHONY: commit
#@ Add all files to git and commit with a message.
commit: depends
	@echo "==- commit -=="
	git add . --all
	git commit -am "Update"
