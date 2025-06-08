// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

contract MessageVerification {
    //store only message hashes for verificiation
    mapping(bytes32 => MessageProof) public messageProofs;
    mapping(address => uint256) public userMessageCount;

    struct MessageProof {
        bytes32 hash;
        address sender;
        address recipient;
        uint256 timestamp;
        bool exists;
    }

    event MessageHashStored(
        bytes32 proofId,
        bytes32 messageHash,
        address indexed sender,
        address indexed recipient,
        uint256 timestamp
    );

    function storeMessageHash (
        bytes32 _messageHash,
        address _recipient
    ) external {
        bytes32 proofId = keccak256(
            abi.encodePacked(msg.sender, _recipient, block.timestamp)
        );

        messageProofs[proofId] = MessageProof({
            hash: _messageHash,
            sender: msg.sender,
            recipient: _recipient,
            timestamp: block.timestamp,
            exists: true
        });

        userMessageCount[msg.sender]++;

        emit MessageHashStored(
            proofId,
            _messageHash,
            msg.sender,
            _recipient,
            block.timestamp
        );
    }

    //verify message integrity 
    function verifyMessageIntegrity(
        bytes32 _proofId,
        string memory _originalContent
    ) external view returns (bool) {
        MessageProof memory proof = messageProofs[_proofId];
        bytes32 computedHash = keccak256(abi.encodePacked(_originalContent));
        return proof.exists && (computedHash == proof.hash);
    }
}