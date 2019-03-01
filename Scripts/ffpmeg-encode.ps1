$inputFile = ""
$outputFile = ""

ffmpeg -i $inputFile -acodec pcm_s16le -vn -ar 16000 -ac 1 $outputFile