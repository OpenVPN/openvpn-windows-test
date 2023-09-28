#Requires -Version 7

param (
    [ValidateSet("Default", "OvpnDco", "Wintun", "TapWindows6", "All")]
    [string]$Driver = "Default",

    # use openvpn-gui and service to start/stop connections
    [int]$UseGUI = 0,

    [string]$CA = "c:/Temp/openvpn2_ta/ca.crt",
    [string]$CERT = "c:/Temp/openvpn2_ta/lev-tclient.crt",
    [string]$KEY = "c:/Temp/openvpn2_ta/lev-tclient.key",

    [string[]]$Tests = "All",

    # use "Return" instead of "exit" at the end of execution, useful when called from Invoke-Command
    # (cannot use switch parameter with Invoke-Command -FilePath -ArgumentList)
    [int]$SuppressExit = 0
)

$OPENVPN_GUI_EXE = "c:\Program Files\OpenVPN\bin\openvpn-gui.exe"
$OPENVPN_EXE = "c:\Program Files\OpenVPN\bin\openvpn.exe"

$MANAGEMENT_PORT="58581"

$REMOTE = "conn-test-server.openvpn.org"

$BASE_P2MP=@"
client
tls-cert-profile insecure
ca $CA
cert $CERT
key $KEY
remote-cert-tls server
verb 3
setenv UV_NOCOMP 1
push-peer-info
"@

$PING4_HOSTS_1=@("10.194.1.1", "10.194.0.1")
$PING6_HOSTS_1=@("fd00:abcd:194:1::1", "fd00:abcd:194:0::1")

$PING4_HOSTS_2=@("10.194.2.1", "10.194.0.1")
$PING6_HOSTS_2=@("fd00:abcd:194:2::1", "fd00:abcd:194:0::1")

$PING4_HOSTS_4=@("10.194.4.1", "10.194.0.1")
$PING6_HOSTS_4=@("fd00:abcd:194:4::1", "fd00:abcd:194:0::1")

