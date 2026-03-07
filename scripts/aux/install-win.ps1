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
    # Perform the operation for the current user profile only
    [parameter(ParameterSetName="user")]
    [switch]
    $user,

    # Perform the operation system-wide (needs elevated privileges)
    [parameter(ParameterSetName="system")]
    [switch]
    $system,

    # Rather than installing the native component (default), uninstall it
    [switch]
    $uninstall,

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

    Set-Content $env:TMP\notify-server.zip -Value $decoded -Encoding Byte
    Expand-Archive -Path $env:TMP\notify-server.zip -DestinationPath $env:TMP\notify-server -Force
}

$nativeManifest = @'
%NATIVE_MANIFEST%
'@

$registryKeys = @{
    'firefox' = 'SOFTWARE\Mozilla\NativeMessagingHosts'
    'chrome' = 'SOFTWARE\Google\Chrome\NativeMessagingHosts'
}

$allowedExtensions = @{
    'firefox' = '"allowed_extensions": ["%FF_EXT_ID%"]'
    'chrome' = '"allowed_origins": ["%CHROME_EXT_ID%"]'
}

# Install the server binary and native manifest
if (!$uninstall) {
    Expand-ServerBinary
}

if ($system) {
    $nativeInstallPath = "$env:PROGRAMFILES\tab-reload-notify"
} else {
    $nativeInstallPath = "$env:LOCALAPPDATA\tab-reload-notify"
}

if ($uninstall) {
    Remove-Item -Path $nativeInstallPath\notify-server.exe -Force
} else {
    New-Item -Path $nativeInstallPath -Type Directory -Force
    Copy-Item -Path $env:TMP\notify-server\notify-server.exe -Destination $nativeInstallPath\notify-server.exe
}

# For each browser, add/remove the native manifest info to/from the registry
foreach ($browser in $browsers) {
    if ($system) {
        $regPath = "HKLM:\$($registryKeys[$browser])\tab_reload_notify_server"
    } else {
        $regPath = "HKCU:\$($registryKeys[$browser])\tab_reload_notify_server"
    }

    if ($uninstall) {
        Remove-Item -Path $regPath -Force
        Remove-Item -Path $nativeInstallPath\native-manifest.$browser.json -Force
    } else {
        if (!(Test-Path -Path $regPath)) {
            New-Item -Path $regPath -Value $nativeInstallPath\native-manifest.$browser.json -Force
        }

        $nativeManifest -replace '%ALLOWED%', $allowedExtensions[$browser] | Out-File -Encoding utf8 -FilePath $nativeInstallPath\native-manifest.$browser.json
    }
}

Write-Output ''
Write-Output 'You may need to log out or reboot for registry changes to take effect.'
