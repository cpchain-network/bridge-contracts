// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import {Script, console} from "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/StorageSlot.sol";

import { MessageManager } from "../src/core/MessageManager.sol";
import { PoolManager } from "../src/core/PoolManager.sol";

contract UpgraderCpChainBridge is Script {
    // 已部署的代理合约地址
    address public constant POOL_MANAGER_PROXY = 0x1FB71BA7D57fC4709408a351E554CaC082643B0e;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console.log("Deployer address:", deployerAddress);
        console.log("Pool Manager Proxy:", POOL_MANAGER_PROXY);
        

        address proxyAdminAddress = getProxyAdminAddress(POOL_MANAGER_PROXY);
        console.log("Calculated Pool Manager Proxy Admin:", proxyAdminAddress);
        
        ProxyAdmin poolManagerProxyAdmin = ProxyAdmin(proxyAdminAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 部署新的实现合约
        PoolManager newPoolManagerImplementation = new PoolManager();
        
        console.log("New PoolManager implementation:", address(newPoolManagerImplementation));
        
        // 升级PoolManager实现
        poolManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(POOL_MANAGER_PROXY),
            address(newPoolManagerImplementation),
            ""
        );
        
        console.log("Upgrade completed successfully!");
        vm.stopBroadcast();
    }

    function getProxyAdminAddress(address proxy) internal view returns (address) {
        address CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        bytes32 adminSlot = vm.load(proxy, ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }
}