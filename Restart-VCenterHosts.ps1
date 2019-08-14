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
#>

[cmdletbinding()]
param (
 [Parameter(Mandatory = $True)]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$Server,
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$Credential,
 [switch]$WhatIf
)

Clear-Host

# Import Modules
# Import Functions
. .\lib\Add-Log.ps1

# Main Process
if (Get-Module -ListAvailable -name VMware.VimAutomation.Core) {
 Import-Module -Name VMware.VimAutomation.Core
}
else { 
 Install-Module -Name VMware.PowerCLI -Scope CurrentUser
 Import-Module -Name VMware.VimAutomation.Core
}
if ( !(Get-Module -ListAvailable -name VMware.VimAutomation.Core)) {
 Add-Log error "VMware.VimAutomation.Core not available. EXITING"
 EXIT 
}

if ($global:defaultviserver) { Disconnect-VIServer -Server * -Confirm:$false }
Connect-VIServer -Server $Server -Credential $Credential
# Get a list of all hosts
$esxiHosts = Get-VMHost

# Shutdown VMHosts
foreach ($esxiHost in $esxiHosts) {
 $name = $esxiHost.name
 Set-VMHost -VMHost $name -State Maintenance -Evacuate:$true -Confirm:$false -WhatIf:$WhatIf
 Add-Log restart ('{0}, restarting ESXi Host' -f $name) $logPath $WhatIf
 Restart-VMhost -VMHost $name -Confirm:$false -Force -WhatIf:$WhatIf
 # wait for host to restart and reconnect
 do { if (!$WhatIf) { Start-Sleep 60 } }
 until ( ((Get-VMHost -Name $name).ConnectionState -eq 'Connected'))
 Set-VMHost -VMHost $name -State Connected -Confirm:$false -WhatIf:$WhatIf
 $bootTime = (Get-VMHost -Name $name | Get-View).runtime.boottime
 Add-Log bootime ('{0},{1}' -f $name, $bootTime )
}

Disconnect-VIServer -Server * -Confirm:$false