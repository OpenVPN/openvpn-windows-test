Param (
    [string]$Installer,
    [switch]$TestUpgrade,
    [switch]$TestCleanInstall,
    [switch]$Verbose,
    [switch]$Help
)

Function Show-Usage {
    Write-Host "Usage: Test-Installer.ps1 -Installer <installer-file> [-Verbose] [-TestUpgrade] [-TestCleanInstall] [-Help]"
    Write-Host
    Write-Host "Parameters:"
    Write-Host "   -Installer        Path to the OpenVPN installer you wish to test"
    Write-Host "   -Verbose          Show what is happening, even if there is nothing noteworthy to report"
    Write-Host "   -TestUpgrade      Test reinstalling on top of old installation"
    Write-Host "   -TestCleanInstall Test full uninstall -> install cycle"
    Write-Host "   -Help             Display this help"
    exit 1
}

if ($Help) {
    Show-Usage
}

if (! $installer) {
    Show-Usage
}

if (! (Test-Path $installer -PathType leaf)) {
    Write-Host "ERROR: Invalid file!"
    Show-Usage
}

Function Get-ServiceStates {
    $service_states = New-Object –TypeName PSObject
    $services = "OpenVPNService", "OpenVPNServiceInteractive", "OpenVPNServiceLegacy"
    foreach ($service in $services) {
        Add-Member -InputObject $service_states -NotePropertyName "${service}_Status" -NotePropertyValue ([string](Get-Service $service).Status)
        Add-Member -InputObject $service_states -NotePropertyName "${service}_StartMode"-NotePropertyValue ([string](Get-WmiObject -Class Win32_Service -Property StartMode -Filter "Name='$service'").Startmode)
    }
    return $service_states
}

function Run-Installer($installer) {
    Write-Verbose "Running OpenVPN installer"

    & $installer /S

    # Wait for the installer to finish. It would be cleaner to just use
    #
    # Start-Process -Wait -FilePath $installer -ArgumentList "/S"
    #
    # but that generates a warning popup which the user has to manually
    # skip.
    $processname = [string](Get-ChildItem $installer).BaseName
    while (Get-Process -ProcessName $processname -ErrorAction Ignore) {
        Start-Sleep -Seconds 1
    }
    Write-Verbose "Install finished"
}

function Run-Uninstaller {
    Write-Verbose "Running OpenVPN uninstaller"

    # Uninstaller seems to fork immediately, so launching it with
    #
    # Start-Process -Wait -FilePath $uninstaller -ArgumentList "/S"
    #
    # Exits immediately. Unlike the installer, running the uninstaller
    # from within Start-Process does not trigger any warnings.
    #
    & 'C:\Program Files\OpenVPN\Uninstall.exe' /S

    # Due to above just sleep a while
    Start-Sleep -Seconds 7

    Write-Verbose "Uninstall finished"
}

function Compare-ServiceStates($service_states_before,$service_states_after) {

    # Create an arraylist with all the service state property names
    $service_state_names = [System.Collections.ArrayList]@()
    foreach ($property in ($service_states_before|Get-Member -Type NoteProperty)) {
        $service_state_names.Add(([string]$property.Name)) > $null
    }

    # Compare states before and after install
    $no_changes = $true
    foreach ($property_name in $service_state_names) {
        $before = $service_states_before.$property_name
        $after = $service_states_after.$property_name
        if ($before -ne $after) {
            Write-Host "${property_name} has changed from ${before} to ${after}"
            $no_changes = $false
        }
    }

    if ($no_changes) {
        Write-Verbose "No changes during install"
    }

}

if ($TestUpgrade) {
    $service_states_before = Get-ServiceStates
    Run-Installer $installer
    $service_states_after = Get-ServiceStates

    # To verify that the service state check works, use
    #
    # $service_states_after.OpenVPNService_StartMode = "Changed"

    Compare-ServiceStates $service_states_before $service_states_after
}

if ($TestCleanInstall) {
    $service_states_before = Get-ServiceStates
    Run-Uninstaller
    Run-Installer $installer
    $service_states_after = Get-ServiceStates
    Compare-ServiceStates $service_states_before $service_states_after
}