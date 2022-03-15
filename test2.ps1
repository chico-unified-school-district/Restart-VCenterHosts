[cmdletbinding()]
param(
 [string[]]$stuff
 # ,$Cred
)
# 'before blurgs!'
# sleep 60
# 'after zergs!'

function test1 {
 begin {
  $global:things = @()
 }
 process {
  $myObj = [PSCustomObject]@{'name' = $_ ; 'hate' = $_ }
  $global:things += $myObj
 }
}

$stuff | test1

$global:things

Remove-Variable -Name things -Scope Global