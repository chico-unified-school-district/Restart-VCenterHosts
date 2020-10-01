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
 Warning:
 Disabling DRS will delete any resource pool on the cluster without warning!!!
 http://www.van-lieshout.com/2010/05/powercli-disableenable-ha-and-drs/
 Special thanks to Arnim van Lieshout.

 This script requires more than one host in each cluster to function properly
#>

[cmdletbinding()]
param (
 # Target VIServer
 [Parameter(Mandatory = $True)]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$Server,
 # VIServer Credentials with Proper Permission Levels
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$Credential,
 # Cluster Name to Skip
 [Parameter(Mandatory = $False)]
 [array]$SkipClusternames,
 # Host Name to Skip
 [Parameter(Mandatory = $False)]
 [array]$SkipHostNames,
 [Alias('wi')]
 [switch]$WhatIf
)
# $env:psmodulepath += 'C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Modules'
Clear-Host
$env:psmodulepath = 'C:\Program Files\WindowsPowerShell\Modules; C:\Windows\system32\config\systemprofile\Documents\WindowsPowerShell\Modules; C:\Program Files (x86)\WindowsPowerShell\Modules; C:\Windows\system32\WindowsPowerShell\v1.0\Modules; C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Modules'
# Import Functions
. .\lib\Add-Log.ps1

# Main Process
if (Get-Module -ListAvailable -name VMware.VimAutomation.Core) {
 $cmdlets = 'Connect-VIServer','Disconnect-VIServer','Get-Cluster','Set-Cluster','Get-VMHost','Set-VMHost ','Restart-VMhost'
 Import-Module -Name VMware.VimAutomation.Core -Cmdlet $cmdlets | Out-Null
}
else {
 Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force -Confirm:$false
 Import-Module -Name VMware.VimAutomation.Core -Cmdlet $cmdlets | Out-Null
}
if ( !(Get-Module -ListAvailable -name VMware.VimAutomation.Core)) {
 Add-Log error "VMware.VimAutomation.Core not available. EXITING"
 EXIT
}

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Scope User -Confirm:$false | Out-Null
if ($global:defaultviserver) { Disconnect-VIServer -Server * -Confirm:$false }
Connect-VIServer -Server $Server -Credential $Credential | Out-Null

$allClusters = Get-Cluster
foreach ($cluster in $allClusters) { # Begin Processing Clusters
 if ($SkipClusternames -contains $cluster.name) {
  Add-Log skipcluster ('{0} Cluster skipped')
  continue
 }
 else {
  $targetName = $server+'\'+$cluster.name
  # ============ Temporarily disable HA and Set DRS to Automatic ================
  try { $cluster | Set-Cluster -HAEnabled:$false -Confirm:$false -ErrorVariable clusterHAError -WhatIf:$WhatIf }
  catch {
   Add-Log error ('{0},HA disable error. Skipping hosts reboot on Cluster {0}' -f $targetName)
   $clusterHAError
   continue
  }
  Add-Log cluster ('{0},Disable HA successfull' -f $targetName)

  # Get DrsAutomationLevel, set to Automatic if needed
  $DrsAutomationLevel = $cluster.DrsAutomationLevel
  if ($DrsAutomationLevel -ne 'FullyAutomated'){
   try { $cluster | Set-Cluster -DrsAutomationLevel FullyAutomated -Confirm:$false -ErrorVariable clusterDRSError -WhatIf:$WhatIf }
   catch {
    Add-Log error ('{0},DRS update error. Skipping hosts reboot on Cluster {0}' -f $targetName)
    $clusterDRSError
    continue
   }
   Add-Log cluster ('{0},set DRS to FullyAutomated successfull' -f $targetName)
  }

  $allClusterHosts = $cluster | Get-VMHost

  if ($allClusterHosts.count -lt 1) {
   Add-Log error ('{0}, Only one host present. Exiting Script' -f $targetName )
  }

  foreach ($esxiHost in $allClusterHosts) {
   if ($SkipHostNames -contains $esxiHost.name) {
    Add-Log skiphost ('{0} esxiHost skipped')
   }
   else {
    # Reboot VMHosts
    $vmHostName = $esxiHost.name
    Write-Debug "Reboot $vmHostName ?"
    if ( (Get-VMHost $vmHostName).ConnectionState -eq 'Maintenance') {
     Add-Log Maintenance ('{0}, host already in MaintenanceMode' -f $vmHostName) $logPath $WhatIf
    } else {
     Add-Log Maintenance ('{0}, Changing host state to MaintenanceMode' -f $vmHostName) $logPath $WhatIf
     Set-VMHost $vmHostName -State Maintenance -Evacuate:$true -Confirm:$false -WhatIf:$WhatIf | Out-Null
     # test for MaintenanceMode
     $i = 1800 # 30 minutes max wait time for host evacuation
     do { Start-Sleep 1; Write-Progress -Act "$vmHostName,Wait For Maintenance Mode" -SecondsRemaining $i ;$i-- }
     until ( ((Get-VMHost $vmHostName).ConnectionState -eq 'Maintenance') -or ( $i -eq 0 ) -or $WhatIf )
    }

    if (!$WhatIf) { Start-Sleep 5 } # Wait for host to settle down

    Add-Log restart ('{0}, restarting ESXi Host' -f $vmHostName) $logPath $WhatIf
    Restart-VMhost -VMHost $vmHostName -Confirm:$false -Force -WhatIf:$WhatIf | Out-Null
    if (!$WhatIf) { Start-Sleep 120 } # Wait for host to settle down
    # wait for host to restart and reconnect
    $i = 600 # 10 minute max wait time for host reboot
    do { Write-Progress -Act "$vmHostName,Wait For Host Reconnect" -SecondsRemaining $i; Start-Sleep 1; $i-- }
    until ( ((Get-VMHost -Name $vmHostName).ConnectionState -eq 'Maintenance') -or ($i -eq 0) -or $WhatIf)

    if (!$WhatIf) { Start-Sleep 10 } # Wait for host to settle down

    Set-VMHost $vmHostName -State Connected -Confirm:$false -WhatIf:$WhatIf | Out-Null
    # $bootTime = (Get-VMHost -Name $vmHostName | Get-View).runtime.boottime
    Add-Log connected $vmHostName
    }
  }

  # Restore HA and DRS settings

  if (!$WhatIf) { for ($i=180;$i -ge 0;$i--){write-progress -Act 'Wait For Storage' -SecondsRemaining $i;start-sleep 1} }
  try {
   Add-log drs ('{0},Attempting to set DRS to {1}' -f $targetName,$DrsAutomationLevel)
   $cluster |
    Set-Cluster -HAEnabled:$true -DrsAutomationLevel $DrsAutomationLevel `
     -Confirm:$false -ErrorVariable resetClusterError -WhatIf:$WhatIf | Out-Null
  }
  catch {
   Add-Log error ('{0},DRS or HA restore error. Please check cluster settngs in vCenter server.' -f $targetName)
   $resetClusterError
   continue
  }
  Add-Log cluster ('{0},HA and DRS settings restored' -f $targetName)
 }
} # End Processing Clusters
# Clean up
Disconnect-VIServer -Server * -Confirm:$false