FROM node:lts@sha256:9025a77b2f37fcda3bbd367587367a9f2251d16a756ed544550b8a571e16a653

RUN apt-get update && apt-get install -y \
    jq=1.5+dfsg-1.3 \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g markdownlint-cli

WORKDIR /app
COPY markdownlint.* /app/

WORKDIR /atm/home
ENTRYPOINT ["bash", "/app/markdownlint.sh"]
