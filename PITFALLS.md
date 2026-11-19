# Operational pitfalls

## Installed gda trampoline fails before Godot starts

- **Applies when:** the installed Windows gda executable reports `uv trampoline failed to canonicalize script path`.
- **Symptom:** even `gda --version --json` fails before starting the engine.
- **Cause:** launcher cannot resolve its managed script; this is not evidence of a Godot project defect.
- **Recovery:** use the project's bundled console executable for this project's documented tests and rendered script captures; do not reinstall tools or clear configuration as a generic remedy.
- **Last verified:** 2026-11-19; Godot 4.7.2 direct execution succeeded.

## Shared Windows workspace ownership

- **Applies when:** sandbox account differs from the known repository owner's account and Git rejects the directory as dubious ownership.
- **Prevention:** use a per-command `git -c safe.directory=<exact-known-repository-root>` for the authorized repository, rather than changing global configuration or trusting all directories.
- **Recovery:** the Sydney pipeline's actual Git root is its parent Sydney directory, not the nested sydney-osm-world directory.
- **Last verified:** 2026-11-19.
