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

ADD https://deb.nodesource.com/setup_10.x .
RUN bash setup_10.x \
        && apt-get install -y nodejs

ADD https://packages.microsoft.com/config/ubuntu/16.04/packages-microsoft-prod.deb .
RUN dpkg -i packages-microsoft-prod.deb
RUN apt-get update \
        && apt-get install -y powershell

RUN git clone https://github.com/shanepeckham/CustomSpeech-Processing-Pipeline.git /usr/src/repos/CustomSpeech-Processing-Pipeline
RUN pip3 install -r /usr/src/repos/CustomSpeech-Processing-Pipeline/Transcriber/requirements.txt
RUN python3 -m spacy download en_core_web_lg

RUN npm --prefix /usr/src/repos/CustomSpeech-Processing-Pipeline/Batcher install

COPY SpeechCLI /usr/bin/SpeechCLI
COPY process-docker.ps1 /usr/src/process-docker.ps1
COPY process-prechunked.ps1 /usr/src/process-prechunked.ps1
COPY start.ps1 /usr/src/start.ps1
COPY helpers.ps1 /usr/src/helpers.ps1

RUN mkdir /usr/src/wrk
WORKDIR /usr/src/wrk

CMD [ "pwsh", "/usr/src/start.ps1" ]
#CMD [ "pwsh" ]