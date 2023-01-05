#Requires -Version 7
#Requires -Modules AWS.Tools.EC2

param (
    [string]$SSH_KEY = "c:\Users\lev\.ssh\openvpn2_win_ta",
    [string]$MSI_PATH = "OpenVPN-2.6git-amd64.msi",

    [ValidateSet("Default", "OvpnDco", "Wintun", "TapWindows6", "All")]
    [string]$Driver = "All",

    [string[]]$Tests = "All",
    [string]$InstanceName = "openvpn2-win-ta"
)

$INSTANCE_TYPE = "t3.small"
$IMAGE_ID = "ami-0acf3d8ed5bf3ec9d"
$SECURITY_GROUPS = @("sg-053fdd33bdc1fd2b6", "sg-004c2f4af3ee2e7c8")
$SUBNET_ID = "subnet-059c2f95ec662bd69"
$REGION = "eu-west-1"

$OPENVPN_EXE = "c:\Program Files\OpenVPN\bin\openvpn.exe"

function Test-Install([string]$IP, $Sess) {
    Write-Host "Test installation"

    # check that interactive service is installed and running
    $status = (Invoke-Command -Session $sess -ScriptBlock { (Get-Service -name 'OpenVPNServiceInteractive').Status }).Value
    if ($status -ne "Running") {
        Write-Error "Interactive service is not running" -ErrorAction Stop
    }

    # check that automatic service is installed
    $name = (Invoke-Command -Session $sess -ScriptBlock { (Get-Service -name 'OpenVPNService') }).Name
    if ($name -ne "OpenVPNService") {
        Write-Error "OpenVPNService is not installed" -ErrorAction Stop
    }

    Invoke-Command -Session $sess -ArgumentList $OPENVPN_EXE -ScriptBlock  {
        Start-Process -FilePath $args[0] -ArgumentList "--version" -NoNewWindow -Wait -RedirectStandardOutput output.txt ; Get-Content output.txt
    }
}

function Start-TestMachine() {
    # Start AWS instance
    Write-Host "Starting instance"

    $tags = @(
        @{
            Key="Name"
            Value=$InstanceName
        }
        @{
            Key="Created-By"
            Value="Powershell/OpenVPN/openvpn-windows-test"
        }
        @{
            Key="Owner"
            Value="Core team"
        }
        @{
            Key="Maintainer"
            Value="Lev Stipakov"
        }
        @{
            Key="Task Group"
            Value="Community"
        }
        @{
            Key="Environment"
            Value="Test"
        }
    )
    $tagSpec = New-Object Amazon.EC2.Model.TagSpecification
    $tagSpec.ResourceType = "instance"

    foreach($tag in $tags) {
        $tagSpec.Tags.Add($tag)
    }

    $instId = (New-EC2Instance `
        -ImageId $IMAGE_ID `
        -InstanceType $INSTANCE_TYPE `
        -SubnetId $SUBNET_ID `
        -TagSpecification $tagSpec `
        -SecurityGroupId $SECURITY_GROUPS).Instances[0].InstanceId

    Write-Host "Instance $instId started"

    while ($true) {
        $status = (Get-EC2InstanceStatus -InstanceId $instId).Status.Status
        Write-Host "Checking status... " $status
        if ($status -eq "ok") {
            break
        }
        Start-Sleep 5
    }

    $ip = (Get-EC2Instance -InstanceId $instId).Instances[0].PublicIpAddress
    Write-Host "IP: $ip"

    return $instId, $ip
}

function Install-MSI($IP, $Sess) {
    Write-Host "Copy MSI"
    scp -i $SSH_KEY "$MSI_PATH" administrator@${IP}:

    Write-Host "Install MSI"
    $msiFileName = Split-Path "$MSI_PATH" -leaf
    Invoke-Command -Session $Sess -ArgumentList $msiFileName -ScriptBlock {
        Start-Process msiexec.exe -Wait -ArgumentList @("/I", "$HOME\$args", "/quiet", "/L*V", "install.log")
    }
}

function Remove-Instance([string]$InstId) {
    if ($InstId -ne "") {
        Write-Host "Remove instance $InstId"
        Remove-EC2Instance -InstanceId $InstId -Force
    }
}

function Get-Logs($IP, $Sess) {
    Invoke-Command -Session $sess -ScriptBlock {
        Copy-Item -Path "$ENV:UserProfile\OpenVPN\log\*.log" -Destination "." -Recurse
        Compress-Archive -Path "*.log" -DestinationPath "$HOME\openvpn-logs.zip"
    }

    scp -i $SSH_KEY administrator@${IP}:openvpn-logs.zip .
}

$exitcode = 0
try {
    Set-DefaultAWSRegion -Region $REGION

    $instId, $ip = Start-TestMachine

    # this is to prevent "The authenticity of host can't be established" prompt
    ssh-keyscan -H $IP | Out-File ~\.ssh\known_hosts -Append
    $sess = New-PSSession -HostName $IP -UserName administrator -KeyFilePath $SSH_KEY

    Install-MSI -IP $ip -Sess $sess
    Test-Install -IP $ip -Sess $sess
    $exitcode = Invoke-Command -Session $sess -FilePath Start-LocalTest.ps1 -ArgumentList @($Driver, 1, "C:/TA/ca.crt", "C:/TA/t_client.crt", "C:/TA/t_client.key", $Tests, 1)
}
catch {
    Write-Host $_
    $exitcode = 1
}
finally {
    if ($sess) {
        Get-Logs -IP $ip -Sess $sess
    }
    if ($instId) {
        Remove-Instance -InstId $instId
    }
}

exit $exitcode
