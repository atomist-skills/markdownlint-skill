FROM node:lts

RUN apt-get update && apt-get install -y \
   jq

RUN npm install -g markdownlint-cli

WORKDIR /app
COPY markdownlint.* /app/

WORKDIR /atm/home
ENTRYPOINT ["bash", "/app/markdownlint.sh"]