$ALL_TESTS = [ordered]@{
    "1" = @{
        Title="tcp / p2pm / top net30"
        Conf=@"
$BASE_P2MP
dev tun
proto tcp4
remote $REMOTE
port 51194
"@
        Ping4Hosts=$PING4_HOSTS_1
        Ping6Hosts=$PING6_HOSTS_1
    }
    "1a" = @{
        Title="tcp*6* / p2pm / top net30"
        Conf=@"
$BASE_P2MP
dev tun3
proto tcp6-client
remote $REMOTE
port 51194
server-poll-timeout 10
"@
        Ping4Hosts=$PING4_HOSTS_1
        Ping6Hosts=$PING6_HOSTS_1
    }
    "2" = @{
        Title="udp / p2pm / top net30"
        Conf=@"
$BASE_P2MP
dev tun
proto udp4
remote $REMOTE
port 51194
"@
        Ping4Hosts=$PING4_HOSTS_2
        Ping6Hosts=$PING6_HOSTS_2
    }
    "2b" = @{
        Title="udp *6* / p2pm / top net30"
        Conf=@"
$BASE_P2MP
dev tun
proto udp6
remote $REMOTE
port 51194
"@
        Ping4Hosts=$PING4_HOSTS_2
        Ping6Hosts=$PING6_HOSTS_2
    }
    "2f" = @{
        Title="UDP / p2pm / top net30 / pull-filter -> ipv6-only"
        Conf=@"
$BASE_P2MP
dev tun
proto udp
remote $REMOTE
port 51194
pull-filter accept ifconfig-
pull-filter ignore ifconfig
"@
        Ping4Hosts=@()
        Ping6Hosts=$PING6_HOSTS_2
    }
    "3" = @{
        Title="udp / p2pm / top subnet"
        Conf=@"
$BASE_P2MP
dev tun
proto udp4
remote $REMOTE
port 51195
"@
        Ping4Hosts=@("10.194.3.1", "10.194.0.1")
        Ping6Hosts=@("fd00:abcd:194:3::1", "fd00:abcd:194:0::1")
    }
    "3a" = @{
        Title="udp / p2pm / top subnet / dco-fail-on-pushed-comp-lzo"
        ErrorMessage="ERROR: Failed to apply push options"
        Driver="OvpnDco"
        Conf=@"
client
tls-cert-profile insecure
ca $CA
cert $CERT
key $KEY
remote-cert-tls server
verb 3
dev tun
proto udp4
remote $REMOTE
port 51195
setenv UV_COMP_LZO no
push-peer-info
"@
    }
    "3b" = @{
        Title="udp / p2pm / top subnet / accept-pushed-comp-lzo"
        Driver="TapWindows6"
        Conf=@"
client
tls-cert-profile insecure
ca $CA
cert $CERT
key $KEY
remote-cert-tls server
verb 3
dev tun
proto udp4
remote $REMOTE
port 51195
setenv UV_COMP_LZO no
push-peer-info
"@
        Ping4Hosts=@("10.194.3.1", "10.194.0.1")
        Ping6Hosts=@("fd00:abcd:194:3::1", "fd00:abcd:194:0::1")
    }
    "4" = @{
        Title="udp(4) / p2pm / tap"
        Conf=@"
$BASE_P2MP
dev tap
proto udp4
remote $REMOTE
port 51196
route-ipv6 fd00:abcd:195::/48 fd00:abcd:194:4::ffff
"@
        Ping4Hosts=$PING4_HOSTS_4
        Ping6Hosts=$PING6_HOSTS_4
    }
    "4a" = @{
        Title="udp(6) / p2pm / tap3 / topo subnet"
        Conf=@"
$BASE_P2MP
dev tap3
proto udp6
remote $REMOTE
port 51196
topology subnet
"@
        Ping4Hosts=$PING4_HOSTS_4
        Ping6Hosts=$PING6_HOSTS_4
    }
    "4b" = @{
        Title="udp / p2pm / tap / ipv6-only (pull-filter) / MAC-Addr"
        Conf=@"
$BASE_P2MP
dev tap
proto udp
remote $REMOTE
port 51196
pull-filter accept ifconfig-
pull-filter ignore ifconfig
lladdr 00:aa:bb:c0:ff:ee
"@
        Ping4Hosts=@()
        Ping6Hosts=$PING6_HOSTS_4
    }
    "5" = @{
        Title="udp / p2pm / top net30 / ipv6 112"
        Conf=@"
$BASE_P2MP
dev tun
proto udp4
remote $REMOTE
port 51197
"@
        Ping4Hosts=@("10.194.5.1", "10.194.0.1")
        Ping6Hosts=@("fd00:abcd:194:5::1", "fd00:abcd:194:0::1")
    }
    "6" = @{
        Driver="TapWindows6"
        Title="udp / p2pm / top subnet / --fragment 500"
        Conf=@"
$BASE_P2MP
dev tun
proto udp
remote $REMOTE
port 51198
fragment 500
"@
        Ping4Hosts=@("10.194.6.1", "10.194.0.1")
        Ping6Hosts=@("fd00:abcd:194:6::1", "fd00:abcd:194:0::1")
    }
}

