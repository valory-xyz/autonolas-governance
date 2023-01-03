# installing node
FROM node:16.7.0 as builder

RUN apt update -y && apt install jq -y

# copy the current directory files to /usr/app
COPY . /usr/app

# working directory
WORKDIR /usr/app

# install dependencies and compile hardhat
RUN yarn install
RUN npx hardhat compile

# ENTRYPOINT ["bash", "entrypoint.sh"]
