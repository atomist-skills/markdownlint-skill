FROM node:lts@sha256:cd98882c1093f758d09cf6821dc8f96b241073b38e8ed294ca1f9e484743858f

RUN apt-get update && apt-get install -y \
    jq=1.5+dfsg-1.3 \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g markdownlint-cli

WORKDIR /app
COPY markdownlint.* /app/

WORKDIR /atm/home
ENTRYPOINT ["bash", "/app/markdownlint.sh"]
