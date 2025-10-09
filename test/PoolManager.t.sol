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

    function _bridge_ETH(uint256 amount, address from ,address to) internal {
        uint256 bridgeAmount = amount * 1 ether;
        vm.deal(from, bridgeAmount);

        address ethTokenAddress = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        uint256 balanceBefore = sourcePoolManager.FundingPoolBalance(ethTokenAddress);
        uint256 nextMessageNumberBefore = sourceMessageManager.nextMessageNumber();

        vm.chainId(SOURCE_CHAIN_ID);
        vm.prank(from);
        sourcePoolManager.BridgeInitiateETH{value: bridgeAmount}(SOURCE_CHAIN_ID, DEST_CHAIN_ID, ethTokenAddress, to);

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
        sourcePoolManager.BridgeInitiateERC20(SOURCE_CHAIN_ID, DEST_CHAIN_ID, to, address(erc20Token), address(erc20Token), bridgeAmount);
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
}
