// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

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

    event DepositToken(
        address indexed tokenAddress,
        address indexed sender,
        uint256 amount
    );

    event WithdrawToken(
        address indexed tokenAddress,
        address sender,
        address withdrawAddress,
        uint256 amount
    );

    event StarkingERC20Event(
        address indexed user,
        address indexed token,
        uint256 chainId,
        uint256 amount
    );

    event StakingETHEvent(
        address indexed user,
        uint256 chainId,
        uint256 amount
    );

    event InitiateETH(
        uint256 sourceChainId,
        uint256 destChainId,
        address destTokenAddress,
        address indexed from,
        address indexed to,
        uint256 value
    );

    event InitiateERC20(
        uint256 sourceChainId,
        uint256 destChainId,
        address sourceTokenAddress,
        address destTokenAddress,
        address indexed from,
        address indexed to,
        uint256 value
    );

    event FinalizeETH(
        uint256 sourceChainId,
        uint256 destChainId,
        address sourceTokenAddress,
        address indexed from,
        address indexed to,
        uint256 value
    );

    event FinalizeERC20(
        uint256 sourceChainId,
        uint256 destChainId,
        address sourceTokenAddress,
        address destTokenAddress,
        address indexed from,
        address indexed to,
        uint256 value
    );

    event ClaimReward(
        address _user,
        uint256 startPoolId,
        uint256 EndPoolId,
        uint256 chainId,
        address _token,
        uint Reward
    );

    event Withdraw(
        address _user,
        uint256 startPoolId,
        uint256 EndPoolId,
        uint256 chainId,
        address _token,
        uint Amount,
        uint Reward
    );

    event CompletePoolEvent(address indexed token, uint256 poolIndex, uint256 chainId);
    event SetMinStakeAmountEvent(address indexed token, uint256 amount, uint256 chainId);
    event SetSupportTokenEvent(address indexed token, bool isSupport, uint256 chainId);
    event SetValidChainId(uint256 chainId, bool isValid);
    event SetPerFee(uint256 chainId);
    event SetMinTransferAmount(uint256 _MinTransferAmount);

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

    function BridgeInitiateETH(uint256 sourceChainId, uint256 destChainId, address destTokenAddress, address to) external payable returns (bool);
    function BridgeInitiateERC20(uint256 sourceChainId, uint256 destChainId, address to, address sourceTokenAddress, address destTokenAddress, uint256 value) external returns (bool);

    function BridgeFinalizeETH(uint256 sourceChainId, uint256 destChainId, address sourceTokenAddress, address from, address to, uint256 amount, uint256 _fee, uint256 _nonce) external payable returns (bool);
    function BridgeFinalizeERC20(uint256 sourceChainId, uint256 destChainId, address from, address to, address sourceTokenAddress, address destTokenAddress, uint256 amount, uint256 _fee, uint256 _nonce) external returns (bool);

    function DepositAndStakingETH() external payable;
    function DepositAndStakingERC20(address _token, uint256 _amount) external;

    function CompletePoolAndNew(Pool[] memory CompletePools) external payable;

    function WithdrawAll() external;
    function ClaimAllReward() external;
    function WithdrawByID(uint i) external;
    function ClaimbyID(uint i) external;
    function QuickSendAssertToUser(address _token, address to, uint256 _amount) external;
    function getPrincipal() external view returns (KeyValuePair[] memory);
    function getReward() external view returns (KeyValuePair[] memory);
    function WithdrawPoolManagerAssetTo(address _token, address to, uint256 _amount) external;

    function setMinTransferAmount(uint256 _MinTransferAmount) external;
    function setValidChainId(uint256 chainId, bool isValid) external;
    function setSupportERC20Token(address ERC20Address, bool isValid) external;
    function setPerFee(uint256 _PerFee) external;
    function setMinStakeAmount(address _token, uint256 _amount) external;
    function setSupportToken(address _token, bool _isSupport, uint32 startTimes) external;

    function fetchFundingPoolBalance(address token) external view returns(uint256);
    function getPoolLength(address _token) external view returns (uint256);
    function getUserLength(address _user) external view returns (uint256) ;
    function getPool(address _token, uint256 _index) external view returns (Pool memory);
    function getUser(address _user) external view returns (User[] memory);

    function pause() external;
    function unpause() external;
}
