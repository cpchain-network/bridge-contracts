// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/IMessageManager.sol";

abstract contract MessageManagerStorage is IMessageManager{
    uint256 public nextMessageNumber;
    address public poolManagerAddress;
    mapping(bytes32 => bool) public sentMessageStatus;
    mapping(bytes32 => bool) public cliamMessageStatus;
}
