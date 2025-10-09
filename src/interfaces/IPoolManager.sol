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

    event SetSupportTokenEvent(address indexed token, bool isSupport, uint256 chainId);
    event SetValidChainId(uint256 chainId, bool isValid);
    event SetPerFee(uint256 chainId);
    event SetMinTransferAmount(uint256 _MinTransferAmount);

    error TokenIsAlreadySupported(address token, bool isSupported);

    error ChainIdIsNotSupported(uint256 id);

    error TokenIsNotSupported(address ERC20Address);

    error LessThanMinTransferAmount(uint256 MinTransferAmount, uint256 value);

    error sourceChainIdError();

    error TransferETHFailed();

    function BridgeInitiateETH(uint256 sourceChainId, uint256 destChainId, address destTokenAddress, address to) external payable returns (bool);
    function BridgeInitiateERC20(uint256 sourceChainId, uint256 destChainId, address to, address sourceTokenAddress, address destTokenAddress, uint256 value) external returns (bool);

    function BridgeFinalizeETH(uint256 sourceChainId, uint256 destChainId, address sourceTokenAddress, address from, address to, uint256 amount, uint256 _fee, uint256 _nonce) external payable returns (bool);
    function BridgeFinalizeERC20(uint256 sourceChainId, uint256 destChainId, address from, address to, address sourceTokenAddress, address destTokenAddress, uint256 amount, uint256 _fee, uint256 _nonce) external returns (bool);

    function setMinTransferAmount(uint256 _MinTransferAmount) external;
    function setValidChainId(uint256 chainId, bool isValid) external;
    function setSupportERC20Token(address ERC20Address, bool isValid) external;
    function setPerFee(uint256 _PerFee) external;
    function setSupportToken(address _token, bool _isSupport, uint32 startTimes) external;

    function fetchFundingPoolBalance(address token) external view returns(uint256);

    function pause() external;
    function unpause() external;
}
