FROM node:lts@sha256:976c9107158a1c85ab0702aec5b1d56bbb85de493ca50794e545a0271421e028

RUN apt-get update && apt-get install -y \
    jq=1.5+dfsg-1.3 \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g markdownlint-cli

WORKDIR /app
COPY markdownlint.* /app/

WORKDIR /atm/home
ENTRYPOINT ["bash", "/app/markdownlint.sh"]
