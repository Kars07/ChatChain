// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/MessageVerification.sol";

contract MessageVerificationTest is Test {
    MessageVerification public messageVerification;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    string public testMessage = "Hello, this is a test message";
    bytes32 public testMessageHash;
    
    event MessageHashStored(
        bytes32 proofId,
        bytes32 messageHash,
        address indexed sender,
        address indexed recipient,
        uint256 timestamp
    );
    
    function setUp() public {
        messageVerification = new MessageVerification();
        testMessageHash = keccak256(abi.encodePacked(testMessage));
    }
    
    function testStoreMessageHash() public {
        vm.startPrank(alice);
        
        // Calculate expected proofId
        bytes32 expectedProofId = keccak256(
            abi.encodePacked(alice, bob, block.timestamp)
        );
        
        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit MessageHashStored(
            expectedProofId,
            testMessageHash,
            alice,
            bob,
            block.timestamp
        );
        
        // Store message hash
        messageVerification.storeMessageHash(testMessageHash, bob);
        
        // Verify storage
        (
            bytes32 hash,
            address sender,
            address recipient,
            uint256 timestamp,
            bool exists
        ) = messageVerification.messageProofs(expectedProofId);
        
        assertEq(hash, testMessageHash);
        assertEq(sender, alice);
        assertEq(recipient, bob);
        assertEq(timestamp, block.timestamp);
        assertTrue(exists);
        
        // Verify user message count
        assertEq(messageVerification.userMessageCount(alice), 1);
        
        vm.stopPrank();
    }
    
    function testStoreMultipleMessageHashes() public {
        vm.startPrank(alice);
        
        // Store first message
        messageVerification.storeMessageHash(testMessageHash, bob);
        
        // Move time forward to ensure different proofId
        vm.warp(block.timestamp + 1);
        
        // Store second message
        bytes32 secondMessageHash = keccak256(abi.encodePacked("Second message"));
        messageVerification.storeMessageHash(secondMessageHash, charlie);
        
        // Verify user message count increased
        assertEq(messageVerification.userMessageCount(alice), 2);
        
        vm.stopPrank();
    }
    
    function testVerifyMessageIntegrity() public {
        vm.startPrank(alice);
        
        // Store message hash
        messageVerification.storeMessageHash(testMessageHash, bob);
        bytes32 proofId = keccak256(
            abi.encodePacked(alice, bob, block.timestamp)
        );
        
        vm.stopPrank();
        
        // Verify with correct content
        assertTrue(
            messageVerification.verifyMessageIntegrity(proofId, testMessage)
        );
        
        // Verify with incorrect content
        assertFalse(
            messageVerification.verifyMessageIntegrity(proofId, "Wrong message")
        );
    }
    
    function testVerifyMessageIntegrityWithNonExistentProof() public {
        bytes32 nonExistentProofId = keccak256("non-existent");
        
        // Should return false for non-existent proof
        assertFalse(
            messageVerification.verifyMessageIntegrity(nonExistentProofId, testMessage)
        );
    }
    
    function testDifferentSendersGenerateDifferentProofIds() public {
        bytes32 aliceProofId;
        bytes32 bobProofId;
        
        // Alice stores message
        vm.startPrank(alice);
        messageVerification.storeMessageHash(testMessageHash, charlie);
        aliceProofId = keccak256(
            abi.encodePacked(alice, charlie, block.timestamp)
        );
        vm.stopPrank();
        
        // Bob stores same message at same timestamp
        vm.startPrank(bob);
        messageVerification.storeMessageHash(testMessageHash, charlie);
        bobProofId = keccak256(
            abi.encodePacked(bob, charlie, block.timestamp)
        );
        vm.stopPrank();
        
        // ProofIds should be different
        assertTrue(aliceProofId != bobProofId);
        
        // Both should exist
        (, , , , bool aliceExists) = messageVerification.messageProofs(aliceProofId);
        (, , , , bool bobExists) = messageVerification.messageProofs(bobProofId);
        
        assertTrue(aliceExists);
        assertTrue(bobExists);
    }
    
    function testMessageCountIncrements() public {
        vm.startPrank(alice);
        
        // Initial count should be 0
        assertEq(messageVerification.userMessageCount(alice), 0);
        
        // Store multiple messages
        for (uint i = 0; i < 5; i++) {
            vm.warp(block.timestamp + i + 1);
            bytes32 hash = keccak256(abi.encodePacked("Message", i));
            messageVerification.storeMessageHash(hash, bob);
        }
        
        // Count should be 5
        assertEq(messageVerification.userMessageCount(alice), 5);
        
        vm.stopPrank();
    }
    
    function testFuzzStoreAndVerify(string memory content, address recipient) public {
        vm.assume(recipient != address(0));
        vm.assume(bytes(content).length > 0);
        
        vm.startPrank(alice);
        
        bytes32 messageHash = keccak256(abi.encodePacked(content));
        messageVerification.storeMessageHash(messageHash, recipient);
        
        bytes32 proofId = keccak256(
            abi.encodePacked(alice, recipient, block.timestamp)
        );
        
        // Should verify with correct content
        assertTrue(
            messageVerification.verifyMessageIntegrity(proofId, content)
        );
        
        // Should fail with different content
        assertFalse(
            messageVerification.verifyMessageIntegrity(proofId, string.concat(content, "extra"))
        );
        
        vm.stopPrank();
    }
}