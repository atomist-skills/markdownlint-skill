FROM node:lts@sha256:8eb45f4677c813ad08cef8522254640aa6a1800e75a9c213a0a651f6f3564189

RUN apt-get update && apt-get install -y \
   jq \
   && rm -rf /var/lib/apt/lists/*

RUN npm install -g markdownlint-cli

WORKDIR /app
COPY markdownlint.* /app/

WORKDIR /atm/home
ENTRYPOINT ["bash", "/app/markdownlint.sh"]
