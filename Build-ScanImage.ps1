param(
    [string]$Tag = 'psmediamanager:scan'
)

Write-Information "Building Docker image '$Tag' for vulnerability scanning..." -InformationAction Continue

# Basic build (no cache busting; adjust if needed)
docker build -t $Tag .

if ($LASTEXITCODE -eq 0) {
    Write-Information "Image '$Tag' built successfully." -InformationAction Continue
} else {
    Write-Error "Docker build failed (exit $LASTEXITCODE)."
    exit $LASTEXITCODE
}
