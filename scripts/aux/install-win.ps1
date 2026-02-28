#requires -version 5.1

<#
    .SYNOPSIS
        Install script for notify-server (tab-reload-notify)
    .DESCRIPTION
        This script will install notify-server, the native component
        for the tab-reload-notify browser extension.
#>

[CmdletBinding(DefaultParameterSetName="user")]
param (
    # Install for the current user profile only
    [parameter(ParameterSetName="user")]
    [switch]
    $user,

    # Install system-wide (needs elevated privileges)
    [parameter(ParameterSetName="system")]
    [switch]
    $system,

    # Browsers to register the native manifest to. All supported browsers by default.
    [ValidateSet('firefox', 'chrome')]
    [string[]]
    $browsers = @('firefox', 'chrome')
)

$currentUser = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')

if ($system -and !$isAdmin) {
    throw "You have to run this script with elevated privileges when using the `-system' switch."
}

function Expand-ServerBinary {
    # DO NOT EDIT THIS STRING!
    $b64 = @'
%B64_ZIP_DATA%
'@

    $decoded = [System.Convert]::FromBase64String($b64)

    Set-Content $env:TMP\notify-server.zip -Value $decoded -AsByteStream
    Expand-Archive -Path $env:TMP\notify-server.zip -DestinationPath $env:TMP\notify-server
}

$nativeManifest = @'
%NATIVE_MANIFEST%
'@

$registryKeys = @{
    'firefox' = 'SOFTWARE\Mozilla\NativeMessagingHosts'
    'chrome' = 'SOFTWARE\Google\Chrome\NativeMessagingHosts'
}

# Install the server binary and native manifest
Expand-ServerBinary

if ($system) {
    $nativeInstallPath = "$env:PROGRAMFILES\tab-reload-notify"
} else {
    $nativeInstallPath = "$env:LOCALAPPDATA\tab-reload-notify"
}

New-Item -Path $nativeInstallPath -Type Directory

Copy-Item -Path $env:TMP\notify-server\notify-server.exe -Destination $nativeInstallPath\notify-server.exe
$nativeManifest | Out-File -FilePath $nativeInstallPath\native-manifest.json

# For each browser, add the native manifest info to the registry
foreach ($browser in $browsers) {
    if ($system) {
        New-Item -Path HKLM:\$registryKeys[$browser]\tab_reload_notify_server -Value $nativeManifest\native-manifest.json
    } else {
        New-Item -Path HKCU:\$registryKeys[$browser]\tab_reload_notify_server -Value $nativeInstallPath\native-manifest.json
    }
}
