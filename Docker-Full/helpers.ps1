$segmentsVarName = "segments"

function Set-SegmentStart {
    param($Name)
    
    if ((Test-Path variable:global:$($segmentsVarName)) -eq $false) {
        Set-Variable -Name $segmentsVarName -Value @() -Scope Global
    }

    $seg = Get-Variable -Name $segmentsVarName -ValueOnly -Scope Global
    $seg += @{ $Name = (Get-Date -UFormat %s) }
    Set-Variable -Name $segmentsVarName -Value $seg -Scope Global
}

function Write-SegmentDuration {
    param($Name)

    $seg = Get-Variable -Name $segmentsVarName -ValueOnly -Scope Global

    $end = Get-Date -UFormat %s
    $start = $seg.$Name

    if ($null -eq $start) {
        # segment was not started
        Throw "Segment $Name was not started."
    }

    "[Measurement][{0}] {1}s" -f $Name, ($end - $start)
}