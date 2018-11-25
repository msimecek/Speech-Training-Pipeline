FROM ubuntu:16.04
WORKDIR /usr/src
COPY SpeechCLI /usr/bin/SpeechCLI
COPY process-docker.ps1 /usr/src/process-docker.ps1
COPY start.ps1 .

RUN apt-get update
RUN apt-get install

RUN apt-get --assume-yes install \
         curl \
         python3 \
         python3-pip \
         git \
         ffmpeg

RUN apt-get --assume-yes install \
        gnupg gnupg2 \
        libicu55 \
        apt-transport-https


ADD https://deb.nodesource.com/setup_10.x .
RUN bash setup_10.x
RUN apt-get install -y nodejs

ADD https://packages.microsoft.com/config/ubuntu/16.04/packages-microsoft-prod.deb .
RUN dpkg -i packages-microsoft-prod.deb
RUN apt-get update \
        && apt-get install -y powershell

CMD [ "pwsh", "start.ps1" ]
#CMD [ "pwsh" ]