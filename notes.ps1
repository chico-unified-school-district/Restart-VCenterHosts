$params = @{
 VIServer     = 'dr-vcenter-test.chico.usd'
 Cred         = $vsphereTest
 SkipClusters = 'Other Cluster'
 SkipHosts    = $null
 RebootDays   = 30
 # WhatIf       = $true
}

$params = @{
 VIServer     = 'do-vdi-vsa-01.chico.usd'
 Cred         = $vSphere
 SkipClusters = 'DR'
 SkipHosts    = $null
 RebootDays   = 30
 # WhatIf       = $true
}

# https://jeffbrown.tech/powershell-hash-table-pscustomobject/
# $obj = @[PSCustomObject] {
#  'Server' = $null
#  'Hosts' = [array]$null
# }

# $myCustomObject | Add-Member `
#     -Name "Owner" `
#     -Value "Jeff Brown" `
#     -MemberType NoteProperty