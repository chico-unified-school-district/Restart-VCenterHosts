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
 [System.Management.Automation.PSCredential]$Credential,
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
 [int]$RebootDays = 30,
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
function Disable-ClusterRule {
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.name) -Fore Green
  $_ | Get-DrsRule | Disable-Rule
  $_ | Get-DrsVMHostRule | Disable-Rule
  $_
 }
}
function Restore-ClusterRule {
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.name) -Fore Green
  $baseClusterState = $_
  $rules1 = $_ | Get-DrsRule
  $rules2 = $_ | Get-DrsVMHostRule
  foreach ($rule in ($rules1) ) {
   Restore-Rule $baseClusterState $rule
  }
  foreach ($rule in ($rules2) ) {
   Restore-Rule $baseClusterState $rule
  }
  $_
 }
}
function Set-ClusterRules {
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.name) -Fore Green
  $drsRules1 = $_ | Get-DrsRule
  $drsRules2 = $_ | Get-DrsVMHostRule
  if (($drsRules1.Enabled -contains $true) -or ($drsRules2.Enabled -contains $true)) {
   Write-Host 'Kill'
   $drsRules1 | Disable-Rule
   $drsRules2 | Disable-Rule
  }
  else {
   Write-Host 'Marry'
   $baseClusterState = $_
   foreach ($rule in ($drsRules1, $drsRules2) ) {
    Restore-Rule $baseClusterState $rule
   }
  }
  $_
 }
}

