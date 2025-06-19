// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../interfaces/IPoolManager.sol";
import "../libraries/ContractsAddress.sol";
import "../libraries/SafeCall.sol";
import "./PoolManagerStorage.sol";

contract PoolManager is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PoolManagerStorage {
    function initialize(address _MultisigWallet, address _messageManager) public initializer  {
        MinTransferAmount = 0.1 ether;
        PerFee = 10000;
        _grantRole(DEFAULT_ADMIN_ROLE, _MultisigWallet);
        messageManager = IMessageManager(_messageManager);
        stakingMessageNumber = 1;
    }


    function DepositAndStaking(address _token, uint256 _amount) public payable override whenNotPaused {
        if (msg.value > 0) {
            DepositAndStakingETH();
        } else if (IsSupportToken[_token]) {
            DepositAndStakingERC20(_token, _amount);
        }
    }

    function DepositAndStakingERC20(address _token, uint256 _amount) public override nonReentrant whenNotPaused {
        if (!IsSupportToken[_token]) {
            revert TokenIsNotSupported(_token);
        }

        if (_amount < MinStakeAmount[_token]) {
            revert LessThanMinStakeAmount(MinStakeAmount[_token], _amount);
        }

        uint256 BalanceBefore = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 BalanceAfter = IERC20(_token).balanceOf(address(this));

        _amount = BalanceAfter - BalanceBefore;

        if (Pools[_token].length == 0) {
            revert NewPoolIsNotCreate(1);
        }

        uint256 PoolIndex = Pools[_token].length - 1;
        if (Pools[_token][PoolIndex].startTimestamp > block.timestamp) {
            Users[msg.sender].push(
                User({
                    isWithdrawed: false,
                    StartPoolId: PoolIndex,
                    EndPoolId: 0,
                    token: _token,
                    Amount: _amount
                })
            );
            Pools[_token][PoolIndex].TotalAmount += _amount;
        } else {
            revert NewPoolIsNotCreate(PoolIndex + 1);
        }
        FundingPoolBalance[_token] += _amount;
        emit StarkingERC20Event(msg.sender, _token, _amount);
    }

    function WithdrawAll() external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < SupportTokens.length; i++) {
            WithdrawOrClaimBySimpleAsset(msg.sender, SupportTokens[i], true);
        }
    }

    function ClaimAllReward() external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < SupportTokens.length; i++) {
            WithdrawOrClaimBySimpleAsset(msg.sender, SupportTokens[i], false);
        }
    }

    function WithdrawByID(uint i) external nonReentrant whenNotPaused {
        if (i >= Users[msg.sender].length) {
            revert OutOfRange(i, Users[msg.sender].length);
        }
        WithdrawOrClaimBySimpleID(msg.sender, i, true);
    }

    function ClaimbyID(uint i) external nonReentrant whenNotPaused {
        if (i >= Users[msg.sender].length) {
            revert OutOfRange(i, Users[msg.sender].length);
        }
        WithdrawOrClaimBySimpleID(msg.sender, i, false);
    }


    function DepositAndStakingETH() public payable override nonReentrant whenNotPaused {
        if (msg.value < MinStakeAmount[address(ContractsAddress.ETHAddress)]) {
            revert LessThanMinStakeAmount(
                MinStakeAmount[address(ContractsAddress.ETHAddress)],
                msg.value
            );
        }

        if (Pools[address(ContractsAddress.ETHAddress)].length == 0) {
            revert NewPoolIsNotCreate(1);
        }

        uint256 PoolIndex = Pools[address(ContractsAddress.ETHAddress)].length - 1;
        if (Pools[address(ContractsAddress.ETHAddress)][PoolIndex].startTimestamp > block.timestamp) {
            Users[msg.sender].push(
                User({
                    isWithdrawed: false,
                    StartPoolId: PoolIndex,
                    EndPoolId: 0,
                    token: ContractsAddress.ETHAddress,
                    Amount: msg.value
                })
            );
            Pools[address(ContractsAddress.ETHAddress)][PoolIndex].TotalAmount += msg.value;
        } else {
            revert NewPoolIsNotCreate(PoolIndex + 1);
        }
        FundingPoolBalance[ContractsAddress.ETHAddress] += msg.value;
        emit StakingETHEvent(msg.sender, msg.value);
    }


    function BridgeInitiateETH(uint256 sourceChainId, uint256 destChainId, address to) external payable returns (bool) {
        if (sourceChainId != block.chainid) {
            revert sourceChainIdError();
        }

        if (!IsSupportChainId(destChainId)) {
            revert ChainIdIsNotSupported(destChainId);
        }

        if (msg.value < MinTransferAmount) {
            revert LessThanMinTransferAmount(MinTransferAmount, msg.value);
        }

        FundingPoolBalance[ContractsAddress.ETHAddress] += msg.value;

        uint256 fee = (msg.value * PerFee) / 1_000_000;
        uint256 amount = msg.value - fee;

        FeePoolValue[ContractsAddress.ETHAddress] += fee;

        messageManager.sendMessage(block.chainid, destChainId, to, amount, fee);

        emit InitiateETH(sourceChainId, destChainId, msg.sender, to, amount);

        return true;
    }

    function BridgeInitiateERC20(uint256 sourceChainId, uint256 destChainId, address to, address ERC20Address, uint256 value) external returns (bool) {
        if (sourceChainId != block.chainid) {
            revert sourceChainIdError();
        }

        if (!IsSupportChainId(destChainId)) {
            revert ChainIdIsNotSupported(destChainId);
        }

        if (!IsSupportToken[ERC20Address]) {
            revert TokenIsNotSupported(ERC20Address);
        }

        uint256 BalanceBefore = IERC20(ERC20Address).balanceOf(address(this));
        IERC20(ERC20Address).safeTransferFrom(msg.sender, address(this), value);
        uint256 BalanceAfter = IERC20(ERC20Address).balanceOf(address(this));

        uint256 amount = BalanceAfter - BalanceBefore;
        FundingPoolBalance[ERC20Address] += value;
        uint256 fee = (amount * PerFee) / 1_000_000;

        amount -= fee;
        FeePoolValue[ERC20Address] += fee;

        messageManager.sendMessage(sourceChainId, destChainId, to, amount, fee);

        emit InitiateERC20(
            sourceChainId,
            destChainId,
            ERC20Address,
            msg.sender,
            to,
            amount
        );

        return true;
    }

    function BridgeFinalizeETH(uint256 sourceChainId, uint256 destChainId, address to, uint256 amount, uint256 _fee, uint256 _nonce) external payable onlyRole(ReLayer) returns (bool) {
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

        FundingPoolBalance[ContractsAddress.ETHAddress] -= amount;

        messageManager.claimMessage(
            sourceChainId,
            destChainId,
            to,
            _fee,
            amount,
            _nonce
        );

        emit FinalizeETH(sourceChainId, destChainId, address(this), to, amount);

        return true;
    }

    function BridgeFinalizeERC20(uint256 sourceChainId, uint256 destChainId, address to, address ERC20Address, uint256 amount, uint256 _fee, uint256 _nonce) external onlyRole(ReLayer) returns (bool) {
        if (destChainId != block.chainid) {
            revert sourceChainIdError();
        }

        if (!IsSupportChainId(sourceChainId)) {
            revert ChainIdIsNotSupported(sourceChainId);
        }

        if (!IsSupportToken[ERC20Address]) {
            revert TokenIsNotSupported(ERC20Address);
        }

        IERC20(ERC20Address).safeTransfer(to, amount);
        FundingPoolBalance[ERC20Address] -= amount;

        messageManager.claimMessage(
            sourceChainId,
            destChainId,
            to,
            _fee,
            amount,
            _nonce
        );

        emit FinalizeERC20(
            sourceChainId,
            destChainId,
            ERC20Address,
            address(this),
            to,
            amount
        );
        return true;
    }

    function IsSupportChainId(uint256 chainId) public view returns (bool) {
        return IsSupportedChainId[chainId];
    }

    function WithdrawPoolManagerAssetTo(address _token, address to, uint256 _amount) external onlyRole(ReLayer) {
        if (!IsSupportToken[_token]) {
            revert TokenIsNotSupported(_token);
        }

        require((FundingPoolBalance[_token]>=_amount),"Not enough balance");

        FundingPoolBalance[_token] -= _amount;

        if (_token == address(ContractsAddress.ETHAddress)) {
            if (address(this).balance < _amount) {
                revert NotEnoughETH();
            }
            (bool _ret, ) = payable(to).call{value: _amount}("");
            if (!_ret) {
                revert TransferETHFailed();
            }
        } else {
            if (IERC20(_token).balanceOf(address(this)) < _amount) {
                revert NotEnoughToken(_token);
            }
            IERC20(_token).safeTransfer(to, _amount);
        }
        return true;
    }

    function getPrincipal() public view returns (KeyValuePair[] memory) {
        KeyValuePair[] memory result = new KeyValuePair[](SupportTokens.length);
        for (uint256 i = 0; i < SupportTokens.length; i++) {
            uint256 Amount = 0;
            for (uint256 j = 0; j < Users[msg.sender].length; j++) {
                if (Users[msg.sender][j].token == SupportTokens[i]) {
                    if (Users[msg.sender][j].isWithdrawed) {
                        continue;
                    }
                    Amount += Users[msg.sender][j].Amount;
                }
            }
            result[i] = KeyValuePair({key: SupportTokens[i], value: Amount});
        }
        return result;
    }

    function getReward() public view returns (KeyValuePair[] memory) {
        KeyValuePair[] memory result = new KeyValuePair[](SupportTokens.length);
        for (uint256 i = 0; i < SupportTokens.length; i++) {
            uint256 Reward = 0;
            for (uint256 j = 0; j < Users[msg.sender].length; j++) {
                if (Users[msg.sender][j].token == SupportTokens[i]) {
                    if (Users[msg.sender][j].isWithdrawed) {
                        continue;
                    }
                    uint256 EndPoolId = Pools[SupportTokens[i]].length - 1;

                    uint256 Amount = Users[msg.sender][j].Amount;
                    uint256 startPoolId = Users[msg.sender][j].StartPoolId;
                    if (startPoolId > EndPoolId) {
                        continue;
                    }

                    for (uint256 k = startPoolId; k < EndPoolId; k++) {
                        if (k > Pools[SupportTokens[i]].length - 1) {
                            revert NewPoolIsNotCreate(k);
                        }
                        uint256 _Reward = (Amount * Pools[SupportTokens[i]][k].TotalFee) / Pools[SupportTokens[i]][k].TotalAmount;
                        Reward += _Reward;
                    }
                }
            }
            result[i] = KeyValuePair({key: SupportTokens[i], value: Reward});
        }
        return result;
    }

    function setMinTransferAmount(uint256 _MinTransferAmount) external onlyRole(ReLayer) {
        MinTransferAmount = _MinTransferAmount;
    }

    function setValidChainId(uint256 chainId, bool isValid) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IsSupportedChainId[chainId] = isValid;
    }

    function setSupportERC20Token(address ERC20Address, bool isValid) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IsSupportToken[ERC20Address] = isValid;
        if (isValid) {
            SupportTokens.push(ERC20Address);
        }
    }

    function setPerFee(uint256 _PerFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_PerFee < 1_000_000);
        PerFee = _PerFee;
    }

    function setMinStakeAmount(address _token, uint256 _amount) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_amount == 0) {
            revert Zero(_amount);
        }
        MinStakeAmount[_token] = _amount;
        emit SetMinStakeAmountEvent(_token, _amount);
    }

    function setSupportToken(address _token, bool _isSupport, uint32 startTimes) external override onlyRole(DEFAULT_ADMIN_ROLE) {
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
        emit SetSupportTokenEvent(_token, _isSupport);
    }

    /***************************************
    ***** Relayer function *****
    ***************************************/
    function CompletePoolAndNew(Pool[] memory CompletePools) external payable onlyRole(ReLayer) {
        for (uint256 i = 0; i < CompletePools.length; i++) {
            address _token = CompletePools[i].token;
            uint PoolIndex = Pools[_token].length - 1;
            Pools[_token][PoolIndex - 1].IsCompleted = true;
            if (PoolIndex - 1 != 0) {
                Pools[_token][PoolIndex - 1].TotalFee = FeePoolValue[_token];
                FeePoolValue[_token] = 0;
            }
            uint32 startTimes = Pools[_token][PoolIndex].endTimestamp;
            Pools[_token].push(
                Pool({
                    startTimestamp: startTimes,
                    endTimestamp: startTimes + periodTime,
                    token: _token,
                    TotalAmount: Pools[_token][PoolIndex].TotalAmount,
                    TotalFee: 0,
                    TotalFeeClaimed: 0,
                    IsCompleted: false
                })
            );
            emit CompletePoolEvent(_token, PoolIndex);
        }
    }

    /***************************************
    ***** internal function *****
    ***************************************/
    function WithdrawOrClaimBySimpleAsset(address _user, address _token, bool IsWithdraw) internal {
        if (Pools[_token].length == 0) {
            revert NewPoolIsNotCreate(0);
        }

        for (uint256 index = 0; index < Users[_user].length; index++) {
            if (Users[_user][index].token == _token) {
                if (Users[_user][index].isWithdrawed) {
                    continue;
                }

                uint256 EndPoolId = Pools[_token].length - 1;

                uint256 Reward = 0;
                uint256 Amount = Users[_user][index].Amount;
                uint256 startPoolId = Users[_user][index].StartPoolId;

                for (uint256 j = startPoolId; j < EndPoolId; j++) {
                    uint256 _Reward = (Amount * Pools[_token][j].TotalFee * 1e18) / Pools[_token][j].TotalAmount;
                    Reward += _Reward / 1e18;
                    Pools[_token][j].TotalFeeClaimed += _Reward;
                }

                Amount += Reward;
                Users[_user][index].isWithdrawed = true;

                if (IsWithdraw) {
                    Pools[_token][EndPoolId].TotalAmount -= Users[_user][index].Amount;
                    WithdrawPoolManagerAssetTo(_token, _user, Amount);
                    if (Users[_user].length > 0) {
                        Users[_user][index] = Users[_user][Users[_user].length - 1];
                        Users[_user].pop();
                        index--;
                    }
                    emit Withdraw(_user, startPoolId, EndPoolId, _token, Amount - Reward, Reward);
                } else {
                    Users[_user][index].StartPoolId = EndPoolId;
                    WithdrawPoolManagerAssetTo(_token, _user, Reward);
                    emit ClaimReward(_user, startPoolId, EndPoolId, _token, Reward);
                }
            }
        }
    }

    function WithdrawOrClaimBySimpleID(address _user, uint index, bool IsWithdraw) internal {
        address _token = Users[_user][index].token;
        uint256 EndPoolId = Pools[_token].length - 1;

        uint256 Reward = 0;
        uint256 Amount = Users[_user][index].Amount;
        uint256 startPoolId = Users[_user][index].StartPoolId;
        if (Users[_user][index].isWithdrawed) {
            revert NoReward();
        }

        for (uint256 j = startPoolId; j < EndPoolId; j++) {
            uint256 _Reward = (Amount * Pools[_token][j].TotalFee * 1e18) / Pools[_token][j].TotalAmount;
            Reward += _Reward / 1e18;
            Pools[_token][j].TotalFeeClaimed += _Reward;
        }

        Amount += Reward;
        Users[_user][index].isWithdrawed = true;
        if (IsWithdraw) {
            Pools[_token][EndPoolId].TotalAmount -= Users[_user][index].Amount;
            SendAssertToUser(_token, _user, Amount);
            if (Users[_user].length > 0) {
                Users[_user][index] = Users[_user][Users[_user].length - 1];
                Users[_user].pop();
            }
            emit Withdraw(_user, startPoolId, EndPoolId, _token, Amount - Reward, Reward);
        } else {
            Users[_user][index].StartPoolId = EndPoolId;
            SendAssertToUser(_token, _user, Reward);
            emit ClaimReward(_user, startPoolId, EndPoolId, _token, Reward);
        }
    }
}
