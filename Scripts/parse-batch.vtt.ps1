# JSON file with transcription output
$sourceFile = "<file>.json"
# Output VTT file
$destFile = "<file>.vtt"

$json = Get-Content $sourceFile | Out-String | ConvertFrom-Json

$output = @()
$output += "WEBVTT`n"

foreach ($i in $json.AudioFileResults[0].SegmentResults) {
    if ($i.RecognitionStatus -eq "Success") {
        $best = $i.NBest[0]
        $startTime = ("{0:hh\:mm\:ss\.fff}" -f ([TimeSpan] $i.Offset))
        $endTime = ("{0:hh\:mm\:ss\.fff}" -f [TimeSpan] [int64]($i.Offset + $i.Duration))

        $output += "$startTime --> $endTime"
        
        if ($best.Confidence -ge 0.5) {
            $output += "$($best.Display)"
        }
        else {
            $output += ""
        }
        
        $output += ""
    }
}

$output | Out-File $destFile