# Pushing the patched PSmediaManager image

## Build and tag locally

```pwsh
# Build from repo root
pwsh -NoProfile -Command "docker build -t psmediamanager:patched ."

# Optionally tag for your registry (example using GHCR)
docker tag psmediamanager:patched ghcr.io/OWNER/psmediamanager:patched
```

## Push to registry

```pwsh
# Replace OWNER with your org/user
docker push ghcr.io/OWNER/psmediamanager:patched
```
 

## CI/CD tip
- In pipelines, use the pinned base digest in `Dockerfile` to avoid drift.
- For Trivy/Codacy scans, prefer scanning the built image (`docker build` then `trivy image ...`) rather than source-only scans to reflect the pinned base.
