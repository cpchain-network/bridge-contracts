// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IMessageManager {
    event MessageSent(
        uint256 sourceChainId,
        uint256 destChainId,
        address sourceTokenAddress,
        address destTokenAddress,
        address indexed _from,
        address indexed _to,
        uint256 _fee,
        uint256 _value,
        uint256 _nonce,
        bytes32 indexed _messageHash
    );

    event MessageClaimed(
        uint256 sourceChainId,
        uint256 destChainId,
        address sourceTokenAddress,
        address destTokenAddress,
        bytes32 indexed _messageHash,
        uint256 _nonce
    );

    error ZeroAddressNotAllowed();
    error MessageAlreadySent(bytes32 messageHash);

    function sendMessage(uint256 sourceChainId, uint256 destChainId, address sourceTokenAddress, address destTokenAddress, address _from, address _to, uint256 _value, uint256 _fee) external;
    function claimMessage(uint256 sourceChainId, uint256 destChainId, address sourceTokenAddress, address destTokenAddress, address _from, address _to,  uint256 _value, uint256 _fee, uint256 _nonce) external;
}
