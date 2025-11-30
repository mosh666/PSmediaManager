param(
    [string]$Tag = 'psmediamanager:scan'
)

Write-Host "Building Docker image '$Tag' for vulnerability scanning..." -ForegroundColor Cyan

# Basic build (no cache busting; adjust if needed)
docker build -t $Tag .

if ($LASTEXITCODE -eq 0) {
    Write-Host "Image '$Tag' built successfully." -ForegroundColor Green
} else {
    Write-Host "Docker build failed (exit $LASTEXITCODE)." -ForegroundColor Red
    exit $LASTEXITCODE
}
