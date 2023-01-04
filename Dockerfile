# installing node
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

# check with alex
RUN npx hardhat deploy 

# can you save this please we need to rebuild
# once the export is completed we can try to run it
# we might need to use the buildx thing to try to run it as well
CMD ["npx", "hardhat", "node", "--hostname", "0.0.0.0"] 

# run with
# `docker run -p 8545:8545 -it valory/autonolas-governance:dev`

# build with
# `docker buildx build --platform linux/amd64 -t valory/autonolas-governance:dev . --load`
