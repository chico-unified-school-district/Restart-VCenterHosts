if (!(Test-Path .\$ENV:JOB_NAME)) { git clone https://github.com/chico-unified-school-district/$ENV:JOB_NAME.git }
cd .\$ENV:JOB_NAME
'git pull'
git pull
'git last log entry'
git log -1
# Set this to true or false
$test = $false
$scriptParams = @{
 VIServers    = 'DO-VCENTER.chico.usd', 'dr-cusd-vsa.chico.usd', 'DO-VDI-VSA-01.CHICO.USD'
 Credential   = .\lib\Set-PSCred.ps1 $ENV:VCENTER_USER $ENV:VCENTER_PW
 VIServer     = 'do-vdi-vsa-01.chico.usd'
 Cred         = $vsphere
 SkipClusters = 'DO2', 'Pivot3 Cluster'
 SkipHosts    = $null
 RebootDays   = 30
 Verbose      = $test
 WhatIf       = $test
}

.\Restart-VCenterHosts.PS1 @scriptParams