if (!(Test-Path .\$ENV:JOB_NAME)) { git clone https://github.com/chico-unified-school-district/$ENV:JOB_NAME.git }
cd .\$ENV:JOB_NAME
'git pull'
git pull
'git last log entry'
git log -2
# Set this to true or false
$test = $true
# vcenter servers: 'DO-VCENTER.chico.usd', , 'DO-VDI-VSA-01.CHICO.USD'
$scriptParams = @{
 VIServers    = 'dr-cusd-vsa.chico.usd'
 Credential   = .\lib\Set-PSCred.ps1 $ENV:VCENTER_USER $ENV:VCENTER_PW
 VIServer     = 'dr-cusd-vsa.chico.usd'
 Cred         = $vsphere
 SkipClusters = 'Pivot3 Cluster'
 SkipHosts    = $null
 MaxDaysOn    = 30
 Verbose      = $test
 WhatIf       = $test
}

.\Restart-VCenterHosts.PS1 @scriptParams