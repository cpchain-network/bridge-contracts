// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PoolManager} from "../src/core/PoolManager.sol";
import {MessageManager} from "../src/core/MessageManager.sol";
import {mockToken} from "../script/utils/mockERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract PoolManagerTest is Test {
    PoolManager public sourcePoolManager;
    PoolManager public destPoolManager;
    MessageManager public sourceMessageManager;
    MessageManager public destMessageManager;

    mockToken public erc20Token;

    uint256 constant SOURCE_CHAIN_ID = 1;
    uint256 constant DEST_CHAIN_ID = 10;

    address cat = makeAddr("cat");
    address seek = makeAddr("seek");

    address bridge_cat = makeAddr("bridge_cat");
    address bridge_seek = makeAddr("bridge_seek");

    address admin;
    address ReLayer;

    function setUp() public {
        admin = makeAddr("admin");
        ReLayer = makeAddr("ReLayer");

        PoolManager poolManagerLogic = new PoolManager();
        MessageManager messageManagerLogic = new MessageManager();
        erc20Token = new mockToken("CAT", "CAT");

        vm.startPrank(admin);
        TransparentUpgradeableProxy sourcePoolManagerProxy = new TransparentUpgradeableProxy(address(poolManagerLogic), admin, "");
        TransparentUpgradeableProxy sourceMessageManagerProxy = new TransparentUpgradeableProxy(address(messageManagerLogic), admin, "");
        TransparentUpgradeableProxy destPoolManagerProxy = new TransparentUpgradeableProxy(address(poolManagerLogic), admin, "");
        TransparentUpgradeableProxy destMessageManagerProxy = new TransparentUpgradeableProxy(address(messageManagerLogic), admin, "");

        sourcePoolManager = PoolManager(payable(address(sourcePoolManagerProxy)));
        destPoolManager = PoolManager(payable(address(destPoolManagerProxy)));
        sourceMessageManager = MessageManager(address(sourceMessageManagerProxy));
        destMessageManager = MessageManager(address(destMessageManagerProxy));

        sourcePoolManager.initialize(admin, address(sourceMessageManager), ReLayer, admin);
        destPoolManager.initialize(admin, address(destMessageManager), ReLayer, admin);
        sourceMessageManager.initialize(admin, address(sourcePoolManager));
        destMessageManager.initialize(admin, address(destPoolManager));
        vm.stopPrank();

        vm.startPrank(ReLayer);
        sourcePoolManager.setValidChainId(DEST_CHAIN_ID, true);
        destPoolManager.setValidChainId(SOURCE_CHAIN_ID, true);
        vm.stopPrank();
    }

    // Test bridging ETH from source to destination chain
    function test_Bridge_ETH() public {
        _bridge_ETH(10, cat, seek);
    }

    // Test bridging ERC20 tokens from source to destination chain
    function test_Bridge_ERC20() public {
        vm.startPrank(ReLayer);
        sourcePoolManager.setSupportERC20Token(address(erc20Token), true);
        destPoolManager.setSupportERC20Token(address(erc20Token), true);
        vm.stopPrank();

        _bridge_ERC20(10, cat, seek);
    }

    // Test the complete ETH staking lifecycle including rewards
    function test_Full_ETH_Staking_And_Reward_Lifecycle() public {
        uint256 stakeAmount = 1 ether;
        vm.deal(cat, 10 ether);
        address ethTokenAddress = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        uint32 startTime = uint32(block.timestamp + 2400 hours);

        vm.startPrank(ReLayer);
        sourcePoolManager.setSupportToken(ethTokenAddress, true, startTime);
        vm.stopPrank();

        vm.warp(startTime - 1 hours);

        vm.prank(cat);
        sourcePoolManager.DepositAndStakingETH{value: stakeAmount}();

        assertEq(address(sourcePoolManager).balance, stakeAmount, "Contract ETH balance should increase by stakeAmount");
        assertEq(sourcePoolManager.FundingPoolBalance(ethTokenAddress), stakeAmount, "FundingPoolBalance for ETH should be updated");

        (uint32 poolStartTime, , , uint256 totalAmount, , , bool isCompleted) = sourcePoolManager.Pools(ethTokenAddress, 1);
        assertEq(poolStartTime, startTime, "Pool start time should match");
        assertEq(totalAmount, stakeAmount, "Pool's total amount should be updated");
        assertEq(isCompleted, false, "Pool's IsCompleted flag should be false");

        uint256 bridgeCalls = 10;
        uint256 singleBridgeAmount = 1 ether;
        uint256 totalBridgedAmount = bridgeCalls * singleBridgeAmount;

        for (uint256 i = 0; i < bridgeCalls; i++) {
            _bridge_ETH(1, bridge_cat, bridge_seek);
        }

        assertEq(sourcePoolManager.FundingPoolBalance(ethTokenAddress), stakeAmount + totalBridgedAmount, "Final FundingPoolBalance should be stake + total bridged");

        uint256 perFee = sourcePoolManager.PerFee();
        uint256 expectedTotalFee = (totalBridgedAmount * perFee) / 1_000_000;
        assertEq(sourcePoolManager.FeePoolValue(ethTokenAddress), expectedTotalFee, "Total accumulated fee is incorrect");

        PoolManager.Pool memory poolToComplete = sourcePoolManager.getPool(ethTokenAddress, 1);
        vm.warp(poolToComplete.endTimestamp + 1 hours);

        vm.startPrank(ReLayer);
        PoolManager.Pool[] memory poolsToCompleteArray = new PoolManager.Pool[](1);
        poolsToCompleteArray[0] = poolToComplete;
        sourcePoolManager.CompletePoolAndNew(poolsToCompleteArray);
        vm.stopPrank();

        assertEq(sourcePoolManager.getPoolLength(ethTokenAddress), 3, "A new pool (index 2) should be created");

        PoolManager.Pool memory completedPoolInfo = sourcePoolManager.getPool(ethTokenAddress, 1);
        assertEq(completedPoolInfo.TotalFee, expectedTotalFee, "Completed pool's total fee was not set correctly");
        assertTrue(completedPoolInfo.IsCompleted, "Pool 1 should be marked as completed");
        assertEq(sourcePoolManager.FeePoolValue(ethTokenAddress), 0, "FeePoolValue should be reset");
    }

    function _bridge_ETH(uint256 amount, address from ,address to) internal {
        uint256 bridgeAmount = amount * 1 ether;
        vm.deal(from, bridgeAmount);

        address ethTokenAddress = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        uint256 balanceBefore = sourcePoolManager.FundingPoolBalance(ethTokenAddress);
        uint256 nextMessageNumberBefore = sourceMessageManager.nextMessageNumber();

        vm.chainId(SOURCE_CHAIN_ID);
        vm.prank(from);
        sourcePoolManager.BridgeInitiateETH{value: bridgeAmount}(SOURCE_CHAIN_ID, DEST_CHAIN_ID, seek);

        assertEq(sourcePoolManager.FundingPoolBalance(ethTokenAddress), balanceBefore + bridgeAmount, "FundingPoolBalance for ETH should increase by bridgeAmount");
        assertEq(sourceMessageManager.nextMessageNumber(), nextMessageNumberBefore + 1, "nextMessageNumber should be incremented");

        uint256 perFee = sourcePoolManager.PerFee();
        uint256 fee = (bridgeAmount * perFee) / 1_000_000;
        uint256 amountAfterFee = bridgeAmount - fee;

        uint256 messageNonce = nextMessageNumberBefore;
        bytes32 messageHash = keccak256(
            abi.encode(SOURCE_CHAIN_ID, DEST_CHAIN_ID, seek, fee, amountAfterFee, messageNonce)
        );

        assertTrue(sourceMessageManager.sentMessageStatus(messageHash), "Message hash should be marked as sent");
    }

    function _bridge_ERC20(uint256 amount, address from ,address to) internal {
        uint256 bridgeAmount = amount * 1 ether;
        erc20Token.mint(from, bridgeAmount);

        uint256 balanceBefore = sourcePoolManager.FundingPoolBalance(address(erc20Token));
        uint256 nextMessageNumberBefore = sourceMessageManager.nextMessageNumber();

        vm.chainId(SOURCE_CHAIN_ID);
        vm.startPrank(from);
        erc20Token.approve(address(sourcePoolManager), bridgeAmount);
        sourcePoolManager.BridgeInitiateERC20(SOURCE_CHAIN_ID, DEST_CHAIN_ID, seek, address(erc20Token), address(erc20Token), bridgeAmount);
        vm.stopPrank();

        assertEq(erc20Token.balanceOf(address(sourcePoolManager)), balanceBefore + bridgeAmount, "Contract ERC20 balance should equal bridgeAmount");
        assertEq(sourcePoolManager.FundingPoolBalance(address(erc20Token)), balanceBefore +bridgeAmount, "FundingPoolBalance for ERC20 should equal bridgeAmount");
        assertEq(sourceMessageManager.nextMessageNumber(), nextMessageNumberBefore + 1, "nextMessageNumber should be incremented");

        uint256 perFee = sourcePoolManager.PerFee();
        uint256 fee = (bridgeAmount * perFee) / 1_000_000;
        uint256 amountAfterFee = bridgeAmount - fee;

        uint256 messageNonce = 1;
        bytes32 messageHash = keccak256(
            abi.encode(SOURCE_CHAIN_ID, DEST_CHAIN_ID, seek, fee, amountAfterFee, messageNonce)
        );

        assertTrue(sourceMessageManager.sentMessageStatus(messageHash), "Message hash for ERC20 bridge should be marked as sent");
    }

    // Test withdrawing a specific stake by ID
    function test_WithdrawByID() public {
        (uint256 ethStake,) = _setupStakingAndGenerateFees();

        address ethTokenAddress = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        PoolManager.Pool memory ethPool = sourcePoolManager.getPool(ethTokenAddress, 1);

        uint256 expectedEthReward = (ethStake * ethPool.TotalFee) / ethPool.TotalAmount;

        uint256 ethBalanceBefore = cat.balance;

        vm.prank(cat);
        sourcePoolManager.WithdrawByID(0);

        uint256 ethBalanceAfter = cat.balance;

        uint256 actualEthReward = ethBalanceAfter - ethBalanceBefore - ethStake;

        assertEq(ethBalanceAfter - ethBalanceBefore, ethStake + expectedEthReward, "ETH withdrawal (principal + reward) is incorrect");

        assertEq(actualEthReward, expectedEthReward, "ETH reward calculation is incorrect");

        uint256 expectedRemainingEthBalance = 5 ether - (5 ether * sourcePoolManager.PerFee()) / 1_000_000;
        assertEq(sourcePoolManager.FundingPoolBalance(ethTokenAddress), expectedRemainingEthBalance, "FundingPoolBalance for ETH should equal bridged amount minus fees");

        assertEq(sourcePoolManager.FeePoolValue(ethTokenAddress), 0, "FeePoolValue for ETH should be 0");
    }

    // Test withdrawing all stakes at once
    function test_withdraw_All() public {
        (uint256 ethStake, uint256 erc20Stake) = _setupStakingAndGenerateFees();

        address ethTokenAddress = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        PoolManager.Pool memory ethPool = sourcePoolManager.getPool(ethTokenAddress, 1);
        PoolManager.Pool memory erc20Pool = sourcePoolManager.getPool(address(erc20Token), 1);

        uint256 expectedEthReward = (ethStake * ethPool.TotalFee) / ethPool.TotalAmount;
        uint256 expectedErc20Reward = (erc20Stake * erc20Pool.TotalFee) / erc20Pool.TotalAmount;

        uint256 ethBalanceBefore = cat.balance;
        uint256 erc20BalanceBefore = erc20Token.balanceOf(cat);

        vm.prank(cat);
        sourcePoolManager.WithdrawAll();

        uint256 ethBalanceAfter = cat.balance;
        uint256 erc20BalanceAfter = erc20Token.balanceOf(cat);

        uint256 actualEthReward = ethBalanceAfter - ethBalanceBefore - ethStake;
        uint256 actualErc20Reward = erc20BalanceAfter - erc20BalanceBefore - erc20Stake;

        assertEq(ethBalanceAfter - ethBalanceBefore, ethStake + expectedEthReward, "ETH withdrawal (principal + reward) is incorrect");
        assertEq(erc20BalanceAfter - erc20BalanceBefore, erc20Stake + expectedErc20Reward, "ERC20 withdrawal (principal + reward) is incorrect");

        assertEq(actualEthReward, expectedEthReward, "ETH reward calculation is incorrect");
        assertEq(actualErc20Reward, expectedErc20Reward, "ERC20 reward calculation is incorrect");

        assertEq(sourcePoolManager.getUserLength(cat), 0, "User's stake array should be empty after full withdrawal");

        uint256 expectedRemainingEthBalance = 5 ether - (5 ether * sourcePoolManager.PerFee()) / 1_000_000;
        assertEq(sourcePoolManager.FundingPoolBalance(ethTokenAddress), expectedRemainingEthBalance, "FundingPoolBalance for ETH should equal bridged amount minus fees");

        uint256 expectedRemainingErc20Balance = 5 ether - (5 ether * sourcePoolManager.PerFee()) / 1_000_000;
        assertEq(sourcePoolManager.FundingPoolBalance(address(erc20Token)), expectedRemainingErc20Balance, "FundingPoolBalance for ERC20 should equal bridged amount minus fees");
    }

    // Test claiming rewards for a specific stake by ID
    function test_ClaimByID() public {
        (, uint256 erc20Stake) = _setupStakingAndGenerateFees();

        PoolManager.Pool memory erc20Pool = sourcePoolManager.getPool(address(erc20Token), 1);

        uint256 expectedErc20Reward = (erc20Stake * erc20Pool.TotalFee) / erc20Pool.TotalAmount;

        uint256 erc20BalanceBefore = erc20Token.balanceOf(cat);

        vm.prank(cat);
        sourcePoolManager.ClaimAllReward();

        uint256 erc20BalanceAfter = erc20Token.balanceOf(cat);

        assertEq(erc20BalanceAfter - erc20BalanceBefore, expectedErc20Reward, "ERC20 reward is incorrect");

        assertEq(sourcePoolManager.getUserLength(cat), 2, "User's stake array should still have 2 entries after claiming rewards");

        uint256 expectedRemainingErc20Balance = erc20Stake + 5 ether - (5 ether * sourcePoolManager.PerFee()) / 1_000_000;
        assertEq(sourcePoolManager.FundingPoolBalance(address(erc20Token)), expectedRemainingErc20Balance, "FundingPoolBalance for ERC20 should include stake and bridged amount minus fees");

        assertEq(sourcePoolManager.FeePoolValue(address(erc20Token)), 0, "FeePoolValue for ERC20 should be 0");
    }

    // Test claiming all rewards across different tokens
    function test_ClaimAllReward() public {
        (uint256 ethStake, uint256 erc20Stake) = _setupStakingAndGenerateFees();

        address ethTokenAddress = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        PoolManager.Pool memory ethPool = sourcePoolManager.getPool(ethTokenAddress, 1);
        PoolManager.Pool memory erc20Pool = sourcePoolManager.getPool(address(erc20Token), 1);

        uint256 expectedEthReward = (ethStake * ethPool.TotalFee) / ethPool.TotalAmount;
        uint256 expectedErc20Reward = (erc20Stake * erc20Pool.TotalFee) / erc20Pool.TotalAmount;

        uint256 ethBalanceBefore = cat.balance;
        uint256 erc20BalanceBefore = erc20Token.balanceOf(cat);

        vm.prank(cat);
        sourcePoolManager.ClaimAllReward();

        uint256 ethBalanceAfter = cat.balance;
        uint256 erc20BalanceAfter = erc20Token.balanceOf(cat);

        assertEq(ethBalanceAfter - ethBalanceBefore, expectedEthReward, "ETH reward is incorrect");
        assertEq(erc20BalanceAfter - erc20BalanceBefore, expectedErc20Reward, "ERC20 reward is incorrect");

        assertEq(sourcePoolManager.getUserLength(cat), 2, "User's stake array should still have 2 entries after claiming rewards");

        uint256 expectedRemainingEthBalance = ethStake + 5 ether - (5 ether * sourcePoolManager.PerFee()) / 1_000_000;
        assertEq(sourcePoolManager.FundingPoolBalance(ethTokenAddress), expectedRemainingEthBalance, "FundingPoolBalance for ETH should include stake and bridged amount minus fees");

        uint256 expectedRemainingErc20Balance = erc20Stake + 5 ether - (5 ether * sourcePoolManager.PerFee()) / 1_000_000;
        assertEq(sourcePoolManager.FundingPoolBalance(address(erc20Token)), expectedRemainingErc20Balance, "FundingPoolBalance for ERC20 should include stake and bridged amount minus fees");
    }

    function _setupStakingAndGenerateFees() internal returns (uint256 ethStake, uint256 erc20Stake) {
        ethStake = 1 ether;
        vm.deal(cat, ethStake);
        erc20Stake = 100 ether;
        erc20Token.mint(cat, erc20Stake);

        address ethTokenAddress = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

        uint32 startTime = uint32(block.timestamp + 2400 hours);
        vm.startPrank(ReLayer);
        sourcePoolManager.setSupportToken(ethTokenAddress, true, startTime);
        sourcePoolManager.setSupportToken(address(erc20Token), true, startTime);
        vm.stopPrank();

        vm.warp(startTime - 1 hours);
        vm.startPrank(cat);
        sourcePoolManager.DepositAndStakingETH{value: ethStake}();
        erc20Token.approve(address(sourcePoolManager), erc20Stake);
        sourcePoolManager.DepositAndStakingERC20(address(erc20Token), erc20Stake);
        vm.stopPrank();

        for (uint i = 0; i < 5; i++) {
            _bridge_ETH(1, bridge_cat, bridge_seek);
            _bridge_ERC20(1, bridge_cat, bridge_seek);
        }

        PoolManager.Pool memory ethPoolToComplete = sourcePoolManager.getPool(ethTokenAddress, 1);
        vm.warp(ethPoolToComplete.endTimestamp + 1 hours);

        vm.startPrank(ReLayer);
        PoolManager.Pool[] memory poolsToComplete = new PoolManager.Pool[](2);
        poolsToComplete[0] = ethPoolToComplete;
        poolsToComplete[1] = sourcePoolManager.getPool(address(erc20Token), 1);
        sourcePoolManager.CompletePoolAndNew(poolsToComplete);
        vm.stopPrank();
    }
}
