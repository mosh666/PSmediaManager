# Minimal Dockerfile for PSmediaManager vulnerability scanning
# Built for Trivy/Codacy CLI to have a container context.

FROM mcr.microsoft.com/powershell:7.5-alpine-3.20@sha256:a6beeddb2fcf45547c9099fba091ce231e51aa374fe62ecc182f7c28b69a6cbf
LABEL org.opencontainers.image.source="https://github.com/mosh666/PSmediaManager"
LABEL org.opencontainers.image.title="PSmediaManager"
LABEL org.opencontainers.image.description="Minimal container image for security scanning of PSmediaManager"

# Set working directory
WORKDIR /app

# Apply latest security updates to base packages
RUN apk update \
	&& apk upgrade \
	&& apk add --no-cache zlib

# Copy only what is needed for bootstrap (adjust if more needed later)
COPY src/ ./src/
COPY Start-PSmediaManager.ps1 ./
# PSmediaManager.ps1 already resides in src/ and was copied above; no extra COPY needed.

# Create and switch to non-root user for runtime security
RUN adduser -D -u 1000 psmm && chown -R psmm:psmm /app
USER psmm

# Default entrypoint (can be overridden)
ENTRYPOINT ["pwsh","-NoLogo","-File","Start-PSmediaManager.ps1"]

# Security hardening hints for runtime (documented; may be enforced by orchestrator):
# - Run with read-only root filesystem
# - Drop capabilities and set no-new-privileges
# - Limit resources and disallow privilege escalation