function Disable-Rule {
 process {
  $msgVars = $MyInvocation.MyCommand.name, $_.Cluster, $_.Name
  Write-Host ( '{0},{1},Original Setting,Rule:[{2}],Enabled:[{3}]' -f ($msgVars + $_.Enabled) ) -Fore DarkMagenta
  if ($_.Enabled -eq $True) {
   Write-Host ( '{0},{1},Updating,Rule:[{2}],Enabled:[False]' -f $msgVars ) -Fore Yellow
   $ruleParams = @{
    Enabled = $False
    Confirm = $False
    WhatIf  = $WhatIf
    # ErrorAction = 'SilentlyContinue'
   }
   # switch -Wildcard ( $_.Type ) {
   #  '*Affinity*' { Get-DrsRule -Name $_.name -Cluster $_.Cluster | Set-DrsRule @ruleParams | Out-Null }
   #  'MustRunOn' { Get-DrsVMHostRule -Name $_.name -Cluster $_.Cluster | Set-DrsVMHostRule @ruleParams | Out-Null }
   # }
   if ($_.Type -match 'Affinity') { $_ | Set-DrsRule @ruleParams | Out-Null }
   if ($_.Type -match 'MustRunOn') { $_ | Set-DrsVMHostRule @ruleParams | Out-Null }
  }
 }
}
function Restore-Rule ($cluster, $rule) {
 $baseRuleData = $cluster.ExtensionData.Configuration.Rule.Where({ $_.name -eq $rule.Name })
 Write-Host ( $baseRuleData | Out-String)
 if ($baseRuleData.Enabled -eq $true) {
  $msgVars = $MyInvocation.MyCommand.name, $cluster.name, $rule.name, 'True'
  Write-Host ('{0},{1},[{2}],Enabled: [{3}]' -f $msgVars) -Fore DarkMagenta
  $ruleParams = @{
   Confirm = $False
   WhatIf  = $WhatIf
   # ErrorAction = 'SilentlyContinue'
  }
  # switch -Wildcard ( $rule.Type ) {
  #  '*Affinity*' { $rule | Set-DrsRule @ruleParams -Enabled:$ruleState.Enabled | Out-Null }
  #  'MustRunOn' { $rule | Set-DrsVMHostRule @ruleParams -Enabled:$ruleState.Enabled | Out-Null }
  # }
  if ($rule.Type -match 'Affinity') { $rule | Set-DrsRule @ruleParams | Out-Null }
  if ($rule.Type -match 'MustRunOn') { $rule | Set-DrsVMHostRule @ruleParams | Out-Null }
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
function Get-VCenterClusters {
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
   Write-Host ('{0},{1},Restarting Host' -f $MyInvocation.MyCommand.name, $vmHost.name) -Fore Blue
   # Place MaintenanceMode
   $vmHost | Set-VMHost -State Maintenance -Evacuate:$true -RunAsync -Confirm:$false -WhatIf:$WhatIf | Out-Null
   $global:timeout = 1200
   Wait-VMHostState $vmHost.name Maintenance
   $vmHost | Restart-VMhost -Confirm:$false -RunAsync -WhatIf:$WhatIf | Out-Null
   if (-not$WhatIf) {
    Write-Host ('{0},{1},{2},120 second delay...' -f $MyInvocation.MyCommand.name, $_.name, $vmHost.name) -Fore Green
    Start-Sleep 120
   }
   Wait-VMHostState $vmHost.name Maintenance
   $vmHost | Set-VMHost -State Connected -Confirm:$false -RunAsync -WhatIf:$WhatIf | Out-Null
   Wait-VMHostState $vmHost.name Connected
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
 if (Get-Module -ListAvailable -name VMware.VimAutomation.Core) {
  # $cmdlets = 'Connect-VIServer','Disconnect-VIServer','Get-Cluster','Set-Cluster','Get-VMHost','Set-VMHost ','Restart-VMhost'
  # Import-Module -Name VMware.VimAutomation.Core -Cmdlet $cmdlets | Out-Null
  Import-Module -Name VMware.VimAutomation.Core | Out-Null
 }
 else {
  Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force -Confirm:$false
  Import-Module -Name VMware.VimAutomation.Core -Cmdlet $cmdlets | Out-Null
 }
 if ( !(Get-Module -ListAvailable -name VMware.VimAutomation.Core)) {
  Write-Error "VMware.VimAutomation.Core not available. EXITING"
  EXIT
 }
 # Get-PowerCLIVersion

 Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Scope User -Confirm:$false | Out-Null
}
function Show-ClusterInfo {
 process {
  $output = $_.name, $_.DrsEnabled, $_.DrsAutomationLevel, $_.HAEnabled
  Write-Host ('Cluster:{0},DRS:{1},Level:{2},HA:{3}' -f $output) -Fore DarkCyan
 }
}
filter Skip-Cluster {
 if ($SkipClusters -notcontains $_.name) {
  $_ | Show-ClusterInfo
  $_
 }
 else { Write-Host ('{0},[{1}]' -f $MyInvocation.MyCommand.name, $_.name) -Fore DarkYellow }
}
# ===============================================
. .\lib\Clear-SessionData.ps1
# . .\lib\Load-Module.ps1
. .\lib\Set-PSCred.ps1
. .\lib\Show-TestRun.ps1
# ===============================================
$env:psmodulepath = 'C:\Program Files\WindowsPowerShell\Modules; C:\Windows\system32\config\systemprofile\Documents\WindowsPowerShell\Modules; C:\Program Files (x86)\WindowsPowerShell\Modules; C:\Windows\system32\WindowsPowerShell\v1.0\Modules; C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Modules'
Show-TestRun

$VIServer | Connect-TargetVIServers
$clusters = $global:DefaultVIServers | Get-VCenterClusters | Skip-Cluster

# $clusters | Enable-ClusterDRS | Set-ClusterRules | Complete-Pipeline
$clusters | Disable-ClusterRule
$clusters | Restore-ClusterRule
# $clusters | Get-VMState | Complete-Pipeline
# $clusters | Restart-VMHosts | Complete-Pipeline
# $clusters | Set-ClusterRules | Restore-ClusterDRS | Complete-Pipeline
# $clusters | Restore-VMState | Complete-Pipeline

Disconnect-VIServer * -Confirm:$False
Show-TestRun
# END