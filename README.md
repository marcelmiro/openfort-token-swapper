# On-chain Token Swapper Smart Contract

This project aims to create a Solidity smart contract that facilitates the swapping of tokens from a predefined addresses using a combination of Chainlink price feeds and the Uniswap V3 router.

## How to run this contract's tests

1. Rename `.env.example` to `.env`. You may also modify the predefined values inside but the default ones should work straight away.
2. Deploy a local Ethereum fork using `Anvil`:
   1. First retrieve an Ethereum RPC URL you can use (I have used Alchemy's RPC node for example).
   2. (OPTIONAL) Get the most recent mined block from [Etherscan](https://etherscan.io).
   3. Run the following command: `anvil --fork-url <fork_url> --fork-block-number 20107269 --fork-chain-id 1 --chain-id 1`
3. Open a new terminal and run the contract's tests by executing the command: `forge test --fork-url http://127.0.0.1:8545`

## How to deploy this contract

1. (OPTIONAL) Retrieve an API key from [Etherscan](https://etherscan.io) to verify the smart contract.
2. Go to the `.env` file and modify the deployment contract's constructor arguments. Currently, the `.env` values are based on Ethereum mainnet.
3. Run the following command: `forge script .\script\TokenSwapper.s.sol --rpc-url <rpc_url> --broadcast -vvvv --verify --etherscan-api-key <etherscan_api_key>`
   1. If you do not want to verify the contract you can also run this command: `forge script .\script\TokenSwapper.s.sol --rpc-url <rpc_url> --broadcast -vvvv`