function Test-ConnectionMs([switch]$IPv4, [switch]$IPv6, [array]$Hosts, $Count=20, $Delay=250) {
    $(64, 1440, 3000) | ForEach-Object {
        $bufferSize = $_
        Write-Host "Ping ""$Hosts"" $Count times with $bufferSize bytes..."

        # failures per host
        $failuresPerHost = [hashtable]::Synchronized(@{ })
        foreach ($h in $Hosts) {
            $failuresPerHost[$h] = 0
        }

        for ($i = 0; $i -lt $Count; ++$i) {
            # this is because we have nested scope, Invoke-Command and Parallel
            # see https://stackoverflow.com/questions/57700435/usingvar-in-start-job-within-invoke-command
            $pingPerHost = [scriptblock]::Create(
@'
            $startTime = Get-Date
            $ok = Test-Connection -TargetName $_ -IPv4:$using:IPv4 -IPv6:$using:IPv6 -Count 1 -BufferSize $using:bufferSize -Quiet
            if (!$ok) {
                $fph = $using:failuresPerHost
                ++$fph[$_]
            }
            $endTime = Get-Date
            $neededDelay = $Delay - (($endTime - $startTime).TotalMilliseconds)
            # sleep if ping took less time than passed $Delay value
            if ($neededDelay -gt 0) {
                Start-Sleep -Milliseconds $neededDelay
            }
'@
            )

            # ping hosts in parallel
            $hosts | ForEach-Object -Parallel $pingPerHost
        }

        foreach ($en in $failuresPerHost.GetEnumerator()) {
            # test failed if all pings have failed
            if ($en.Value -eq $Count) {
                throw "ping $($en.Key) failed"
            } elseif ($en.Value -gt 0) {
                # print failure rate if some pings have failed
                $rate = ($en.Value / $Count).ToString("0.00")
                Write-Host "failure rate for $($en.Key): $rate"
            }
        }
    }
}

function Test-Pings ([array]$hosts4, [array]$hosts6) {
    if ($hosts4) {
        Test-ConnectionMs -IPv4 -Hosts $hosts4
    }
    if ($hosts6) {
        Test-ConnectionMs -IPv6 -Hosts $hosts6
    }
}

Function Stop-OpenVPN([string]$ConfName) {
    if ($ConfName -and $UseGUI) {
        Write-Host "Stop openvpn via gui command"
        & $OPENVPN_GUI_EXE --command disconnect $ConfName
        Start-Sleep -Seconds 1
    } else {
        # if there is no gui, we stop openvpn via management
        if (!$UseGUI) {
            $socket = New-Object System.Net.Sockets.TcpClient("127.0.0.1", $MANAGEMENT_PORT)

            if ($socket) {
                Write-Host "Stop openvpn via management"
                $stream = $socket.GetStream()
                $writer = New-Object System.IO.StreamWriter($Stream)

                Start-Sleep -Seconds 1
                $writer.WriteLine("signal SIGTERM")
                $writer.Flush()
                Start-Sleep -Seconds 3
                return
            }
        }

        $processes = (Get-Process|Where-Object { $_.ProcessName -eq "openvpn" })
        foreach ($process in $processes) {
            Write-Host "Stop openvpn process $($process.Id)"
            Stop-Process $process.Id -Force
        }
    }
}

