---
name: secrets
description: Encrypt and decrypt project secrets using age with SSH key pairs.
---
# Skill: Secrets Management with age

This skill ensures consistent and secure handling of project secrets across all development and automated workflows.

## Canonical Rules

1.  **Use the standard library**: Always use `lib::std::secrets::encrypt` and `lib::std::secrets::decrypt` from `lib/std/secrets.sh`. The library handles `--armor`, public key derivation, and idempotency automatically.
2.  **Private Key Resolution**: Always resolve the identity file via `${MKS_AGE_PKEY:-${MKS_TMP}/age/id_rsa}`. Never hardcode absolute paths to identities.
3.  **In-Memory Load**: Use process substitution `source <(lib::std::secrets::decrypt ...)` to load secrets into scripts. Never write decrypted plaintext to disk.

## Workflows

### 1. Encrypting a new secrets file
A project-standard assignment file (e.g., `vars/secrets.env.sec`) must be encrypted before commit.
- **Goal**: Produce an ASCII PEM encrypted file.
- **Procedure**:
    - Run the encryption: `lib::std::secrets::encrypt --source vars/secrets.env.sec --target vars/secrets.env.sec.age` (public key is derived automatically)
    - Verify the output is armored: `head -n 1 vars/secrets.env.sec.age` (should start with `-----BEGIN AGE ENCRYPTED FILE-----`)

### 2. Auditing secret recipients
Periodically verify that secrets are only accessible by authorized keys.
- **Procedure**: Use the `bin/audit` helper in this skill folder to inspect all headers.
- **Correction**: If an unauthorized key is found, rotate the project secrets immediately.

### 3. Key Rotation
When an identity is compromised or a team member leaves:
- **Procedure**:
    - Replace `tmp/age/id_rsa`.
    - Use the `bin/rotate` helper in this skill folder to re-encrypt all project files (public key is derived automatically during encryption).

## Common Failures
- **Hardcoded Identity**: If you don't use the `MKS_AGE_PKEY` fallback pattern, scripts will fail in CI/CD environments where keys are injected at runtime.
- **Plaintext Leak**: Always verify that `*.env.sec` is in `.gitignore` so plaintext secrets are never committed.
- **Missing Private Key**: If `${MKS_AGE_PKEY:-${MKS_TMP}/age/id_rsa}` doesn't exist, decryption will fail. Ensure the key is deployed in CI/CD or symlinked locally.
