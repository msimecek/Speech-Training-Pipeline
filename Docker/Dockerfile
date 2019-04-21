FROM ubuntu:16.04
WORKDIR /usr/src

RUN  apt-get update \ 
        && apt-get install \
        && apt-get -y install \
                curl \
                python3 \
                python3-pip \
                git \
                ffmpeg \
                gnupg gnupg2 \
                libicu55 \
                apt-transport-https

ADD https://packages.microsoft.com/config/ubuntu/16.04/packages-microsoft-prod.deb .
RUN dpkg -i packages-microsoft-prod.deb
RUN apt-get update \
        && apt-get install -y powershell

RUN git clone https://github.com/shanepeckham/CustomSpeech-Processing-Pipeline.git /usr/src/repos/CustomSpeech-Processing-Pipeline
RUN pip3 install -r /usr/src/repos/CustomSpeech-Processing-Pipeline/Transcriber/requirements.txt \
        && pip3 install -r /usr/src/repos/CustomSpeech-Processing-Pipeline/Batcher-Py/requirements.txt \
        && python3 -m spacy download en_core_web_lg

ENV audioFilesPath=/mnt/audio_in
ENV transcriptFilePath=/mnt/audio_in/transcript.txt

COPY SpeechCLI /usr/bin/SpeechCLI
COPY process-docker.ps1 /usr/src/process-docker.ps1
COPY process-prechunked.ps1 /usr/src/process-prechunked.ps1
COPY start.ps1 /usr/src/start.ps1
COPY helpers.ps1 /usr/src/helpers.ps1

RUN mkdir /usr/src/wrk
WORKDIR /usr/src/wrk

ENTRYPOINT [ "pwsh", "/usr/src/start.ps1" ]
#ENTRYPOINT [ "pwsh" ]