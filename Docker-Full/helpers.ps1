function Set-SegmentStart {
    param($VarName)
    
    if ($null -eq $VarName) { $VarName = "t1" }

    Set-Variable -Name $VarName -Value (Get-Date -UFormat %s) -Scope Global #TODO: move to single array instead of series of variables
}

function Write-SegmentDuration {
    param($VarName, $TextTemplate)

    if ($null -eq $VarName) { $VarName = "t1" }

    $end = Get-Date -UFormat %s
    $start = Get-Variable -Name $VarName -ValueOnly -Scope Global

    $TextTemplate -f ($end - $start)
}