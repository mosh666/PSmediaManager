#Requires -Version 7.5.4
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
$psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
$projectsManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Projects/PSmm.Projects.psd1'
