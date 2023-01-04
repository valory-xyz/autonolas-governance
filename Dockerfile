FROM node:18.6.0 as builder

RUN mkdir -p /code
WORKDIR /code
ADD package* /code

ENV NODE_OPTIONS=--openssl-legacy-provider

COPY yarn.lock .
RUN yarn install --ignore-engines

COPY contracts contracts
COPY scripts scripts
COPY lib lib
COPY hardhat.config.js .

RUN npx hardhat compile
RUN npx hardhat deploy 

CMD ["npx", "hardhat", "node", "--hostname", "0.0.0.0"] 
