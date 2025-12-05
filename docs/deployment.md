# PSmediaManager Deployment Guide

This guide covers secure deployment of PSmediaManager using containers, including runtime hardening recommendations to minimize attack surface and mitigate vulnerabilities.

---

## Container Image

The project provides a minimal, pinned Alpine-based container image optimized for security scanning:

```dockerfile
FROM mcr.microsoft.com/powershell:7.5-alpine-3.20@sha256:a6beeddb2fcf45547c9099fba091ce231e51aa374fe62ecc182f7c28b69a6cbf
# zlib patched via apk to keep CVE-2023-45853 addressed
RUN apk update \
  && apk upgrade \
  && apk add --no-cache zlib
```

### Security Features
- **Base Image**: Alpine 3.20 (pinned digest) with PowerShell 7.5
- **Updates Applied**: `apk upgrade` plus explicit `zlib` install to keep zlib patched
- **Minimized Packages**: No extra packages beyond zlib; apk cache removed via `--no-cache`
- **Non-Root User**: Runs as `psmm` (UID 1000) to limit privilege escalation

---

## Building the Image

```bash
# Build from repository root
docker build -t psmediamanager:latest .

# Build with specific tag
docker build -t psmediamanager:v1.0.0 .

# Scan with Trivy
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image psmediamanager:latest
```

---

## Runtime Hardening

### Docker CLI

Run with security flags to enforce defense-in-depth:

```bash
docker run -d \
  --name psmediamanager \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=100m \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  --cap-add NET_BIND_SERVICE \
  -u 1000:1000 \
  -v /path/to/config:/app/config:ro \
  -v /path/to/data:/app/data:rw \
  psmediamanager:latest
```

**Flag Explanation**:
- `--read-only`: Root filesystem is immutable; prevents container tampering
- `--tmpfs /tmp`: Writable temp space with exec disabled
- `--security-opt no-new-privileges`: Blocks privilege escalation via setuid/setgid
- `--cap-drop ALL`: Removes all Linux capabilities
- `--cap-add NET_BIND_SERVICE`: Adds back only required capabilities (example)
- `-u 1000:1000`: Enforce non-root user explicitly
- `-v ... :ro`: Mount config volumes read-only where possible

### Docker Compose

Create a `docker-compose.yml` with hardening directives:

```yaml
version: '3.8'

services:
  psmediamanager:
    image: psmediamanager:latest
    container_name: psmediamanager
    user: "1000:1000"
    read_only: true
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE  # Adjust based on actual needs
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=100m
    volumes:
      - ./config:/app/config:ro
      - ./data:/app/data:rw
    restart: unless-stopped
```

Run with:

```bash
docker-compose up -d
```

### Kubernetes

Deploy with a hardened `PodSecurityContext`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: psmediamanager
spec:
  replicas: 1
  selector:
    matchLabels:
      app: psmediamanager
  template:
    metadata:
      labels:
        app: psmediamanager
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: psmediamanager
        image: psmediamanager:latest
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
            add:
              - NET_BIND_SERVICE  # Adjust as needed
        volumeMounts:
        - name: config
          mountPath: /app/config
          readOnly: true
        - name: data
          mountPath: /app/data
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: config
        configMap:
          name: psmediamanager-config
      - name: data
        persistentVolumeClaim:
          claimName: psmediamanager-data
      - name: tmp
        emptyDir:
          medium: Memory
          sizeLimit: 100Mi
```

Apply with:

```bash
kubectl apply -f deployment.yaml
```

---

## Network Policies

If running in Kubernetes, restrict egress/ingress with NetworkPolicy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: psmediamanager-netpol
spec:
  podSelector:
    matchLabels:
      app: psmediamanager
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend  # Example: allow only from frontend pods
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: database  # Example: allow only to database
    ports:
    - protocol: TCP
      port: 5432
  - to:  # Allow DNS
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
```

---

## Continuous Security

### Image Scanning in CI/CD

Integrate Trivy into your pipeline:

```yaml
# GitHub Actions example
- name: Build image
  run: docker build -t psmediamanager:${{ github.sha }} .

- name: Scan with Trivy
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: psmediamanager:${{ github.sha }}
    format: 'sarif'
    output: 'trivy-results.sarif'
    severity: 'CRITICAL,HIGH'
    exit-code: 1  # Fail pipeline on critical/high

- name: Upload results
  uses: github/codeql-action/upload-sarif@v2
  with:
    sarif_file: 'trivy-results.sarif'
```

### Rebuild Cadence

- **Weekly**: Rebuild images to consume latest Debian security updates
- **On CVE Alerts**: Trigger rebuild when Debian security advisories (DSA) are published
- **Pin by Digest**: Use `mcr.microsoft.com/powershell@sha256:...` to ensure reproducible builds

---

## Security Checklist

Before deploying to production:

- [ ] Image built with latest base and security patches applied
- [ ] Trivy scan passed with no high/critical vulnerabilities (or documented exceptions)
- [ ] Running as non-root user (UID 1000)
- [ ] Read-only root filesystem enabled
- [ ] All capabilities dropped except explicitly required
- [ ] `no-new-privileges` security option set
- [ ] Tmpfs configured for writable paths with `noexec`
- [ ] Network policies restrict unnecessary ingress/egress (Kubernetes)
- [ ] Secrets mounted via orchestrator mechanisms (not baked into image)
- [ ] Resource limits (CPU, memory) enforced to prevent DoS
- [ ] Monitoring and alerting configured for container events

---

## Troubleshooting

### Read-Only Filesystem Issues

If the application fails due to read-only constraints:
1. Identify writable paths required at runtime
2. Mount them as `tmpfs` or persistent volumes:

  ```bash
   --tmpfs /app/cache:rw,noexec,nosuid,size=50m
   ```

### Capability Errors

If the application requires specific capabilities:
1. Run with `--cap-add SYS_ADMIN` (example) temporarily to diagnose
2. Use `capsh` or `pscap` to audit actual capabilities needed
3. Add only the minimal set to production config

### Permission Denied

Ensure volume mounts have correct ownership:

```bash
sudo chown -R 1000:1000 /path/to/data
```

---

## References

- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)
- [OWASP Container Security](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)

---

## Support

For security concerns or questions, open an issue in the [GitHub repository](https://github.com/mosh666/PSmediaManager/issues).
