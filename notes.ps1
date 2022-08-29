$params = @{
 VIServer     = 'dr-vcenter-test.chico.usd'
 Cred         = $vsphereTest
 SkipClusters = 'Other Cluster'
 SkipHosts    = $null
 MaxDaysOn    = 30
 # WhatIf       = $true
}

$params = @{
 VIServer  = 'do-vdi-vsa-01.chico.usd'
 Cred      = $vSphere
 # SkipClusters = 'DR'
 SkipHosts = $null
 MaxDaysOn = 2
 # WhatIf       = $true
}

$params = @{
 VIServer     = 'do-vcenter.chico.usd'
 Cred         = $vSphere
 SkipClusters = 'Pivot3 Cluster'
 SkipHosts    = $null
 MaxDaysOn    = 30
}

$params = @{
 VIServer     = 'dr-cusd-vsa.chico.usd'
 Cred         = $vSphere
 SkipClusters = 'Pivot3 Cluster'
 SkipHosts    = $null
 MaxDaysOn    = 30
}

ls -Filter *.ps1 -Recurse | Unblock-File
$params

# https://jeffbrown.tech/powershell-hash-table-pscustomobject/
# $obj = @[PSCustomObject] {
#  'Server' = $null
#  'Hosts' = [array]$null
# }

# $myCustomObject | Add-Member `
#     -Name "Owner" `
#     -Value "Jeff Brown" `
#     -MemberType NoteProperty


# NSX Edge
# agoM3t*L#wvcTsVl

5 / 25 / 2022 6:47:45 AM :: Processing DR-Site VMs ESXi-Nested (10.200.95.10) (T3) Error: REST API error: 'S3 error: Access Denied
Code: AccessDenied', error code: 403
Other: HostId: '1n/N3lvH8iMus8swrgyutn7brklLV/FL1mF0mS9jAWF7DkukKyskLCc9BtdUUqU1CjDrB25gXABG'
Exception from server: REST API error: 'S3 error: Access Denied
Code: AccessDenied', error code: 403
Other: HostId: '1n/N3lvH8iMus8swrgyutn7brklLV/FL1mF0mS9jAWF7DkukKyskLCc9BtdUUqU1CjDrB25gXABG'
