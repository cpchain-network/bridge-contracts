// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../interfaces/IMessageManager.sol";
import "../../interfaces/IPoolManager.sol";

abstract contract PoolManagerStorage is IPoolManager{
    bytes32 public constant ReLayer = keccak256(abi.encode(uint256(keccak256("ReLayer")) - 1)) & ~bytes32(uint256(0xff));

    using SafeERC20 for IERC20;

    uint32 public periodTime;


    uint256 public MinTransferAmount;
    uint256 public PerFee; // 0.1%
    uint256 public stakingMessageNumber;


    IMessageManager public messageManager;


    address[] public SupportTokens;
    address public assetBalanceMessager;


    mapping(uint256 => bool) private IsSupportedChainId;
    mapping(address => bool) public IsSupportToken;
    mapping(address => uint256) public FundingPoolBalance;
    mapping(address => uint256) public FeePoolValue;
    mapping(address => uint256) public MinStakeAmount;

    mapping(address => Pool[]) public Pools;
    mapping(address => User[]) public Users;

}
