FROM node:16.7.0 as builder

RUN apt update -y && apt install jq -y

RUN mkdir -p /code
WORKDIR /code
ADD package* /code

COPY yarn.lock .
RUN yarn install --ignore-engines 

COPY contracts contracts
COPY scripts scripts
COPY lib lib
COPY hardhat.config.js .

RUN npm run compile
RUN npx hardhat deploy

CMD [ "npx", "hardhat", "node", "--hostname", "0.0.0.0" ]

