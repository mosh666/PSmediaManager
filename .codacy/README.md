# Codacy WSL Wrapper Usage

This folder contains helper scripts to run Codacy CLI and specific tools inside WSL for Windows users.

## Semgrep (bypass)

- Run Semgrep only with custom config and JSON output:
  - PowerShell:
    - `pwsh -NoProfile -File .\.codacy\Invoke-CodacyWSL.ps1 -RepositoryPath . -CliArguments "analyze --tool semgrep" -OutputFormat json -OutputFile semgrep-report.json -SemgrepArgs "--verbose" -Verbose`

## Trivy Secrets (bypass)

- Run Trivy secrets scan only (fast path), output JSON or SARIF:
  - JSON:
    - `pwsh -NoProfile -File .\.codacy\Invoke-CodacyWSL.ps1 -RepositoryPath . -CliArguments "analyze --tool trivy" -OutputFormat json -OutputFile trivy-secrets.json -Verbose`
  - SARIF:
    - `pwsh -NoProfile -File .\.codacy\Invoke-CodacyWSL.ps1 -RepositoryPath . -CliArguments "analyze --tool trivy" -OutputFormat sarif -OutputFile trivy-secrets.sarif -Verbose`
  - Extra flags:
    - Add via `-TrivyArgs "<flags>"` (e.g., `--skip-dirs .git`).

## Full Codacy CLI

- Run default Codacy analysis (tools from `.codacy/codacy.yaml`):
  - `pwsh -NoProfile -File .\.codacy\Invoke-CodacyWSL.ps1 -RepositoryPath . -CliArguments analyze -Verbose`

Notes

- Wrapper auto-detects WSL distro and converts Windows paths to `/mnt/<drive>/...`.
- Semgrep and Trivy bypasses execute the tools directly in WSL to allow tool-specific flags and outputs.
- For Trivy installation in WSL Ubuntu, use Aqua Security apt repo or install via package manager.