function Start-OpenVPN ([string] $ConfName, [string]$Conf, [string]$Driver, [string]$ErrorMessage) {
    $windowsDriver = ""
    switch ($Driver) {
        "OvpnDco" {
            $windowsDriver = "windows-driver ovpn-dco"
        }
        "TapWindows6" {
            $windowsDriver = "windows-driver tap-windows6"
        }
        "wintun" {
            $windowsDriver = "windows-driver wintun"
        }
    }
    $Conf += "`n$windowsDriver"
    $log_file = "$ENV:UserProfile\OpenVPN\log\$ConfName.log"

    $CONFIG_DIR = "$ENV:UserProfile\OpenVPN\config"
    $LOG_DIR = "$ENV:UserProfile\OpenVPN\log"

    New-Item -Path "$CONFIG_DIR" -type directory -Force | Out-Null
    New-Item -Path "$LOG_DIR" -type directory -Force | Out-Null

    # if we don't use gui, we need to specify log file and management for graceful shutdown
    if (!$UseGUI) {
        $Conf += "`nlog $log_file".Replace("\", "\\")
        $Conf += "`nmanagement 127.0.0.1 $MANAGEMENT_PORT"
    }

    # write config to config dir
    $Conf | Out-File "$CONFIG_DIR\\$ConfName.ovpn"

    Remove-Item $log_file -ErrorAction Ignore

    if ($UseGUI) {
        & $OPENVPN_GUI_EXE --command rescan
        Start-Sleep -Seconds 1

        & $OPENVPN_GUI_EXE --connect $ConfName
    } else {
        Start-Process -NoNewWindow -FilePath $OPENVPN_EXE -ArgumentList "$CONFIG_DIR\\$ConfName.ovpn" -ErrorAction Stop -RedirectStandardError error-$ConfName.log -RedirectStandardOutput output-$ConfName.log
    }

    for ($i = 0; $i -le 30; ++$i) {
        Start-Sleep -Seconds 1
        if (!(Test-Path $log_file)) {
            Write-Host "Waiting for log $log_file to appear..."
        } else {
            if ($ErrorMessage) {
                if (Select-String -Pattern $ErrorMessage -Path $log_file) {
                    return
                } else {
                    Write-Host "Waiting for error message to appear..."
                }
            } else {
                if (Select-String -Pattern "Initialization Sequence Completed" -Path $log_file) {
                    return
                } else {
                    Write-Host "Waiting for connection to be established..."
                }
            }
        }
    }

    if ($ErrorMessage) {
        Write-Error "Cannot find error message" -ErrorAction Stop
    }
    else {
        Write-Error "Cannot establish VPN connection" -ErrorAction Stop
    }
}

function Start-SingleDriverTests([string]$Drv) {
    $passed = [String[]]@()
    $failed = [String[]]@()
    if ($Tests -eq "All") {
        $tests_to_run = $ALL_TESTS.Keys
    } else {
        $tests_to_run = $Tests
    }

    $gui = ""
    if ($UseGUI) {
        $gui = "and openvpn-gui / service"
    }

    Write-Host "`r`nWill run tests $($tests_to_run -join ",") using driver $Drv $gui"
    foreach ($t in $tests_to_run) {
        if (!$ALL_TESTS.Contains($t)) {
            Write-Error "Test $t is missing"
            continue
        }

        $test = $ALL_TESTS[$t]

        if ($test.Driver -and ($Drv -ne $test.Driver)) {
            Write-Warning "Skip test $t because it requires driver $($test.Driver)"
            continue
        }

        Write-Host "Running Test $t ($($test.Title))"

        try {
            $conf_name = "test_" + $t + "_$Drv"
            Start-OpenVPN -ConfName $conf_name -Conf $test.Conf -Driver $Drv -ErrorMessage $test.ErrorMessage

            if (!$test.ErrorMessage) {
                # give some time for network settings to settle
                Start-Sleep -Seconds 3

                Test-Pings $test.Ping4Hosts $test.Ping6Hosts
            }

            Write-Host "PASS`r`n"
            $passed += ,$t
        }
        catch {
            Write-Host "FAIL: $_`r`n"
            $failed += ,$t
        }
        finally {
            Stop-OpenVPN $conf_name
        }
    }

    return [System.Tuple]::Create($passed, $failed)
}

$results = @()
if ($Driver -eq "All") {
    # skip Wintun since it requires SYSTEM elevation
    foreach ($d in @("OvpnDco", "TapWindows6")) {
        $r = Start-SingleDriverTests $d
        $results += ,[System.Tuple]::Create($d, $r.Item1, $r.Item2)
    }
} else {
    $r = Start-SingleDriverTests $Driver
    $results += ,[System.Tuple]::Create($Driver, $r.Item1, $r.Item2)
}

$exitcode = 0
Write-Host "`r`nSUMMARY:"
foreach ($r in $results) {
    Write-Host "Driver $($r.Item1)`r`nPassed: $($r.Item2)`r`nFailed: $($r.Item3)`r`n"
    if ($r.Item3) {
        $exitcode = 1
    }
}

if ($SuppressExit) {
    return $exitcode
}
else {
    exit $exitcode
}
