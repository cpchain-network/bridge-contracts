// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import {Script, console} from "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { EmptyContract } from "./utils/EmptyContract.sol";
import { MessageManager } from "../src/core/MessageManager.sol";
import { PoolManager } from "../src/core/PoolManager.sol";

contract DeployerCpChainBridge is Script {
    EmptyContract public emptyContract;
    ProxyAdmin public messageManagerProxyAdmin;
    ProxyAdmin public  poolManagerProxyAdmin;
    MessageManager public messageManager;
    MessageManager public messageManagerImplementation;

    PoolManager public poolManager;
    PoolManager public poolManagerImplementation;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address relayerAddress =  vm.envAddress("RELAYER_ADDRESS");
        address cpChainMultiSign =  vm.envAddress("MULTI_SIGNER");

        address deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        emptyContract = new EmptyContract();

        TransparentUpgradeableProxy proxyMessageManager = new TransparentUpgradeableProxy(address(emptyContract), cpChainMultiSign, "");
        messageManager = MessageManager(address(proxyMessageManager));
        messageManagerImplementation = new MessageManager();
        messageManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyMessageManager)));

        TransparentUpgradeableProxy proxyPoolManager = new TransparentUpgradeableProxy(address(emptyContract), cpChainMultiSign, "");
        poolManager = PoolManager(payable(address(proxyPoolManager)));
        poolManagerImplementation = new PoolManager();
        poolManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyPoolManager)));

        messageManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(messageManager)),
            address(messageManagerImplementation),
            abi.encodeWithSelector(
                MessageManager.initialize.selector,
                deployerAddress,
                poolManager
            )
        );

        poolManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(poolManager)),
            address(poolManagerImplementation),
            abi.encodeWithSelector(
                PoolManager.initialize.selector,
                deployerAddress,
                messageManager,
                relayerAddress,
                deployerAddress
            )
        );

        console.log("deploy proxyMessageManager:", address(proxyMessageManager));
        console.log("deploy proxyPoolManager:", address(proxyPoolManager));
        // string memory path = "deployed_addresses.json";
        // string memory data = string(abi.encodePacked(
        //     '{"proxyMessageManager": "', vm.toString(address(proxyMessageManager)), '", ',
        //     '"proxyPoolManager": "', vm.toString(address(proxyPoolManager)), '"}'
        // ));
        // vm.writeJson(data, path);
        // vm.stopBroadcast();
    }

    function getProxyAdminAddress(address proxy) internal view returns (address) {
        address CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 adminSlot = vm.load(proxy, ERC1967Utils.ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }
}
