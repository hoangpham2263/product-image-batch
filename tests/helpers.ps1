# Shared location for test fixtures and temporary artifacts, including standalone suites.
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/application/workspace.ps1')
$TestWorkspaceRoot = (Initialize-ProjectWorkspace (Split-Path $PSScriptRoot -Parent)).Tests
