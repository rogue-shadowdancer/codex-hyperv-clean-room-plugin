[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Repository = 'rogue-shadowdancer/codex-hyperv-clean-room-plugin',

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-f0-9]{40}$')]
    [string]$ExpectedMasterCommit,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^0\.4\.1\+codex\.[0-9]{14}$')]
    [string]$ExpectedBuildVersion,

    [ValidateNotNullOrEmpty()]
    [string]$InstallRoot = (Join-Path $HOME 'plugins\hyperv-clean-room'),

    [ValidateNotNullOrEmpty()]
    [string]$MarketplacePath = (Join-Path $HOME '.agents\plugins\marketplace.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'validate-v032-release-readback.ps1') `
    -Repository $Repository `
    -ExpectedMasterCommit $ExpectedMasterCommit `
    -InstallRoot $InstallRoot `
    -MarketplacePath $MarketplacePath `
    -ReleaseVersion '0.4.1' `
    -ExpectedBuildVersion $ExpectedBuildVersion
