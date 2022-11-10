#Requires -Version 7

param (
    [ValidateSet("Default", "OvpnDco", "Wintun", "TapWindows6", "All")]
    [string]$Driver = "Default",

    [string]$CA = "c:\Temp\openvpn2_ta\ca.crt",
    [string]$CERT = "c:\Temp\openvpn2_ta\lev-tclient.crt",
    [string]$KEY = "c:\Temp\openvpn2_ta\lev-tclient.key",

    [string[]]$Tests = "All"
)

$OPENVPN_EXE = "c:\Program Files\OpenVPN\bin\openvpn.exe"
$REMOTE = "conn-test-server.openvpn.org"

$BASE_P2MP="--client --tls-cert-profile insecure --ca $CA --cert $CERT --key $KEY --remote-cert-tls server --verb 3 --setenv UV_NOCOMP 1 --push-peer-info --management 127.0.0.1 58581"

$PING4_HOSTS_1=@("10.194.1.1", "10.194.0.1")
$PING6_HOSTS_1=@("fd00:abcd:194:1::1", "fd00:abcd:194:0::1")

$PING4_HOSTS_2=@("10.194.2.1", "10.194.0.1")
$PING6_HOSTS_2=@("fd00:abcd:194:2::1", "fd00:abcd:194:0::1")

$PING4_HOSTS_4=@("10.194.4.1", "10.194.0.1")
$PING6_HOSTS_4=@("fd00:abcd:194:4::1", "fd00:abcd:194:0::1")

$ALL_TESTS = [ordered]@{
    "1" = @{
        Title="tcp / p2pm / top net30"
        Conf="$BASE_P2MP --dev tun --proto tcp4 --remote $REMOTE --port 51194"
        Ping4Hosts=$PING4_HOSTS_1
        Ping6Hosts=$PING6_HOSTS_1
    }
    "1a" = @{
        Title="tcp*6* / p2pm / top net30"
        Conf="$BASE_P2MP --dev tun3 --proto tcp6-client --remote $REMOTE --port 51194 --server-poll-timeout 10"
        Ping4Hosts=$PING4_HOSTS_1
        Ping6Hosts=$PING6_HOSTS_1
    }
    "2" = @{
        Title="udp / p2pm / top net30"
        Conf="$BASE_P2MP --dev tun --proto udp4 --remote $REMOTE --port 51194"
        Ping4Hosts=$PING4_HOSTS_2
        Ping6Hosts=$PING6_HOSTS_2
    }
    "2b" = @{
        Title="udp *6* / p2pm / top net30"
        Conf="$BASE_P2MP --dev tun --proto udp6 --remote $REMOTE --port 51194"
        Ping4Hosts=$PING4_HOSTS_2
        Ping6Hosts=$PING6_HOSTS_2
    }
    "2f" = @{
        Title="UDP / p2pm / top net30 / pull-filter -> ipv6-only"
        Conf="$BASE_P2MP --dev tun --proto udp --remote $REMOTE --port 51194 --pull-filter accept ifconfig- --pull-filter ignore ifconfig"
        Ping4Hosts=@()
        Ping6Hosts=$PING6_HOSTS_2
    }
    "3" = @{
        Title="udp / p2pm / top subnet"
        Conf="$BASE_P2MP --dev tun --proto udp4 --remote $REMOTE --port 51195"
        Ping4Hosts=@("10.194.3.1", "10.194.0.1")
        Ping6Hosts=@("fd00:abcd:194:3::1", "fd00:abcd:194:0::1")
    }
    "4" = @{
        Title="udp(4) / p2pm / tap"
        Conf="$BASE_P2MP --dev tap --proto udp4 --remote $REMOTE --port 51196 --route-ipv6 fd00:abcd:195::/48 fd00:abcd:194:4::ffff"
        Ping4Hosts=$PING4_HOSTS_4
        Ping6Hosts=$PING6_HOSTS_4
    }
    "4a" = @{
        Title="udp(6) / p2pm / tap3 / topo subnet"
        Conf="$BASE_P2MP --dev tap3 --proto udp6 --remote $REMOTE --port 51196 --topology subnet"
        Ping4Hosts=$PING4_HOSTS_4
        Ping6Hosts=$PING6_HOSTS_4
    }
    "4b" = @{
        Title="udp / p2pm / tap / ipv6-only (pull-filter) / MAC-Addr"
        Conf="$BASE_P2MP --dev tap --proto udp --remote $REMOTE --port 51196 --pull-filter accept ifconfig- --pull-filter ignore ifconfig --lladdr 00:aa:bb:c0:ff:ee"
        Ping4Hosts=@()
        Ping6Hosts=$PING6_HOSTS_4
    }
    "5" = @{
        Title="udp / p2pm / top net30 / ipv6 112"
        Conf="$BASE_P2MP --dev tun --proto udp4 --remote $REMOTE --port 51197"
        Ping4Hosts=@("10.194.5.1", "10.194.0.1")
        Ping6Hosts=@("fd00:abcd:194:5::1", "fd00:abcd:194:0::1")
    }
}

