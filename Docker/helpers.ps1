$segmentsVarName = "segments"

function Set-SegmentStart {
    param($Name)
    
    if ((Test-Path variable:global:$($segmentsVarName)) -eq $false) {
        Set-Variable -Name $segmentsVarName -Value @() -Scope Global
    }

    $seg = Get-Variable -Name $segmentsVarName -ValueOnly -Scope Global
    if (!($seg.Keys -contains $Name)) {
        $seg += @{ $Name = (Get-Date -UFormat %s) }
        Set-Variable -Name $segmentsVarName -Value $seg -Scope Global
    }
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

    "[Measurement][{0}][{1}] {2}s" -f $env:processName, $Name, ($end - $start)
}

function Get-IdFromCli {
    $idPattern = "(\w{8})-(\w{4})-(\w{4})-(\w{4})-(\w{12})"
    ($input | Select-String $idPattern | % {$_.Matches.Groups[0].Value})
}