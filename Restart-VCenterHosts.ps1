<#
.SYNOPSIS
 Restart vCenter Hosts in order
.DESCRIPTION
 Get hosts attached to vCenter server, place in Maintenance Mode, Restart.
.PARAMETER Server
 A vCenter server name
.PARAMETER Credential
 A credential object with permissions to vCenter Host poweroperation
.PARAMETER WhatIf
 Switch to turn testing mode on or off.
.EXAMPLE
.\Restart-VCenterHosts.ps1 -Server vcenterServer.my.com -Credential $vcenterCredObj
.EXAMPLE
.\Restart-VCenterHosts.ps1 -Server vcenterServer.my.com -Credential $vcenterCredObj -WhatIf
.INPUTS
 [string] vCenter Server name
 [PSCredential] vCenter Credentials
.OUTPUTS
 Log messages are output to the console.
.NOTES
 Special thanks:
 Warning:
 Disabling DRS will delete any resource pool on the cluster without warning!!!
 http://www.van-lieshout.com/2010/05/powercli-disableenable-ha-and-drs/
 Special thanks to Arnim van Lieshout.
 and LucD at VMware for:
 https://communities.vmware.com/t5/VMware-PowerCLI-Discussions/PowerCLI-Enable-Disable-Alarm-Actions-on-Hosts-Clusters/td-p/2124257
Disable Host Alarms
TheSleepyAdmin
 https://communities.vmware.com/t5/VMware-PowerCLI-Discussions/Enable-and-Disable-Alarm-Actions-on-a-Single-VM/td-p/2851127
 LucD (mod)
 https://communities.vmware.com/t5/VMware-PowerCLI-Discussions/PowerCLI-Enable-Disable-Alarm-Actions-on-Hosts-Clusters/td-p/2124257
 Break labels
Manoj Sahoo
https://ridicurious.com/2020/01/23/deep-dive-break-continue-return-exit-in-powershell/
#>

