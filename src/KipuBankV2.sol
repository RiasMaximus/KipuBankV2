// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract KipuBankV2 is AccessControl, ReentrancyGuard {
    type Token is address;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");

    address public constant NATIVE_TOKEN = address(0);
    uint8 public constant INTERNAL_DECIMALS = 6;

    error ZeroAmount();
    error UnsupportedToken(address token);
    error BankCapExceeded(uint256 currentTotalUsd, uint256 newTotalUsd, uint256 capUsd);
    error TransferFailed();
    error InvalidAddress();
    error NotEnoughBalance(address token, address user, uint256 requested, uint256 available);

    event TokenConfigured(address indexed token, bool supported, uint8 decimals);
    event Deposit(address indexed user, address indexed token, uint256 amount, uint256 usdValue);
    event Withdrawal(address indexed user, address indexed token, uint256 amount, uint256 usdValue);
    event BankCapUpdated(uint256 oldCapUsd, uint256 newCapUsd);
    event Paused(address indexed by);
    event Unpaused(address indexed by);

    AggregatorV3Interface public immutable ethUsdPriceFeed;
    uint256 public bankCapUsd;
    uint256 public totalEthUsdDeposited;
    bool public paused;

    struct TokenConfig {
        bool supported;
        uint8 decimals;
    }

    mapping(address => TokenConfig) public tokenConfigs;
    mapping(address => mapping(address => uint256)) private balances;
    mapping(address => uint256) private userUsdBalance;

    constructor(address admin, address priceFeed, uint256 initialBankCapUsd) {
        if (admin == address(0) || priceFeed == address(0)) revert InvalidAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(RISK_MANAGER_ROLE, admin);

        ethUsdPriceFeed = AggregatorV3Interface(priceFeed);
        bankCapUsd = initialBankCapUsd;
    }

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    function balanceOf(address token, address user) external view returns (uint256) {
        return balances[token][user];
    }

    function internalUsdBalanceOf(address user) external view returns (uint256) {
        return userUsdBalance[user];
    }

    function getLatestEthUsdPrice() public view returns (uint256 price, uint8 decimals_) {
        (, int256 answer, , , ) = ethUsdPriceFeed.latestRoundData();
        require(answer > 0, "Invalid price");
        price = uint256(answer);
        decimals_ = ethUsdPriceFeed.decimals();
    }

    function configureToken(address token, bool supported) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert InvalidAddress();
        uint8 decimals_ = IERC20Metadata(token).decimals();
        tokenConfigs[token] = TokenConfig(supported, decimals_);
        emit TokenConfigured(token, supported, decimals_);
    }

    function updateBankCap(uint256 newCapUsd) external onlyRole(RISK_MANAGER_ROLE) {
        uint256 old = bankCapUsd;
        bankCapUsd = newCapUsd;
        emit BankCapUpdated(old, newCapUsd);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function depositNative() external payable whenNotPaused nonReentrant {
        if (msg.value == 0) revert ZeroAmount();
        uint256 usdValue = _ethToUsd(msg.value);

        uint256 newTotal = totalEthUsdDeposited + usdValue;
        if (newTotal > bankCapUsd) revert BankCapExceeded(totalEthUsdDeposited, newTotal, bankCapUsd);

        totalEthUsdDeposited = newTotal;
        balances[NATIVE_TOKEN][msg.sender] += msg.value;
        userUsdBalance[msg.sender] += usdValue;

        emit Deposit(msg.sender, NATIVE_TOKEN, msg.value, usdValue);
    }

    function depositToken(address token, uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        TokenConfig memory cfg = tokenConfigs[token];
        if (!cfg.supported) revert UnsupportedToken(token);

        balances[token][msg.sender] += amount;
        uint256 usdValue = _scaleToInternal(amount, cfg.decimals);
        userUsdBalance[msg.sender] += usdValue;

        bool ok = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!ok) revert TransferFailed();

        emit Deposit(msg.sender, token, amount, usdValue);
    }

    function withdrawNative(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();

        uint256 bal = balances[NATIVE_TOKEN][msg.sender];
        if (amount > bal) revert NotEnoughBalance(NATIVE_TOKEN, msg.sender, amount, bal);

        uint256 usdValue = _ethToUsd(amount);

        balances[NATIVE_TOKEN][msg.sender] = bal - amount;
        if (userUsdBalance[msg.sender] >= usdValue) userUsdBalance[msg.sender] -= usdValue;
        if (totalEthUsdDeposited >= usdValue) totalEthUsdDeposited -= usdValue;

        (bool sent, ) = msg.sender.call{value: amount}("");
        if (!sent) revert TransferFailed();

        emit Withdrawal(msg.sender, NATIVE_TOKEN, amount, usdValue);
    }

    function withdrawToken(address token, uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        TokenConfig memory cfg = tokenConfigs[token];
        if (!cfg.supported) revert UnsupportedToken(token);

        uint256 bal = balances[token][msg.sender];
        if (amount > bal) revert NotEnoughBalance(token, msg.sender, amount, bal);

        uint256 usdValue = _scaleToInternal(amount, cfg.decimals);
        balances[token][msg.sender] = bal - amount;
        if (userUsdBalance[msg.sender] >= usdValue) userUsdBalance[msg.sender] -= usdValue;

        bool ok = IERC20(token).transfer(msg.sender, amount);
        if (!ok) revert TransferFailed();

        emit Withdrawal(msg.sender, token, amount, usdValue);
    }

    function _scaleToInternal(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == INTERNAL_DECIMALS) return amount;
        if (decimals > INTERNAL_DECIMALS) return amount / (10 ** (decimals - INTERNAL_DECIMALS));
        return amount * (10 ** (INTERNAL_DECIMALS - decimals));
    }

    function _ethToUsd(uint256 ethAmount) internal view returns (uint256) {
        (uint256 price, uint8 priceDecimals) = getLatestEthUsdPrice();
        uint256 rawValue = (ethAmount * price) / 1e18;
        return _scaleToInternal(rawValue, priceDecimals);
    }
}