function Test-ConnectionMs([switch]$IPv4, [switch]$IPv6, [array]$Hosts, $Count=20, $Delay=250) {
    $(64, 1440, 3000) | ForEach-Object {
        Write-Host "Ping ""$Hosts"" $Count times with $_ bytes..."
        # failures per host
        $nFailures = New-Object int[] $Hosts.Length
        for ($i = 0; $i -lt $Count; ++$i) {
            # this returns bool array, item per host
            $ts1 = Get-Date
            $arr = Test-Connection -TargetName $Hosts -IPv4:$IPv4 -IPv6:$IPv6 -Count 1 -BufferSize $_ -Quiet
            for ($j = 0; $j -lt $arr.Length; ++$j) {
                if (!$arr[$j])
                {
                    ++$nFailures[$j]
                }
            }
            $ts2 = Get-Date
            $neededDelay = $Delay - (($ts2 - $ts1).TotalMilliseconds)
            if ($neededDelay -gt 0)
            {
                Start-Sleep -Milliseconds $neededDelay
            }
        }

        # test failed if all pings have failed
        for ($i = 0; $i -lt $Hosts.Length; ++$i) {
            if ($nFailures[$i] -eq $Count) {
                throw "ping $($Hosts[$i]) failed"
            } elseif ($nFailures[$i] -gt 0) {
                # print failure rate if some pings have failed
                $rate = ($nFailures[$i] / $Count).ToString("0.00")
                Write-Host "failure rate for $($Hosts[$i]): $rate"
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

Function Stop-OpenVPN {
    $socket = New-Object System.Net.Sockets.TcpClient("127.0.0.1", "58581")

    if ($socket) {
        $Stream = $Socket.GetStream()
        $Writer = New-Object System.IO.StreamWriter($Stream)

        Start-Sleep -Seconds 1
        $writer.WriteLine("signal SIGTERM")
        $writer.Flush()
        Start-Sleep -Seconds 3
    } else {
        $processes = (Get-Process|Where-Object { $_.ProcessName -eq "openvpn" })
        foreach ($process in $processes) {
            Stop-Process $process.Id -Force
        }
    }
}

function Start-OpenVPN ([string]$TestId, [string]$Conf, [string]$Driver) {
    $windowsDriver = ""
    switch ($Driver) {
        "OvpnDco" {
            $windowsDriver = " --windows-driver ovpn-dco"
        }
        "TapWindows6" {
            $windowsDriver = " --windows-driver tap-windows6"
        }
        "wintun" {
            $windowsDriver = " --windows-driver wintun"
        }
    }
    $Conf += $windowsDriver
    $logFile = "openvpn-$TestId-$Driver.log"
    $Conf += " --log $logFile"

    Start-Process -NoNewWindow -FilePath $OPENVPN_EXE -ArgumentList $Conf -ErrorAction Stop -RedirectStandardError error-$TestId-$Driver.log -RedirectStandardOutput output-$TestId-$Driver.log

    for ($i = 0; $i -le 30; ++$i) {
        Start-Sleep -Seconds 1
        if (Select-String -Pattern "Initialization Sequence Completed" -Path $logFile) {
            return
        }
    }

    Write-Error "Cannot establish VPN connection" -ErrorAction Stop
}

function Start-SingleDriverTests([string]$Driver) {
    $passed = @()
    $failed = @()
    if ($Tests -eq "All") {
        $tests_to_run = $ALL_TESTS.Keys
    } else {
        $tests_to_run = $Tests
    }
    Write-Host "`r`nWill run tests $($tests_to_run -join ",") using driver $Driver"
    foreach ($t in $tests_to_run) {
        if (!$ALL_TESTS.Contains($t)) {
            Write-Error "Test $t is missing"
            continue
        }

        $test = $ALL_TESTS[$t]
        Write-Host "Running Test $t ($($Test.Title))"

        try {
            Start-OpenVPN -TestId $t -Conf $test.Conf -Driver $Driver

            # give some time for network settings to settle
            Start-Sleep -Seconds 3

            Test-Pings $Test.Ping4Hosts $Test.Ping6Hosts
            Write-Host "PASS`r`n"
            $passed += ,$t
        }
        catch {
            Write-Host "FAIL: $_`r`n"
            $failed += ,$t
        }
        finally {
            Stop-OpenVPN
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

Write-Host "`r`nSUMMARY:"
foreach ($r in $results) {
    Write-Host "Driver $($r.Item1)`r`nPassed: $($r.Item2)`r`nFailed: $($r.Item3)`r`n"
}
