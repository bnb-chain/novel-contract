# novel-contract

Mind marketplace is a marketplace protocol for safely and efficiently buying and selling data uploaded in [Greenfield](https://github.com/bnb-chain/greenfield).

## Install

To install dependencies:

```bash
git clone --recurse-submodules https://github.com/bnb-chain/novel-contract.git && cd novel-contract
yarn install
forge install
```

## Deploy

1. Copy `.env.example` and setup `OP_PRIVATE_KEY` and `OWNER_PRIVATE_KEY` in `.env`.

```bash
cp .env[foundry.toml](foundry.toml).example .env
```

2. Deploy with foundry.

```bash
forge script ./script/1-deploy.s.sol --rpc-url ${RPC_LOCAL} --legacy --broadcast --private-key ${OP_PRIVATE_KEY}
```

## Test

Test with foundry after deploying:

```bash
forge test
```
