// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/IMessageManager.sol";
import "../interfaces/IPoolManager.sol";

abstract contract PoolManagerStorage is IPoolManager{

    address public constant ETHAddress = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    uint32 public periodTime;

    uint256 public MinTransferAmount;
    uint256 public PerFee; // 0.1%
    uint256 public stakingMessageNumber;

    address public relayerAddress;

    IMessageManager public messageManager;


    address[] public SupportTokens;
    address public assetBalanceMessager;


    mapping(uint256 => bool) public IsSupportedChainId;
    mapping(address => bool) public IsSupportToken;
    mapping(address => uint256) public FundingPoolBalance;
    mapping(address => uint256) public FeePoolValue;
    mapping(address => uint256) public MinStakeAmount;

    mapping(address => Pool[]) public Pools;
    mapping(address => User[]) public Users;

}
