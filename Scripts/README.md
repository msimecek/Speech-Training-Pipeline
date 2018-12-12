# Scripts

Mostly PowerShell scripts which can be useful when working with this pipeline.

## VTT

To convert results coming from speech batch transcription from JSON to subtitle format VTT use the `parse-batch.vtt.ps1` script.

It expects values of two input variables:

* `$sourceFile` - path of the source JSON file.
* `$destFile` - path of output VTT file.