// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {TokenSwapper} from "../src/TokenSwapper.sol";
import {MockAggregatorV3} from "../src/mocks/AggregatorV3.sol";

contract TokenSwapperTest is Test {
    TokenSwapper internal swapper;
    ERC20 internal inputToken;
    ERC20 internal outputToken;
    AggregatorV3Interface internal inputFeed;
    AggregatorV3Interface internal outputFeed;
    ISwapRouter internal swapRouter;

    address internal owner;
    address internal feeReceiver;
    address internal tokenReceiver;
    address internal user;

    function setUp() external {
        uint256 ownerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0x01));
        owner = vm.addr(ownerPrivateKey);
        feeReceiver = vm.addr(0x02);
        tokenReceiver = vm.addr(0x03);
        user = vm.addr(0x04);
        vm.startPrank(owner);

        address _inputToken = vm.envOr("INPUT_TOKEN_ADDRESS", address(0));
        address _outputToken = vm.envOr("OUTPUT_TOKEN_ADDRESS", address(0));
        address _inputFeed = vm.envOr("INPUT_FEED_ADDRESS", address(0));
        address _outputFeed = vm.envOr("OUTPUT_FEED_ADDRESS", address(0));
        address _swapRouter = vm.envAddress("SWAP_ROUTER_ADDRESS");

        if (_inputToken != address(0)) {
            inputToken = ERC20(_inputToken);
            deal(address(inputToken), owner, 100 * 10 ** inputToken.decimals());
        } else {
            inputToken = new InputToken();
        }

        if (_outputToken != address(0)) outputToken = ERC20(_outputToken);
        else outputToken = new OutputToken();

        if (_inputFeed != address(0)) {
            inputFeed = AggregatorV3Interface(_inputFeed);
        } else {
            MockAggregatorV3 inputFeed_ = new MockAggregatorV3(8, "IPT/USD", 1);
            inputFeed_.setRoundData(0, 1234567890, block.timestamp, block.timestamp, 1);
            inputFeed = AggregatorV3Interface(inputFeed_);
        }

        if (_outputFeed != address(0)) {
            outputFeed = AggregatorV3Interface(_outputFeed);
        } else {
            MockAggregatorV3 outputFeed_ = new MockAggregatorV3(8, "OPT/USD", 1);
            outputFeed_.setRoundData(0, 152470933, block.timestamp, block.timestamp, 1);
            outputFeed = AggregatorV3Interface(outputFeed_);
        }

        swapRouter = ISwapRouter(_swapRouter);
        swapper = new TokenSwapper(
            address(inputToken),
            address(outputToken),
            address(inputFeed),
            address(outputFeed),
            address(swapRouter),
            feeReceiver,
            tokenReceiver,
            0,
            0,
            9500,
            60 * 60 * 24
        );
    }

    function test_ConversionRate() external view {
        (int256 rate, uint8 decimals) = swapper.conversionRate();

        (, int256 inputRate,,,) = inputFeed.latestRoundData();
        (, int256 outputRate,,,) = outputFeed.latestRoundData();

        assertEq(rate, inputRate * int256(10 ** decimals) / outputRate);
        assertEq(decimals, 8);
    }

    function test_Swap() external {
        uint256 amount = 100 * 10 ** inputToken.decimals();
        inputToken.transfer(address(swapper), amount);
        swapper.swap(amount);

        uint256 expectedAmountOut = _calculateSwapAmountOut(amount);
        uint256 minAmountOut = expectedAmountOut * swapper.minExpectedSwapPct() / 10000;

        assertGe(outputToken.balanceOf(address(swapper)), minAmountOut);
    }

    function test_Swap_Fee() external {
        swapper.setSwapFeePct(5000);

        uint256 amount = 100 * 10 ** inputToken.decimals();
        inputToken.transfer(address(swapper), amount);

        uint256 amountOut = swapper.swap(amount);
        uint256 expectedAmountOut = _calculateSwapAmountOut(amount);
        uint256 minAmountOut = expectedAmountOut * swapper.minExpectedSwapPct() / 10000;

        uint256 swapperBalance = outputToken.balanceOf(address(swapper));
        assertEq(inputToken.balanceOf(address(swapper)), 0);
        assertEq(outputToken.balanceOf(address(swapper)), amountOut);
        assertTrue(
            swapperBalance == amountOut && swapperBalance >= minAmountOut / 2 && swapperBalance < expectedAmountOut / 2
        );
        assertEq(outputToken.balanceOf(feeReceiver), amountOut);
    }

    function test_Swap_AutomaticWithdrawal() external {
        swapper.setWithdrawalDelay(0);

        uint256 amount = 100 * 10 ** inputToken.decimals();
        inputToken.transfer(address(swapper), amount);
        uint256 amountOut = swapper.swap(amount);

        assertEq(inputToken.balanceOf(address(swapper)), 0);
        assertEq(outputToken.balanceOf(address(swapper)), 0);
        assertEq(outputToken.balanceOf(tokenReceiver), amountOut);
    }

    function testRevert_Swap_NotOwner() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        swapper.swap(1);
    }

    function testRevert_Swap_InsufficientBalance() external {
        vm.expectRevert(abi.encodePacked("insufficient balance"));
        swapper.swap(1);
    }

    function testRevert_Swap_InsufficientAmountOut() external {
        uint256 amount = 100 * 10 ** inputToken.decimals();
        inputToken.transfer(address(swapper), amount);

        swapper.setMinExpectedSwapPct(10000);
        vm.expectRevert(abi.encodePacked("Too little received"));
        swapper.swap(amount);
    }

    function testRevert_Swap_Paused() external {
        swapper.pause();
        inputToken.transfer(address(swapper), 100);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        swapper.swap(100);
    }

    function test_Deposit() external {
        uint256 amount = 100 * 10 ** inputToken.decimals();
        deal(address(inputToken), user, amount);

        vm.startPrank(user);
        inputToken.approve(address(swapper), amount);
        swapper.deposit(amount);

        assertEq(inputToken.balanceOf(user), 0);
        assertEq(inputToken.balanceOf(address(swapper)), 0);

        uint256 expectedAmountOut = _calculateSwapAmountOut(amount);
        uint256 minAmountOut = expectedAmountOut * swapper.minExpectedSwapPct() / 10000;
        assertGe(outputToken.balanceOf(address(swapper)), minAmountOut);
    }

    function test_Deposit_Fee() external {
        swapper.setDepositFeePct(5000);

        uint256 amount = 100 * 10 ** inputToken.decimals();
        deal(address(inputToken), user, amount);

        vm.startPrank(user);
        inputToken.approve(address(swapper), amount);
        swapper.deposit(amount);

        uint256 expectedAmountOut = _calculateSwapAmountOut(amount);
        uint256 minAmountOut = expectedAmountOut * swapper.minExpectedSwapPct() / 10000;

        assertEq(inputToken.balanceOf(user), 0);
        assertEq(inputToken.balanceOf(feeReceiver), amount / 2);
        assertGe(outputToken.balanceOf(address(swapper)), minAmountOut / 2);
        assertLt(outputToken.balanceOf(address(swapper)), expectedAmountOut / 2);
    }

    function test_Deposit_FailSwap() external {
        uint256 amount = 100 * 10 ** inputToken.decimals();
        deal(address(inputToken), user, amount);
        swapper.setMinExpectedSwapPct(10000);

        vm.startPrank(user);
        inputToken.approve(address(swapper), amount);
        swapper.deposit(amount);

        assertEq(inputToken.balanceOf(user), 0);
        assertEq(inputToken.balanceOf(address(swapper)), amount);
        assertEq(outputToken.balanceOf(address(swapper)), 0);
    }

    function test_Deposit_SwapAndWithdraw() external {
        swapper.setWithdrawalDelay(0);

        uint256 amount = 100 * 10 ** inputToken.decimals();
        deal(address(inputToken), user, amount);

        vm.startPrank(user);
        inputToken.approve(address(swapper), amount);
        swapper.deposit(amount);

        uint256 expectedAmountOut = _calculateSwapAmountOut(amount);
        uint256 minAmountOut = expectedAmountOut * swapper.minExpectedSwapPct() / 10000;

        assertEq(inputToken.balanceOf(user), 0);
        assertEq(inputToken.balanceOf(address(swapper)), 0);
        assertEq(outputToken.balanceOf(address(swapper)), 0);
        assertGe(outputToken.balanceOf(tokenReceiver), minAmountOut);
    }

    function testRevert_Deposit_InsufficientBalance() external {
        vm.expectRevert(abi.encodePacked("STF"));
        swapper.deposit(1);
    }

    function test_Withdraw() external {
        uint256 amountIn = 100 * 10 ** inputToken.decimals();
        inputToken.transfer(address(swapper), amountIn);
        uint256 amountOut = swapper.swap(amountIn);

        swapper.withdraw(amountOut);

        assertEq(inputToken.balanceOf(address(swapper)), 0);
        assertEq(outputToken.balanceOf(address(swapper)), 0);
        assertEq(outputToken.balanceOf(tokenReceiver), amountOut);
    }

    function testRevert_Withdraw_NotOwner() external {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        swapper.withdraw(1);
    }

    function testRevert_Withdraw_InsufficientBalance() external {
        inputToken.transfer(address(swapper), 100);
        swapper.swap(100);

        vm.expectRevert(abi.encodePacked("insufficient balance"));
        swapper.withdraw(1);
    }

    function testRevert_Withdraw_InsufficientDelay() external {
        uint256 amount = 100 * 10 ** inputToken.decimals();
        inputToken.transfer(address(swapper), amount);
        swapper.swap(amount);

        swapper.withdraw(1);

        vm.expectRevert(abi.encodePacked("insufficient delay"));
        swapper.withdraw(1);

        vm.warp(block.timestamp + 60 * 60 * 24);
        swapper.withdraw(1);

        swapper.setWithdrawalDelay(0);
        swapper.withdraw(1);
    }

    function test_Execute() external {
        inputToken.transfer(address(swapper), 100);

        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", user, 100);
        swapper.execute(address(inputToken), 0, data);

        assertEq(inputToken.balanceOf(address(swapper)), 0);
        assertEq(inputToken.balanceOf(user), 100);
    }

    function testRevert_Execute_NotOwner() external {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)");

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        swapper.execute(address(inputToken), 0, data);
    }

    /// ---- INTERNAL FUNCTIONS ---- ///

    function _calculateSwapAmountOut(uint256 amountIn) internal view returns (uint256 amountOut) {
        (int256 rate, uint8 rateDecimals) = swapper.conversionRate();
        assert(rate >= 0);
        amountOut =
            amountIn * uint256(rate) * 10 ** outputToken.decimals() / 10 ** (rateDecimals + inputToken.decimals());
    }
}

contract InputToken is ERC20 {
    constructor() ERC20("InputToken", "IPT") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }
}

contract OutputToken is ERC20 {
    constructor() ERC20("OutputToken", "OPT") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }
}
