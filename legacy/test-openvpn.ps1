Param (
    [string]$Openvpn,
    [string]$Gui,
    [string]$Config,
    [array]$Ping,
    [switch]$TestCmdexe,
    [switch]$TestService,
    [switch]$TestRespawn,
    [switch]$TestGui,
    [switch]$Help
)

Function Show-Usage {
    Write-Host "Usage: Test-Openvpn.ps1 -Config <openvpn-config-file> -Ping <hosts> [-Openvpn <openvpn-exe>] [-Gui <openvpn-gui-exe>] [-TestCmdexe] [-TestService] [-TestRespawn] [-TestGui] [-Help]"
    Write-Host
    Write-Host "Parameters:"
    Write-Host "   -Openvpn     Path to openvpn.exe (defaults to value in registry)"
    Write-Host "   -Gui         Path to openvpn-gui.exe (as above, but openvpn.exe replaced with openvpn-gui.exe)"
    Write-Host "   -Config      Path to the OpenVPN configuration file"
    Write-Host "   -Ping        Target host(s) inside VPN to ping (should succeed). Separate multiple entries with commas."
    Write-Host "   -Suspend     Test suspend and resume [UNIMPLEMENTED]"
    Write-Host "   -TestCmdexe  Test connection from the command-line"
    Write-Host "   -TestGui     Test OpenVPN-GUI"
    Write-Host "   -TestService Test openvpnserv2.exe"
    Write-Host "   -TestRespawn Test if openvpnserv2 is able to respawn a dead connection properly"
    Write-Host "   -Help        Display this help"
    Write-Host
    Write-Host "Example: .\Test-Openvpn.ps1 -Config ""C:\Program Files\OpenVPN\config\company.ovpn"" -Ping 192.168.40.7 -TestCmdexe -TestService -TestGui"
}

Function Verify-Path ([string]$mypath) {
    if (! (Test-Path $mypath -PathType leaf) ) {
        Write-Host "ERROR: ${mypath} not found or not a file!"
        Exit 1
    }
}

$exe_path = (Get-ItemProperty 'HKLM:\SOFTWARE\OpenVPN' -Name 'exe_path').exe_path

if (! $Openvpn) {
    $Openvpn = $exe_path
}

if (! $Gui) {
    # Assume openvpn-gui.exe is in the same directory as openvpn.exe
    $exe_dir = $exe_path.TrimEnd('openvpn.exe')
    $Gui = (Join-Path $exe_dir 'openvpn-gui.exe')
}

if (! ($Config -and $Ping) -or $Help) {
    Show-Usage
    Exit 1
}

# Absolute directory from which this script is launched
$cwd = (Get-Item -Path ".\" -Verbose).FullName

# Separate OpenVPN configuration file path from the file name. This allows us
# to use relative certificate/key paths in OpenVPN configuration files.
$Configname = $Config.Split("\")[-1]
if ($Config -match '\\') {
    $Configdir = $Config -replace $Configname, '' -Replace '\\$'
} else {
    $Configdir = '.'
}


Verify-Path $Openvpn
Verify-Path $Gui
Verify-Path $Config

Function Stop-Generic ([string]$processname) {
    $processes = (Get-Process|Where-Object { $_.ProcessName -eq "${processname}" })
    foreach ($process in $processes) {
        Stop-Process $process.Id -Force
    }
}

Function Stop-Management {
    $socket = New-Object System.Net.Sockets.TcpClient("127.0.0.1", "58581")

    if ($socket) {
        $Stream = $Socket.GetStream()
        $Writer = New-Object System.IO.StreamWriter($Stream)

        Start-Sleep -Seconds 1
        $writer.WriteLine("signal SIGTERM")
        $writer.Flush()
        Start-Sleep -Seconds 5
    } else {
        Stop-Generic "openvpn"
    }
}

Function Stop-Openvpn {
    Stop-Generic "openvpn"
}

Function Stop-Gui {
    & $Gui --command disconnect_all
}

Function Stop-Openvpnservice {
    foreach ($service in 'OpenVPNService', 'OpenVPNServiceLegacy') {
        if (Get-Service -Erroraction Ignore $service) {
            Stop-Service $service
            (Get-Service $service).WaitForStatus('Stopped')
        }
    }
}

# Stop all openvpn-related processes
Function Clean-Up {
    # Kill all instances of (stock) OpenVPN
    Stop-Openvpnservice
    Stop-Generic "openvpn"
    Stop-Gui
}

Function Check-Connectivity ([string]$test_type, [array]$ping) {

    Start-Sleep -Seconds 10

    foreach ($target in $ping) {
        $connected = (Test-Connection -Computername $target -Quiet)

        if ($connected) {
            $result = "SUCCESS"
        } else {
            $result = "FAILURE"
        }

        Write-Host "${Configname} ${test_type} connection to ${target}: ${result}"
    }
}

Function Test-Cmdexe {

    # Create a .bat file dynamically for launching the OpenVPN connection in a
    # separate cmd.exe windows. This approach was chosen as getting all the
    # whitespace in openvpn.exe command-line quoted properly so that cmd.exe /c
    # works properly was simply too nasty to deal with. Cmd.exe is used instead of
    # Powershell as it allows sending signals (e.g. F4=EXIT) to the OpenVPN process. 

    $bat = "${Configname}.bat"
    $pidfile = "${cwd}\${Configname}.pid"
    Set-Content -Path "${bat}" -Value """${Openvpn}"" --management 127.0.0.1 58581 --config ""${config}"" --writepid ""${pidfile}"" --cd ""${Configdir}"" & exit"
    Start-Process -FilePath $env:ComSpec -ArgumentList "/c", "start", "${bat}"
    Check-Connectivity "cmdexe" $ping
    Stop-Management
    Remove-Item "${pidfile}"
    Remove-Item "${bat}"
}

Function Test-Gui {
    & $gui --connect "${configname}"
    Check-Connectivity "gui" $ping
    Stop-Gui

}

Function Test-Service {
    $moved = @()
    $configs = (Get-ChildItem "${configdir}" -Filter "*.ovpn")
    foreach ($config in $configs) {
        $current = $config.Name
        if  ( ! ($current -eq $configname) ) {
            Move-Item "${configdir}\${current}" "${cwd}\${current}"
            if ($?) {
                $moved += ("${cwd}\${current}")
            }
        }
    }

    Start-Service OpenVPNService
    Check-Connectivity "openvpnserv2" $ping

    if ($TestRespawn) {
        Stop-Openvpn
        Check-connectivity "openvpnserv2-respawn" $ping
    }
    Stop-Service OpenVPNService

    foreach ($move in $moved) {
        Move-Item "${move}" "${configdir}\"
    }
}

Clean-Up

if ($TestCmdExe) { Test-Cmdexe }
if ($TestGui) { Test-Gui }
if ($TestService) { Test-Service }