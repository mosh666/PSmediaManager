# Minimal Dockerfile for PSmediaManager vulnerability scanning
# Built for Trivy/Codacy CLI to have a container context.

FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04
LABEL org.opencontainers.image.source="https://github.com/mosh666/PSmediaManager"
LABEL org.opencontainers.image.title="PSmediaManager"
LABEL org.opencontainers.image.description="Minimal container image for security scanning of PSmediaManager"

# Set working directory
WORKDIR /app

# Apply latest security updates to base packages
RUN apt-get update \
	&& apt-get dist-upgrade -y \
	&& apt-get autoremove -y \
	&& rm -rf /var/lib/apt/lists/*

# Copy only what is needed for bootstrap (adjust if more needed later)
COPY src/ ./src/
COPY Start-PSmediaManager.ps1 ./
# PSmediaManager.ps1 already resides in src/ and was copied above; no extra COPY needed.

# Create and switch to non-root user for runtime security
RUN useradd -m -u 1000 psmm && chown -R psmm:psmm /app
USER psmm

# Default entrypoint (can be overridden)
ENTRYPOINT ["pwsh","-NoLogo","-File","Start-PSmediaManager.ps1"]