[cmdletbinding()]
param (
 # Target VIServer
 [Parameter(Mandatory = $True)]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string[]]$VIServer,
 # VIServer Credentials with Proper Permission Levels
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$VICredential,
 # Cluster Name(s) to Target
 # [Parameter(Mandatory = $False)]
 # [string[]]$TargetClusters,
 # Cluster Name(s) to Skip
 [Parameter(Mandatory = $False)]
 [string[]]$SkipClusters,
 # Host Name(s) to Skip
 [Parameter(Mandatory = $False)]
 [string[]]$SkipHosts,
 # If over x days then reboot host
 [int]$MaxDaysOn = 30,
 [Alias('wi')]
 [switch]$WhatIf
)
# ===============================================================
function Complete-Pipeline {
 process {
  $_ | Show-ClusterInfo
  Write-Host ('{0}' -f $MyInvocation.MyCommand.name) -Fore Green
 }
}
function Connect-TargetVIServers {
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_) -Fore Green
  Connect-VIServer -Server $_ -Credential $Credential | Out-Null
 }
}
function Disable-ClusterHA {
 process {
  Write-Host ('{0},{1},HA Orginal Status: {2}' -f $MyInvocation.MyCommand.name, $_.Name, $_.HAEnabled) -Fore DarkYellow
  $_ | Set-Cluster -HAEnabled:$false -Confirm:$false -WhatIf:$WhatIf | Out-Null
  $_
 }
}
function Enable-ClusterDRS {
 process {
  Write-Host ('{0},{1},DRS Original Status: {2}' -f $MyInvocation.MyCommand.name, $_.Name, $_.DrsEnabled) -Fore DarkYellow
  $_ | Set-Cluster -DrsEnabled:$True -DrsAutomationLevel FullyAutomated -Confirm:$false -WhatIf:$WhatIf | Out-Null
  $_
 }
}
function Get-VCenterCluster {
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.name) -Fore Green
  Get-Cluster -Server $_.name
 }
}
function Restart-VMHosts {
 begin {
  function Wait-VMHostState ($thisHost, $state) {
   Write-Verbose ('{0},{1},{2},Timeout in {3}' -f $MyInvocation.MyCommand.name, $thisHost, $state, $global:timeout)
   # Write-Host ('{0},{1},{2},Timeout in {3}' -f $MyInvocation.MyCommand.name, $thisHost, $state, $global:timeout) -Fore Red
   if ((Get-VMHost -Name $thisHost).ConnectionState -ne $state) {
    if ($global:timeout -gt 0) {
     if (-not$WhatIf) {
      $global:timeout -= 10
      Start-Sleep 10
      Wait-VMHostState $thisHost $state
     }
    }
    else {
     Write-Error  ('{0},{1},{2},Timeout limit reached. Somethign is wrong' -f $MyInvocation.MyCommand.name, $thisHost.name, $state)
     $Error[-1]
     Break parentVmHostLoop;
    }
   }
  }
 }
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.name) -Fore Green
  $vmHosts = $_ | Get-VMHost
  :parentVmHostLoop foreach ($vmHost in $vmHosts) {
   $upDays = (New-TimeSpan -Start $vmhost.ExtensionData.Summary.Runtime.BootTime -End (Get-Date)).Days
   if ($upDays -gt $MaxDaysOn) {
    Write-Host ('{0},{1},Restarting Host' -f $MyInvocation.MyCommand.name, $vmHost.name) -Fore Blue
    # Place MaintenanceMode
    Disable-HostAlarms $_ $vmHost
    $vmHost | Set-VMHost -State Maintenance -Evacuate:$true -RunAsync -Confirm:$false -WhatIf:$WhatIf | Out-Null
    $global:timeout = 1200
    Wait-VMHostState $vmHost.name Maintenance
    $vmHost | Restart-VMhost -Confirm:$false -RunAsync -WhatIf:$WhatIf | Out-Null
    if (-not$WhatIf) {
     Write-Host ('{0},{1},{2},300 second delay...' -f $MyInvocation.MyCommand.name, $_.name, $vmHost.name) -Fore Green
     Start-Sleep 300
    }
    Wait-VMHostState $vmHost.name Maintenance
    $vmHost | Set-VMHost -State Connected -Confirm:$false -RunAsync -WhatIf:$WhatIf | Out-Null
    Wait-VMHostState $vmHost.name Connected
    Enable-HostAlarms $_ $vmHost
   }
  }
  foreach ($vmHost in $vmHosts) {
   # Force Renabled Host Alarms in case parentVmHostLoop is exited due to an error
   Enable-HostAlarms $_ $vmHost
  }
  $_
 }
}
function Restore-ClusterDRS {
 process {
  Write-Host ('{0},{1},Enabled: [{2}]' -f $MyInvocation.MyCommand.name, $_.name, $_.DrsEnabled) -Fore Green
  $_ | Set-Cluster -DrsEnabled:$_.DrsEnabled -DrsAutomationLevel $_.DrsAutomationLevel -Confirm:$false -WhatIf:$WhatIf | Out-Null
  $_
 }
}
function Restore-ClusterHA {
 process {
  Write-Host ('{0},{1},Enabled: [{2}]' -f $MyInvocation.MyCommand.name, $_.name, $_.HAEnabled) -Fore Green
  $_ | Set-Cluster -HAEnabled:$_.HAEnabled -Confirm:$false -WhatIf:$WhatIf | Out-Null
  $_
 }
}
function Import-VMwareModules {
 Write-Host ('{0}' -f $MyInvocation.MyCommand.Name)
 if (Get-Module -ListAvailable -name VMware.VimAutomation.Core) {
  Write-Host ('{0},Module Found. Importing...' -f $MyInvocation.MyCommand.Name)
  # $cmdlets = 'Connect-VIServer','Disconnect-VIServer','Get-Cluster','Set-Cluster','Get-VMHost','Set-VMHost ','Restart-VMhost'
  # Import-Module -Name VMware.VimAutomation.Core -Cmdlet $cmdlets | Out-Null
  Import-Module -Name VMware.VimAutomation.Core | Out-Null
 }
 else {
  Write-Host ('{0},Module Not found. Exiting..' -f $MyInvocation.MyCommand.Name)
  # [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  # $installParams = @{
  #  Name               = 'VMware.PowerCLI'
  #  SkipPublisherCheck = $true
  #  Scope              = 'CurrentUser'
  #  Force              = $true
  #  Confirm            = $false
  # }
  # Install-Module @installParams
  # Import-Module -Name VMware.VimAutomation.Core | Out-Null
  EXIT
 }
 if ( !(Get-Module -ListAvailable -name VMware.VimAutomation.Core)) {
  Write-Error "VMware.VimAutomation.Core not available. EXITING"
  EXIT
 }
 # Get-PowerCLIVersion
 Write-Host ('{0},Setting PowerCli behavior...' -f $MyInvocation.MyCommand.Name)
 $powercliParams = @{
  InvalidCertificateAction = 'Ignore'
  ParticipateInCeip        = $false
  Scope                    = 'User'
  Confirm                  = $false
 }
 Set-PowerCLIConfiguration @powercliParams | Out-Null
}
function Show-ClusterInfo {
 process {
  $output = $_.name, $_.DrsEnabled, $_.DrsAutomationLevel, $_.HAEnabled
  Write-Host ('Cluster: [{0}],DRS: [{1}],Level: [{2}],HA: [{3}]' -f $output) -Fore DarkCyan
 }
}
filter Skip-Cluster {
 if ($SkipClusters -notcontains $_.name) {
  $_ | Show-ClusterInfo
  $_
 }
 else { Write-Host ('{0},[{1}]' -f $MyInvocation.MyCommand.name, $_.name) -Fore DarkYellow }
}
function Get-RuleState {
 begin {
  function Write-RuleState {
   process {
    $msgVars = $MyInvocation.MyCommand.Name, $_.Cluster, $_.Name, $_.Enabled
    Write-Host ('{0},[{1}],[{2}],[{3}]' -f $msgVars) -Fore Blue
   }
  }
 }
 process {
  Write-Host ('{0},[{1}]' -f $MyInvocation.MyCommand.name, $_.name) -Fore Blue
  $drsRules = $_ | Get-DrsRule
  $hostRules = $_ | Get-DrsVMHostRule
  $drsRules | Write-RuleState
  $hostRules | Write-RuleState
  $_
 }
}
function Suspend-Rules {
 begin {
  $global:savedDrsRules = @()
  $global:savedHostRules = @()
 }
 process {
  Write-Host ('{0},[{1}]' -f $MyInvocation.MyCommand.name, $_.name) -Fore Yellow
  $params = @{
   Enabled     = $False
   Confirm     = $False
   WhatIf      = $WhatIf
   ErrorAction = 'SilentlyContinue'
  }
  $drsRules = $_ | Get-DrsRule | Where-Object { $_.enabled -eq $True }
  foreach ($rule in $drsRules) {
   Write-Host ('{0},[{1}],[{2}]' -f $MyInvocation.MyCommand.name, $_.Name, $rule.Name) -Fore Yellow
   $rule | Set-DrsRule @params | Out-Null
   $global:savedDrsRules += [PSCustomObject]@{'cluster' = $_.name; 'rule' = $rule.Name }
  }
  $hostRules = $_ | Get-DrsVMHostRule | Where-Object { $_.enabled -eq $True }
  foreach ($rule in $hostRules) {
   Write-Host ('{0},[{1}],[{2}]' -f $MyInvocation.MyCommand.name, $_.Name, $rule.Name) -Fore Yellow
   $rule | Set-DrsVMHostRule @params | Out-Null
   $global:savedHostRules += [PSCustomObject]@{'cluster' = $_.name; 'rule' = $rule.Name }
  }
  $_
 }
}
function Resume-Rules {
 process {
  Write-Host ('{0},[{1}]' -f $MyInvocation.MyCommand.name, $_.name) -Fore Green
  $params = @{
   Enabled     = $True
   Confirm     = $False
   ErrorAction = 'SilentlyContinue'
   WhatIf      = $WhatIf
  }
  foreach ($rule in $global:savedDrsRules) {
   Write-Host ('{0},[{1}],[{2}]' -f $MyInvocation.MyCommand.name, $rule.cluster, $rule.rule) -Fore Green
   $_ | Get-DrsRule -name $rule.rule | Set-DrsRule @params | Out-Null
  }
  foreach ($rule in $global:savedHostRules) {
   Write-Host ('{0},[{1}],[{2}]' -f $MyInvocation.MyCommand.name, $rule.cluster, $rule.rule) -Fore Green
   $_ | Get-DrsVMHostRule -name $rule.rule | Set-DrsVMHostRule @params | Out-Null
  }
  $_
 }
 end {
  Remove-Variable -Name savedDrsRules -Scope Global
  Remove-Variable -Name savedHostRules -Scope Global
 }
}
function Disable-HostAlarms ($cluster, $vmHost) {
 process {
  Write-Host ('{0},[{1}],[{2}]' -f $MyInvocation.MyCommand.name, $cluster, $vmHost) -Fore Yellow
  $alarmMgr = Get-View AlarmManager
  if (-not$WhatIf) {
   $vCenter = $cluster.Uid.Split('@:')[1]
   ($alarmMgr.where({ $_.Client.ServiceUrl -match $vCenter })).EnableAlarmActions($vmHost.Extensiondata.MoRef, $false)
  }
 }
}
function Enable-HostAlarms ($cluster, $vmHost) {
 process {
  Write-Host ('{0},[{1}],[{2}]' -f $MyInvocation.MyCommand.name, $cluster, $vmHost) -Fore Green
  $alarmMgr = Get-View AlarmManager
  if (-not$WhatIf) {
   $vCenter = $cluster.Uid.Split('@:')[1]
   ($alarmMgr.where({ $_.Client.ServiceUrl -match $vCenter })).EnableAlarmActions($vmHost.Extensiondata.MoRef, $true)
  }
 }
}
filter Skip-RecentlyRebootedHosts {
 Write-Host ('{0},[{1}],[{2}]' -f $MyInvocation.MyCommand.name, $cluster, $vmHost) -Fore Green
 $upDays = (New-TimeSpan -Start $vmhost.ExtensionData.Summary.Runtime.BootTime -End (Get-Date)).Days
 if ($upDays -gt $MaxDaysOn) { $_ }
}
# ===============================================
. .\lib\Clear-SessionData.ps1
# . .\lib\Load-Module.ps1
. .\lib\Set-PSCred.ps1
. .\lib\Show-TestRun.ps1
# ===============================================
Show-TestRun
$env:psmodulepath = "$home\Documents\WindowsPowerShell\Modules;C:\Program Files\WindowsPowerShell\Modules; C:\Windows\system32\config\systemprofile\Documents\WindowsPowerShell\Modules; C:\Program Files (x86)\WindowsPowerShell\Modules; C:\Windows\system32\WindowsPowerShell\v1.0\Modules; C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Modules"
Import-VMwareModules

$VIServer | Connect-TargetVIServers
$clusters = $global:DefaultVIServers | Get-VCenterCluster | Skip-Cluster

$clusters | Enable-ClusterDRS | Get-RuleState | Suspend-Rules | Complete-Pipeline
$clusters | Restart-VMHosts | Complete-Pipeline
$clusters | Resume-Rules | Restore-ClusterDRS | Complete-Pipeline

Disconnect-VIServer * -Confirm:$False
Show-TestRun
# END