// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {UserRegistry} from "../src/UserRegistry.sol";
import {MessageVerification} from "../src/MessageVerification.sol";
import {GroupChatDao} from "../src/GroupChatDao.sol";

contract ChatChainScript is Script {
    MessageVerification public messageVerification;
    UserRegistry public userRegistry;
    GroupChatDao public groupChatDao;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        
        messageVerification = new MessageVerification();
        userRegistry = new UserRegistry();
        groupChatDao = new GroupChatDao();

        vm.stopBroadcast();
    }
}