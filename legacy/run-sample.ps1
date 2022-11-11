$configdir = "C:\Program Files\OpenVPN\config"
$basecmd = ".\Test-OpenVPN.ps1"

Function do_test([string]$tests, [string]$configname, [array]$ping) {
    $cmdline = "`"${basecmd}`" ${tests} -Config `"${configdir}\${configname}`" -Ping ${ping}"
    Invoke-Expression "& $cmdline"

}

$tests = "-TestCmdexe"
do_test "$tests" "university.ovpn" "10.8.21.9, fd00:feed:51:3::1"

$tests = "-TestCmdexe -TestGui -TestService"
do_test "$tests" "company.ovpn" "10.10.112.100"
do_test "$tests" "home.ovpn" "192.168.0.81"