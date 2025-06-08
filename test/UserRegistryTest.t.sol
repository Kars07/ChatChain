// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/UserRegistry.sol";

contract UserRegistryTest is Test {
    UserRegistry public userRegistry;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    string public aliceUsername = "alice123";
    string public bobUsername = "bob456";
    string public alicePublicKey = "alice_public_key_xyz";
    string public bobPublicKey = "bob_public_key_abc";
    
    event UserRegistered(
        address indexed wallet,
        string username
    );
    
    function setUp() public {
        userRegistry = new UserRegistry();
    }
    
    function testRegisterUser() public {
        vm.startPrank(alice);
        
        // Expect event emission
        vm.expectEmit(true, false, false, true);
        emit UserRegistered(alice, aliceUsername);
        
        // Register user
        userRegistry.registerUser(aliceUsername, alicePublicKey);
        
        // Verify user data
        (
            address wallet,
            string memory publickey,
            string memory username,
            bool isOnline,
            uint256 lastSeen
        ) = userRegistry.users(alice);
        
        assertEq(wallet, alice);
        assertEq(publickey, alicePublicKey);
        assertEq(username, aliceUsername);
        assertTrue(isOnline);
        assertEq(lastSeen, block.timestamp);
        
        // Verify username mapping
        assertEq(userRegistry.usernameToWallet(aliceUsername), alice);
        
        vm.stopPrank();
    }
    
    function testRegisterMultipleUsers() public {
        // Register Alice
        vm.startPrank(alice);
        userRegistry.registerUser(aliceUsername, alicePublicKey);
        vm.stopPrank();
        
        // Register Bob
        vm.startPrank(bob);
        userRegistry.registerUser(bobUsername, bobPublicKey);
        vm.stopPrank();
        
        // Verify both users exist
        (address aliceWallet, , string memory aliceStoredUsername, , ) = userRegistry.users(alice);
        (address bobWallet, , string memory bobStoredUsername, , ) = userRegistry.users(bob);
        
        assertEq(aliceWallet, alice);
        assertEq(aliceStoredUsername, aliceUsername);
        assertEq(bobWallet, bob);
        assertEq(bobStoredUsername, bobUsername);
        
        // Verify username mappings
        assertEq(userRegistry.usernameToWallet(aliceUsername), alice);
        assertEq(userRegistry.usernameToWallet(bobUsername), bob);
    }
    
    function testUpdateOnlineStatus() public {
        // First register user
        vm.startPrank(alice);
        userRegistry.registerUser(aliceUsername, alicePublicKey);
        
        // User should be online initially
        (, , , bool isOnline, uint256 lastSeen) = userRegistry.users(alice);
        assertTrue(isOnline);
        assertEq(lastSeen, block.timestamp);
        
        // Move time forward
        vm.warp(block.timestamp + 100);
        
        // Update to offline
        userRegistry.updateOnlineStatus(false);
        
        // Verify status updated
        (, , , bool newIsOnline, uint256 newLastSeen) = userRegistry.users(alice);
        assertFalse(newIsOnline);
        assertEq(newLastSeen, block.timestamp);
        
        // Move time forward again
        vm.warp(block.timestamp + 200);
        
        // Update back to online
        userRegistry.updateOnlineStatus(true);
        
        // Verify status updated again
        (, , , bool finalIsOnline, uint256 finalLastSeen) = userRegistry.users(alice);
        assertTrue(finalIsOnline);
        assertEq(finalLastSeen, block.timestamp);
        
        vm.stopPrank();
    }
    
    function testUpdateOnlineStatusWithoutRegistration() public {
        vm.startPrank(alice);
        
        // Try to update status without registering first
        userRegistry.updateOnlineStatus(true);
        
        // Should create empty user entry with updated status
        (, , , bool isOnline, uint256 lastSeen) = userRegistry.users(alice);
        assertTrue(isOnline);
        assertEq(lastSeen, block.timestamp);
        
        vm.stopPrank();
    }
    
    function testOverwriteUserRegistration() public {
        vm.startPrank(alice);
        
        // Register user first time
        userRegistry.registerUser(aliceUsername, alicePublicKey);
        
        // Verify initial registration
        (, string memory initialPublicKey, string memory initialUsername, , ) = userRegistry.users(alice);
        assertEq(initialPublicKey, alicePublicKey);
        assertEq(initialUsername, aliceUsername);
        
        // Move time forward
        vm.warp(block.timestamp + 100);
        
        // Register again with different data
        string memory newUsername = "alice_new";
        string memory newPublicKey = "new_public_key";
        
        userRegistry.registerUser(newUsername, newPublicKey);
        
        // Verify data was overwritten
        (, string memory newStoredPublicKey, string memory newStoredUsername, bool isOnline, uint256 lastSeen) = userRegistry.users(alice);
        assertEq(newStoredPublicKey, newPublicKey);
        assertEq(newStoredUsername, newUsername);
        assertTrue(isOnline);
        assertEq(lastSeen, block.timestamp);
        
        // Verify new username mapping
        assertEq(userRegistry.usernameToWallet(newUsername), alice);
        
        // Old username mapping should still point to alice (this is a potential issue in the contract)
        assertEq(userRegistry.usernameToWallet(aliceUsername), alice);
        
        vm.stopPrank();
    }
    
    function testUsernameCollision() public {
        // Register Alice with a username
        vm.startPrank(alice);
        userRegistry.registerUser(aliceUsername, alicePublicKey);
        vm.stopPrank();
        
        // Try to register Bob with same username
        vm.startPrank(bob);
        userRegistry.registerUser(aliceUsername, bobPublicKey);
        vm.stopPrank();
        
        // Verify that Bob overwrote the username mapping
        assertEq(userRegistry.usernameToWallet(aliceUsername), bob);
        
        // But Alice's user data should still exist
        (, , string memory aliceStoredUsername, , ) = userRegistry.users(alice);
        assertEq(aliceStoredUsername, aliceUsername);
        
        // And Bob's user data should exist too
        (, , string memory bobStoredUsername, , ) = userRegistry.users(bob);
        assertEq(bobStoredUsername, aliceUsername);
    }
    
    function testEmptyUsernameAndPublicKey() public {
        vm.startPrank(alice);
        
        // Register with empty strings
        userRegistry.registerUser("", "");
        
        // Should still work
        (, string memory publickey, string memory username, bool isOnline, ) = userRegistry.users(alice);
        assertEq(publickey, "");
        assertEq(username, "");
        assertTrue(isOnline);
        
        vm.stopPrank();
    }
    
    function testFuzzRegisterUser(string memory username, string memory publicKey) public {
        vm.startPrank(alice);
        
        userRegistry.registerUser(username, publicKey);
        
        // Verify registration
        (
            address wallet,
            string memory storedPublicKey,
            string memory storedUsername,
            bool isOnline,
            uint256 lastSeen
        ) = userRegistry.users(alice);
        
        assertEq(wallet, alice);
        assertEq(storedPublicKey, publicKey);
        assertEq(storedUsername, username);
        assertTrue(isOnline);
        assertEq(lastSeen, block.timestamp);
        
        // Verify username mapping
        assertEq(userRegistry.usernameToWallet(username), alice);
        
        vm.stopPrank();
    }
}