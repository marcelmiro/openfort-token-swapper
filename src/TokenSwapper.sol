// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

contract TokenSwapper is Pausable, Ownable {
    ERC20 public inputToken;
    ERC20 public outputToken;
    AggregatorV3Interface public inputPriceFeed;
    AggregatorV3Interface public outputPriceFeed;
    ISwapRouter public swapRouter;

    address public feeRecipient;
    address public tokenRecipient;

    uint16 public swapFeePct; // Percentage: 0 - 10,000
    uint16 public depositFeePct; // Percentage: 0 - 10,000
    uint16 public minExpectedSwapPct; // Percentage: 0 - 10,000

    uint256 public lastWithdrawal;
    uint256 public withdrawalDelay;

    event Deposit(uint256 indexed amount, address indexed benefactor);
    event Swap(uint256 indexed amountIn, uint256 indexed amountOut, address indexed caller);
    event Withdraw(uint256 indexed amount, address indexed receiver);

    constructor(
        address _inputToken,
        address _outputToken,
        address _inputPriceFeed,
        address _outputPriceFeed,
        address _swapRouter,
        address _feeRecipient,
        address _tokenRecipient,
        uint16 _swapFeePct,
        uint16 _depositFeePct,
        uint16 _minExpectedSwapPct,
        uint256 _withdrawalDelay
    ) Ownable(msg.sender) {
        require(_inputToken != _outputToken, "input and output tokens are the same");
        require(_inputPriceFeed != _outputPriceFeed, "input and output price feeds are the same");

        _setInputToken(_inputToken);
        _setOutputToken(_outputToken);
        _setInputPriceFeed(_inputPriceFeed);
        _setOutputPriceFeed(_outputPriceFeed);
        _setSwapRouter(_swapRouter);

        _setFeeRecipient(_feeRecipient);
        _setTokenRecipient(_tokenRecipient);

        _setSwapFeePct(_swapFeePct);
        _setDepositFeePct(_depositFeePct);
        _setMinExpectedSwapPct(_minExpectedSwapPct);
        _setWithdrawalDelay(_withdrawalDelay);
    }

    /**
     * @dev Returns the rate of conversion between the input and output token -
     * i.e. input token / output token
     */
    function conversionRate() public view returns (int256 rate, uint8 decimals) {
        decimals = inputPriceFeed.decimals();
        uint8 outputDecimals = outputPriceFeed.decimals();

        (, int256 inputPrice,,,) = inputPriceFeed.latestRoundData();
        (, int256 outputPrice,,,) = outputPriceFeed.latestRoundData();

        rate = inputPrice * int256(10 ** outputDecimals) / outputPrice;
    }

    /**
     * @dev Pause token swapping functionality
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause token swapping functionality
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev Swap input tokens from this contract to output tokens. This function
     * can only be called by the contract owner or the same contract (useful
     * when calling from other functions in try/catch blocks). Swapped tokens
     * may be automatically withdrawn into `tokenReceiver` if `withdrawalDelay`
     * is set to 0 (i.e. IMMEDIATE).
     * @param amountIn The amount of input tokens to swap
     * @return amountOut The amount of output tokens received by the DEX
     */
    function swap(uint256 amountIn) external whenNotPaused returns (uint256 amountOut) {
        if (msg.sender != address(this)) {
            _checkOwner();
        }
        amountOut = _swap(amountIn);
        if (withdrawalDelay == 0) {
            try this.withdraw(amountOut) {} catch {}
        }
    }

    /**
     * @dev Withdraw output tokens from this contract. This function can only be
     * called by the contract owner or the same contract (useful when calling
     * from other functions in try/catch blocks). This function can only be
     * called after `withdrawalDelay` has passed.
     * @param amount The amount of output tokens to withdraw
     */
    function withdraw(uint256 amount) external {
        if (msg.sender != address(this)) {
            _checkOwner();
        }
        _withdraw(amount);
    }

    /**
     * @dev Deposit input tokens into this contract. A percentage of input
     * tokens may be transferred to `feeRecipient` if `depositFeePct` is set.
     * This function may also swap and withdraw the input tokens automatically
     * based on try/catch blocks. I.e., `deposit` will try to swap the input
     * tokens and will try to withdraw them before failing. The deposit function
     * will not fail if any of these other calls revert.
     * @param amount The amount of input tokens to deposit
     */
    function deposit(uint256 amount) external {
        TransferHelper.safeTransferFrom(address(inputToken), msg.sender, address(this), amount);

        uint256 feeAmount = amount * depositFeePct / 10000;
        if (feeAmount > 0) {
            TransferHelper.safeTransfer(address(inputToken), feeRecipient, feeAmount);
        }

        emit Deposit(amount - feeAmount, msg.sender);
        try this.swap(amount - feeAmount) {} catch {}
    }

    /// ---- ADMIN FUNCTIONS ---- ///

    /**
     * @dev Execute arbitrary transactions on the target contract. This function
     * can only be called by the contract owner.
     * @param target The target contract
     * @param value The value to send with the transaction
     * @param data The data to send with the transaction
     */
    function execute(address target, uint256 value, bytes memory data) external onlyOwner {
        (bool success,) = target.call{value: value}(data);
        require(success, "execution failed");
    }

    function setInputToken(address _inputToken) external onlyOwner {
        _setInputToken(_inputToken);
    }

    function setOutputToken(address _outputToken) external onlyOwner {
        _setOutputToken(_outputToken);
    }

    function setInputPriceFeed(address _inputPriceFeed) external onlyOwner {
        _setInputPriceFeed(_inputPriceFeed);
    }

    function setOutputPriceFeed(address _outputPriceFeed) external onlyOwner {
        _setOutputPriceFeed(_outputPriceFeed);
    }

    function setSwapRouter(address _swapRouter) external onlyOwner {
        _setSwapRouter(_swapRouter);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        _setFeeRecipient(_feeRecipient);
    }

    function setTokenRecipient(address _tokenRecipient) external onlyOwner {
        _setTokenRecipient(_tokenRecipient);
    }

    function setSwapFeePct(uint16 _swapFeePct) external onlyOwner {
        _setSwapFeePct(_swapFeePct);
    }

    function setDepositFeePct(uint16 _depositFeePct) external onlyOwner {
        _setDepositFeePct(_depositFeePct);
    }

    function setMinExpectedSwapPct(uint16 _minExpectedSwapPct) external onlyOwner {
        _setMinExpectedSwapPct(_minExpectedSwapPct);
    }

    function setWithdrawalDelay(uint256 _withdrawalDelay) external onlyOwner {
        _setWithdrawalDelay(_withdrawalDelay);
    }

    /// ---- INTERNAL FUNCTIONS ---- ///

    /**
     * @dev Internal swapping function that will swap input tokens for output
     * tokens. This function will get the conversion rate from the oracle and
     * force the DEX to swap a minimum amount of tokens based on the oracle
     * conversion and a slippage percentage (minExpectedSwapPct). A fee amount
     * may also be subtracted from returned amount.
     * @param amountIn The amount of input tokens to swap
     * @return amountOut The amount of output tokens received (excluding fees)
     */
    function _swap(uint256 amountIn) internal returns (uint256 amountOut) {
        require(inputToken.balanceOf(address(this)) >= amountIn, "insufficient balance");
        TransferHelper.safeApprove(address(inputToken), address(swapRouter), amountIn);

        (int256 rate, uint8 rateDecimals) = conversionRate();
        assert(rate >= 0);

        uint256 expectedAmountOut =
            amountIn * uint256(rate) * 10 ** outputToken.decimals() / 10 ** (rateDecimals + inputToken.decimals());

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(inputToken),
            tokenOut: address(outputToken),
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: expectedAmountOut * minExpectedSwapPct / 10000,
            sqrtPriceLimitX96: 0
        });

        uint256 totalAmountOut = swapRouter.exactInputSingle(swapParams);

        uint256 feeAmount = totalAmountOut * swapFeePct / 10000;
        if (feeAmount > 0) {
            TransferHelper.safeTransfer(address(outputToken), feeRecipient, feeAmount);
        }

        amountOut = totalAmountOut - feeAmount;
        emit Swap(amountIn, amountOut, msg.sender);
    }

    function _withdraw(uint256 amount) internal {
        require(block.timestamp - lastWithdrawal >= withdrawalDelay, "insufficient delay");
        require(outputToken.balanceOf(address(this)) >= amount, "insufficient balance");
        TransferHelper.safeTransfer(address(outputToken), tokenRecipient, amount);
        lastWithdrawal = block.timestamp;
        emit Withdraw(amount, tokenRecipient);
    }

    function _setInputToken(address _inputToken) internal {
        require(_inputToken != address(0), "token is zero address");
        inputToken = ERC20(_inputToken);
    }

    function _setOutputToken(address _outputToken) internal {
        require(_outputToken != address(0), "token is zero address");
        outputToken = ERC20(_outputToken);
    }

    function _setInputPriceFeed(address _inputPriceFeed) internal {
        require(_inputPriceFeed != address(0), "feed is zero address");
        inputPriceFeed = AggregatorV3Interface(_inputPriceFeed);
    }

    function _setOutputPriceFeed(address _outputPriceFeed) internal {
        require(_outputPriceFeed != address(0), "feed is zero address");
        outputPriceFeed = AggregatorV3Interface(_outputPriceFeed);
    }

    function _setSwapRouter(address _swapRouter) internal {
        require(_swapRouter != address(0), "router is zero address");
        swapRouter = ISwapRouter(_swapRouter);
    }

    function _setFeeRecipient(address _feeRecipient) internal {
        require(_feeRecipient != address(0), "recipient is zero address");
        feeRecipient = _feeRecipient;
    }

    function _setTokenRecipient(address _tokenRecipient) internal {
        require(_tokenRecipient != address(0), "recipient is zero address");
        tokenRecipient = _tokenRecipient;
    }

    function _setSwapFeePct(uint16 _swapFeePct) internal {
        require(_swapFeePct <= 10000, "percentage over 10000");
        swapFeePct = _swapFeePct;
    }

    function _setDepositFeePct(uint16 _depositFeePct) internal {
        require(_depositFeePct <= 10000, "percentage over 10000");
        depositFeePct = _depositFeePct;
    }

    function _setMinExpectedSwapPct(uint16 _minExpectedSwapPct) internal {
        require(_minExpectedSwapPct <= 10000, "percentage over 10000");
        minExpectedSwapPct = _minExpectedSwapPct;
    }

    function _setWithdrawalDelay(uint256 _withdrawalDelay) internal {
        withdrawalDelay = _withdrawalDelay;
    }
}
