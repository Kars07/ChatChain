// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// src/UserRegistry.sol

contract UserRegistry {
    struct User {
        address wallet;
        string publickey;
        string username;
        bool isOnline;
        uint256 lastSeen;
    }

    mapping(address => User) public users;
    mapping(string => address) public usernameToWallet;

    event UserRegistered(
        address indexed wallet,
        string username
    );
    
    function registerUser(
        string memory _username,
        string memory _publickey
    ) external {
        users[msg.sender] = User({
            wallet: msg.sender,
            publickey: _publickey,
            username: _username,
            isOnline: true,
            lastSeen: block.timestamp
        });

        usernameToWallet[_username] = msg.sender;
        emit UserRegistered(msg.sender, _username);
    }

    function updateOnlineStatus(bool _isOnline) external {
        users[msg.sender].isOnline = _isOnline;
        users[msg.sender].lastSeen = block.timestamp;
    }
}
