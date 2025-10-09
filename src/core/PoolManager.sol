// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IPoolManager.sol";
import "./PoolManagerStorage.sol";

contract PoolManager is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, PoolManagerStorage {
    using SafeERC20 for IERC20;

    modifier onlyReLayer() {
        require(
            msg.sender == address(relayerAddress),
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        _;
    }

    modifier onlyWithdrawManager() {
        require(
            msg.sender == address(withdrawManager),
            "TreasureManager:onlyWithdrawManager only withdraw manager can call this function"
        );
        _;
    }

    constructor()  {
        _disableInitializers();
    }

    receive() external payable {
        depositEthToBridge();
    }

    function initialize(address initialOwner, address _messageManager, address _relayerAddress, address _withdrawManager) public initializer  {
        __ReentrancyGuard_init();

        periodTime = 21 days;
        MinTransferAmount = 0.1 ether;
        PerFee = 10000;
        stakingMessageNumber = 1;

        __Ownable_init(initialOwner);

        messageManager = IMessageManager(_messageManager);
        relayerAddress = _relayerAddress;
        withdrawManager = _withdrawManager;
    }

    function depositEthToBridge() public payable whenNotPaused nonReentrant returns (bool) {
        FundingPoolBalance[ETHAddress] += msg.value;
        emit DepositToken(
            ETHAddress,
            msg.sender,
            msg.value
        );
        return true;
    }

    function depositErc20ToBridge(address tokenAddress, uint256 amount) public whenNotPaused nonReentrant returns (bool) {
        if (!IsSupportToken[tokenAddress]) {
            revert TokenIsNotSupported(tokenAddress);
        }
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        FundingPoolBalance[tokenAddress] += amount;
        emit DepositToken(
            tokenAddress,
            msg.sender,
            amount
        );
        return true;
    }

    function withdrawEthFromBridge(address payable withdrawAddress, uint256 amount) public payable whenNotPaused onlyWithdrawManager returns (bool) {
        require(address(this).balance >= amount, "PoolManager withdrawEthFromBridge: insufficient ETH balance in contract");
        FundingPoolBalance[ETHAddress] -= amount;
        (bool success, ) = withdrawAddress.call{value: amount}("");
        if (!success) {
            return false;
        }
        emit WithdrawToken(
            ETHAddress,
            msg.sender,
            withdrawAddress,
            amount
        );
        return true;
    }

    function withdrawErc20FromBridge(address tokenAddress, address withdrawAddress, uint256 amount) public whenNotPaused onlyWithdrawManager returns (bool) {
        require(
            FundingPoolBalance[tokenAddress] >= amount,
            "PoolManager withdrawEthFromBridge: Insufficient token balance in contract"
        );
        FundingPoolBalance[tokenAddress] -= amount;
        IERC20(tokenAddress).safeTransfer(withdrawAddress, amount);
        emit WithdrawToken(
            tokenAddress,
            msg.sender,
            withdrawAddress,
            amount
        );
        return true;
    }

    function BridgeInitiateETH(uint256 sourceChainId, uint256 destChainId, address destTokenAddress, address to) external whenNotPaused nonReentrant payable returns (bool) {
        if (sourceChainId != block.chainid) {
            revert sourceChainIdError();
        }

        if (!IsSupportChainId(destChainId)) {
            revert ChainIdIsNotSupported(destChainId);
        }

        if (msg.value < MinTransferAmount) {
            revert LessThanMinTransferAmount(MinTransferAmount, msg.value);
        }

        FundingPoolBalance[ETHAddress] += msg.value;

        uint256 fee = (msg.value * PerFee) / 1_000_000;
        uint256 amount = msg.value - fee;

        FeePoolValue[ETHAddress] += fee;

        messageManager.sendMessage(block.chainid, destChainId, ETHAddress, destTokenAddress, msg.sender, to, amount, fee);

        emit InitiateETH(sourceChainId, destChainId, destTokenAddress, msg.sender, to, amount);

        return true;
    }

    function BridgeInitiateERC20(uint256 sourceChainId, uint256 destChainId, address to, address sourceTokenAddress, address destTokenAddress, uint256 value) external whenNotPaused nonReentrant returns (bool) {
        if (sourceChainId != block.chainid) {
            revert sourceChainIdError();
        }

        if (!IsSupportChainId(destChainId)) {
            revert ChainIdIsNotSupported(destChainId);
        }

        if (!IsSupportToken[sourceTokenAddress]) {
            revert TokenIsNotSupported(sourceTokenAddress);
        }

        uint256 BalanceBefore = IERC20(sourceTokenAddress).balanceOf(address(this));
        IERC20(sourceTokenAddress).safeTransferFrom(msg.sender, address(this), value);
        uint256 BalanceAfter = IERC20(sourceTokenAddress).balanceOf(address(this));

        uint256 amount = BalanceAfter - BalanceBefore;
        FundingPoolBalance[sourceTokenAddress] += value;
        uint256 fee = (amount * PerFee) / 1_000_000;

        amount -= fee;
        FeePoolValue[sourceTokenAddress] += fee;

        messageManager.sendMessage(sourceChainId, destChainId, sourceTokenAddress, destTokenAddress, msg.sender, to, amount, fee);

        emit InitiateERC20(sourceChainId, destChainId, sourceTokenAddress, destTokenAddress, msg.sender, to, amount);

        return true;
    }

    function BridgeFinalizeETH(uint256 sourceChainId, uint256 destChainId, address sourceTokenAddress, address from, address to, uint256 amount, uint256 _fee, uint256 _nonce) external payable whenNotPaused onlyReLayer returns (bool) {
        if (destChainId != block.chainid) {
            revert sourceChainIdError();
        }

        if (!IsSupportChainId(sourceChainId)) {
            revert ChainIdIsNotSupported(sourceChainId);
        }

        (bool _ret, ) = payable(to).call{value: amount}("");
        if (!_ret) {
            revert TransferETHFailed();
        }

        FundingPoolBalance[ETHAddress] -= amount;

        messageManager.claimMessage(sourceChainId, destChainId, sourceTokenAddress, ETHAddress, from, to, amount, _fee, _nonce);

        emit FinalizeETH(sourceChainId, destChainId, sourceTokenAddress, address(this), to, amount);

        return true;
    }

    function BridgeFinalizeERC20(uint256 sourceChainId, uint256 destChainId, address from, address to,address sourceTokenAddress, address destTokenAddress, uint256 amount, uint256 _fee, uint256 _nonce) external whenNotPaused onlyReLayer returns (bool) {
        if (destChainId != block.chainid) {
            revert sourceChainIdError();
        }

        if (!IsSupportChainId(sourceChainId)) {
            revert ChainIdIsNotSupported(sourceChainId);
        }

        if (!IsSupportToken[destTokenAddress]) {
            revert TokenIsNotSupported(destTokenAddress);
        }

        require(IERC20(destTokenAddress).balanceOf(
            address(this)) >= amount,
            "PoolManager: insufficient token balance for transfer"
        );

        IERC20(destTokenAddress).safeTransfer(to, amount);

        FundingPoolBalance[destTokenAddress] -= amount;

        messageManager.claimMessage(sourceChainId, destChainId, sourceTokenAddress, destTokenAddress, from, to, amount, _fee, _nonce);

        emit FinalizeERC20(sourceChainId, destChainId, sourceTokenAddress, destTokenAddress, address(this), to, amount);

        return true;
    }

    function fetchFundingPoolBalance(address token) external view returns(uint256) {
        return FundingPoolBalance[token];
    }

    function setMinTransferAmount(uint256 _MinTransferAmount) external onlyReLayer {
        MinTransferAmount = _MinTransferAmount;
        emit SetMinTransferAmount(_MinTransferAmount);
    }

    function setValidChainId(uint256 chainId, bool isValid) external onlyReLayer {
        IsSupportedChainId[chainId] = isValid;
        emit SetValidChainId(chainId, isValid);
    }

    function setSupportERC20Token(address ERC20Address, bool isValid) external onlyReLayer {
        IsSupportToken[ERC20Address] = isValid;
        if (isValid) {
            SupportTokens.push(ERC20Address);
        }
        emit SetSupportTokenEvent(ERC20Address, isValid, block.chainid);
    }

    function setPerFee(uint256 _PerFee) external onlyReLayer {
        require(_PerFee < 1_000_000);
        PerFee = _PerFee;
        emit SetPerFee(_PerFee);
    }

    function setSupportToken(address _token, bool _isSupport, uint32 startTimes) external onlyReLayer {
        if (IsSupportToken[_token]) {
            revert TokenIsAlreadySupported(_token, _isSupport);
        }
        IsSupportToken[_token] = _isSupport;
        //genesis pool
        Pools[_token].push(Pool({
            startTimestamp: uint32(startTimes) - periodTime,
            endTimestamp: startTimes,
            token: _token,
            TotalAmount: 0,
            TotalFee: 0,
            TotalFeeClaimed: 0,
            IsCompleted: false
        }));

        //genesis bridge
        Pools[_token].push(Pool({
            startTimestamp: uint32(startTimes),
            endTimestamp: startTimes + periodTime,
            token: _token,
            TotalAmount: 0,
            TotalFee: 0,
            TotalFeeClaimed: 0,
            IsCompleted: false
        }));

        //Next bridge
        SupportTokens.push(_token);
        emit SetSupportTokenEvent(_token, _isSupport, block.chainid);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function IsSupportChainId(uint256 chainId) internal view returns (bool) {
        return IsSupportedChainId[chainId];
    }
}
