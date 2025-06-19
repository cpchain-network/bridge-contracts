// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IPoolManager {
    struct Pool {
        uint32 startTimestamp;
        uint32 endTimestamp;
        address token;
        uint256 TotalAmount;
        uint256 TotalFee;
        uint256 TotalFeeClaimed;
        bool IsCompleted;
    }

    struct User {
        bool isWithdrawed;
        address token;
        uint256 StartPoolId;
        uint256 EndPoolId;
        uint256 Amount;
    }

    struct KeyValuePair {
        address key;
        uint value;
    }

    event StarkingERC20Event(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    event StakingETHEvent(
        address indexed user,
        uint256 amount
    );

    event InitiateETH(
        uint256 sourceChainId,
        uint256 destChainId,
        address indexed from,
        address indexed to,
        uint256 value
    );

    event InitiateERC20(
        uint256 sourceChainId,
        uint256 destChainId,
        address indexed ERC20Address,
        address indexed from,
        address indexed to,
        uint256 value
    );

    event FinalizeETH(
        uint256 sourceChainId,
        uint256 destChainId,
        address indexed from,
        address indexed to,
        uint256 value
    );

    event FinalizeERC20(
        uint256 sourceChainId,
        uint256 destChainId,
        address indexed ERC20Address,
        address indexed from,
        address indexed to,
        uint256 value
    );

    error NoReward();

    error NewPoolIsNotCreate(uint256 PoolIndex);

    error LessThanMinStakeAmount(uint256 minAmount, uint256 providedAmount);

    error PoolIsCompleted(uint256 poolIndex);

    error AlreadyClaimed();

    error LessThanZero(uint256 amount);

    error Zero(uint256 amount);

    error TokenIsAlreadySupported(address token, bool isSupported);

    error OutOfRange(uint256 PoolId, uint256 PoolLength);

    error ChainIdIsNotSupported(uint256 id);

    error ChainIdNotSupported(uint256 chainId);

    error TokenIsNotSupported(address ERC20Address);

    error NotEnoughToken(address ERC20Address);

    error NotEnoughETH();

    error ErrorBlockChain();

    error LessThanMinTransferAmount(uint256 MinTransferAmount, uint256 value);

    error sourceChainIdError();

    error sourceChainIsDestChainError();

    error TransferETHFailed();

    function BridgeInitiateETH(uint256 sourceChainId, uint256 destChainId, address to) external payable returns (bool);
    function BridgeInitiateERC20(uint256 sourceChainId, uint256 destChainId, address to, address ERC20Address, uint256 value) external returns (bool);

    function BridgeFinalizeETH(uint256 sourceChainId, uint256 destChainId, address to, uint256 amount, uint256 _fee, uint256 _nonce) external payable onlyRole(ReLayer) returns (bool);
    function BridgeFinalizeERC20(uint256 sourceChainId, uint256 destChainId, address to, address ERC20Address, uint256 amount, uint256 _fee, uint256 _nonce) external onlyRole(ReLayer) returns (bool);

    function IsSupportChainId(uint256 chainId) public view returns (bool);

    function WithdrawPoolManagerAssetTo(address _token, address to, uint256 _amount) external;

    function setMinTransferAmount(uint256 _MinTransferAmount) external;

    function setValidChainId(uint256 chainId, bool isValid) external;

    function setSupportERC20Token(address ERC20Address, bool isValid) external;

    function setPerFee(uint256 _PerFee) external;
}
