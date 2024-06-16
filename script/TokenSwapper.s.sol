// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TokenSwapper} from "../src/TokenSwapper.sol";

contract TokenSwapperScript is Script {
    TokenSwapper internal swapper;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address inputToken = vm.envAddress("INPUT_TOKEN_ADDRESS");
        address outputToken = vm.envAddress("OUTPUT_TOKEN_ADDRESS");
        address inputPriceFeed = vm.envAddress("INPUT_FEED_ADDRESS");
        address outputPriceFeed = vm.envAddress("OUTPUT_FEED_ADDRESS");
        address swapRouter = vm.envAddress("SWAP_ROUTER_ADDRESS");
        address feeRecipient = vm.envOr("FEE_RECEIVER_ADDRESS", deployer);
        address tokenRecipient = vm.envOr("TOKEN_RECEIVER_ADDRESS", deployer);
        uint256 withdrawalDelay = vm.envOr("WITHDRAWAL_DELAY", uint256(0));

        uint16 swapFeePct = 0;
        uint16 depositFeePct = 0;
        uint16 minExpectedSwapPct = 0;

        {
            uint256 _swapFeePct = vm.envOr("SWAP_FEE_PCT", uint256(0));
            uint256 _depositFeePct = vm.envOr("DEPOSIT_FEE_PCT", uint256(0));
            uint256 _minExpectedSwapPct = vm.envOr("MIN_EXPECTED_SWAP_PCT", uint256(0));
            if (_swapFeePct > 0) swapFeePct = uint16(_swapFeePct);
            if (_depositFeePct > 0) depositFeePct = uint16(_depositFeePct);
            if (_minExpectedSwapPct > 0) minExpectedSwapPct = uint16(_minExpectedSwapPct);
        }

        vm.startBroadcast(deployerPrivateKey);

        swapper = new TokenSwapper(
            inputToken,
            outputToken,
            inputPriceFeed,
            outputPriceFeed,
            swapRouter,
            feeRecipient,
            tokenRecipient,
            swapFeePct,
            depositFeePct,
            minExpectedSwapPct,
            withdrawalDelay
        );

        console.logString("TokenSwapper deployed at:");
        console.logAddress(address(swapper));
    }
}
