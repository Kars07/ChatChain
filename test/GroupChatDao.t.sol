// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/GroupChatDao.sol";

contract GroupChatDaoTest is Test {
    GroupChatDao public groupChatDao;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public dave = address(0x4);
    address public eve = address(0x5);
    
    string public groupName = "Test Group";
    
    event GroupCreated(bytes32 indexed groupId, string groupName, address creator);
    event MemberAdded(bytes32 indexed groupId, address member);
    event MemberRemoved(bytes32 indexed groupId, address member);
    event ProposalCreated(bytes32 indexed proposalId, bytes32 indexed groupId, GroupChatDao.ProposalType proposalType);
    event VoteCast(bytes32 indexed proposalId, address voter, bool vote);
    event ProposalExecuted(bytes32 indexed proposalId, bool passed);
    
    function setUp() public {
        groupChatDao = new GroupChatDao();
    }
    
    function getDefaultSettings() internal pure returns (GroupChatDao.GroupSettings memory) {
        return GroupChatDao.GroupSettings({
            requireVoteToAddMember: true,
            requireVoteToRemoveMember: true,
            requireVoteToChangeSettings: true,
            votingDuration: 86400, // 1 day
            minimumVotesRequired: 2,
            votingThreshold: 60 // 60%
        });
    }
    
    function testCreateGroup() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](2);
        initialMembers[0] = bob;
        initialMembers[1] = charlie;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        
        // Create group first to get actual groupId
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);

        
        // Verify group info
        (
            string memory storedGroupName,
            address creator,
            address[] memory members,
            GroupChatDao.GroupSettings memory storedSettings,
            uint256 createdAt,
            bool isActive
        ) = groupChatDao.getGroupInfo(groupId);
        
        assertEq(storedGroupName, groupName);
        assertEq(creator, alice);
        assertEq(members.length, 3); // alice + 2 initial members
        assertEq(members[0], alice);
        assertEq(members[1], bob);
        assertEq(members[2], charlie);
        assertTrue(isActive);
        assertEq(createdAt, block.timestamp);
        
        // Verify settings
        assertEq(storedSettings.requireVoteToAddMember, settings.requireVoteToAddMember);
        assertEq(storedSettings.votingDuration, settings.votingDuration);
        assertEq(storedSettings.minimumVotesRequired, settings.minimumVotesRequired);
        assertEq(storedSettings.votingThreshold, settings.votingThreshold);
        
        // Verify user groups
        bytes32[] memory aliceGroups = groupChatDao.getUserGroups(alice);
        bytes32[] memory bobGroups = groupChatDao.getUserGroups(bob);
        bytes32[] memory charlieGroups = groupChatDao.getUserGroups(charlie);
        
        assertEq(aliceGroups.length, 1);
        assertEq(aliceGroups[0], groupId);
        assertEq(bobGroups.length, 1);
        assertEq(bobGroups[0], groupId);
        assertEq(charlieGroups.length, 1);
        assertEq(charlieGroups[0], groupId);
        
        vm.stopPrank();
    }
    
    function testCreateGroupWithDuplicateMembers() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](3);
        initialMembers[0] = bob;
        initialMembers[1] = alice; // Duplicate creator
        initialMembers[2] = charlie;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        // Verify alice is not added twice
        (, , address[] memory members, , , ) = groupChatDao.getGroupInfo(groupId);
        assertEq(members.length, 3); // alice, bob, charlie (alice not duplicated)
        
        vm.stopPrank();
    }
    
    function testAddMemberWithoutVoting() public {
        vm.startPrank(alice);
        
        // Create group with no voting required
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        settings.requireVoteToAddMember = false;
        
        address[] memory initialMembers = new address[](1);
        initialMembers[0] = bob;
        
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        // Add member directly
        vm.expectEmit(true, false, false, true);
        emit MemberAdded(groupId, charlie);
        
        groupChatDao.addMember(groupId, charlie);
        
        // Verify member added
        (, , address[] memory members, , , ) = groupChatDao.getGroupInfo(groupId);
        assertEq(members.length, 3);
        assertEq(members[2], charlie);
        
        // Verify user groups updated
        bytes32[] memory charlieGroups = groupChatDao.getUserGroups(charlie);
        assertEq(charlieGroups.length, 1);
        assertEq(charlieGroups[0], groupId);
        
        vm.stopPrank();
    }
    
    function testAddMemberWithVoting() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](2);
        initialMembers[0] = bob;
        initialMembers[1] = charlie;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        vm.stopPrank();
        
        // Non-admin member tries to add member (should create proposal)
        vm.startPrank(bob);
        
        // Expect proposal creation event
        bytes32 expectedProposalId = keccak256(
            abi.encodePacked(groupId, bob, GroupChatDao.ProposalType.ADD_MEMBER, block.timestamp)
        );
        
        vm.expectEmit(true, true, false, true);
        emit ProposalCreated(expectedProposalId, groupId, GroupChatDao.ProposalType.ADD_MEMBER);
        
        groupChatDao.addMember(groupId, dave);
        
        vm.stopPrank();
        
        // Verify member not added yet
        (, , address[] memory members, , , ) = groupChatDao.getGroupInfo(groupId);
        assertEq(members.length, 3); // Still original members
    }
    
    function testAddMemberAsAdmin() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](1);
        initialMembers[0] = bob;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        // Admin can add member even if voting required
        vm.expectEmit(true, false, false, true);
        emit MemberAdded(groupId, charlie);
        
        groupChatDao.addMember(groupId, charlie);
        
        // Verify member added
        (, , address[] memory members, , , ) = groupChatDao.getGroupInfo(groupId);
        assertEq(members.length, 3);
        assertEq(members[2], charlie);
        
        vm.stopPrank();
    }
    
    function testRemoveMemberAsAdmin() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](2);
        initialMembers[0] = bob;
        initialMembers[1] = charlie;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        settings.requireVoteToRemoveMember = false;
        
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        // Remove member
        vm.expectEmit(true, false, false, true);
        emit MemberRemoved(groupId, bob);
        
        groupChatDao.removeMember(groupId, bob);
        
        // Verify member removed
        (, , address[] memory members, , , ) = groupChatDao.getGroupInfo(groupId);
        assertEq(members.length, 2); // alice and charlie remain
        assertEq(members[0], alice);
        assertEq(members[1], charlie);
        
        // Verify user groups updated
        bytes32[] memory bobGroups = groupChatDao.getUserGroups(bob);
        assertEq(bobGroups.length, 0);
        
        vm.stopPrank();
    }
    
    function testCannotRemoveCreator() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](1);
        initialMembers[0] = bob;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        settings.requireVoteToRemoveMember = false;
        
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        // Try to remove creator (should revert)
        vm.expectRevert("Cannot remove group creator");
        groupChatDao.removeMember(groupId, alice);
        
        vm.stopPrank();
    }
    
    function testVotingProposal() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](2);
        initialMembers[0] = bob;
        initialMembers[1] = charlie;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        settings.minimumVotesRequired = 2;
        settings.votingThreshold = 60;
        
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        vm.stopPrank();
        
        // Bob creates proposal to add Dave
        vm.startPrank(bob);
        groupChatDao.addMember(groupId, dave);
        vm.stopPrank();
        
        // Calculate proposalId
        bytes32 proposalId = keccak256(
            abi.encodePacked(groupId, bob, GroupChatDao.ProposalType.ADD_MEMBER, block.timestamp)
        );
        
        // Alice votes for
        vm.startPrank(alice);
        groupChatDao.vote(proposalId, true);
        vm.stopPrank();
        
        // Charlie votes for - this should trigger execution
        vm.startPrank(charlie);
        groupChatDao.vote(proposalId, true);
        vm.stopPrank();
        
        // Verify Dave was added
        (, , address[] memory members, , , ) = groupChatDao.getGroupInfo(groupId);
        assertEq(members.length, 4);
        assertEq(members[3], dave);
    }
    
    function testVotingProposalFails() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](2);
        initialMembers[0] = bob;
        initialMembers[1] = charlie;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        settings.minimumVotesRequired = 2;
        settings.votingThreshold = 60;
        
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        vm.stopPrank();
        
        // Bob creates proposal to add Dave
        vm.startPrank(bob);
        groupChatDao.addMember(groupId, dave);
        vm.stopPrank();
        
        bytes32 proposalId = keccak256(
            abi.encodePacked(groupId, bob, GroupChatDao.ProposalType.ADD_MEMBER, block.timestamp)
        );
        
        // Alice votes against
        vm.startPrank(alice);
        groupChatDao.vote(proposalId, false);
        vm.stopPrank();
        
        // Charlie votes against - this will trigger execution and fail
        vm.startPrank(charlie);
        groupChatDao.vote(proposalId, false);
        vm.stopPrank();
        
        // Verify Dave was not added
        (, , address[] memory members, , , ) = groupChatDao.getGroupInfo(groupId);
        assertEq(members.length, 3); // Original members only
    }
    
    function testCannotVoteTwice() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](1);
        initialMembers[0] = bob;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        vm.stopPrank();
        
        // Bob creates proposal
        vm.startPrank(bob);
        groupChatDao.addMember(groupId, charlie);
        vm.stopPrank();
        
        bytes32 proposalId = keccak256(
            abi.encodePacked(groupId, bob, GroupChatDao.ProposalType.ADD_MEMBER, block.timestamp)
        );
        
        // Alice votes
        vm.startPrank(alice);
        groupChatDao.vote(proposalId, true);
        
        // Try to vote again (should revert)
        vm.expectRevert("Already voted");
        groupChatDao.vote(proposalId, false);
        
        vm.stopPrank();
    }
    
    function testCannotVoteAfterDeadline() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](1);
        initialMembers[0] = bob;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        vm.stopPrank();
        
        // Bob creates proposal
        vm.startPrank(bob);
        groupChatDao.addMember(groupId, charlie);
        vm.stopPrank();
        
        bytes32 proposalId = keccak256(
            abi.encodePacked(groupId, bob, GroupChatDao.ProposalType.ADD_MEMBER, block.timestamp)
        );
        
        // Fast forward past deadline
        vm.warp(block.timestamp + settings.votingDuration + 1);
        
        // Try to vote after deadline
        vm.startPrank(alice);
        vm.expectRevert("Voting period ended");
        groupChatDao.vote(proposalId, true);
        vm.stopPrank();
    }
    
    function testCannotAddExistingMember() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](1);
        initialMembers[0] = bob;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        // Try to add existing member
        vm.expectRevert("Already a member");
        groupChatDao.addMember(groupId, bob);
        
        vm.stopPrank();
    }
    
    function testCannotRemoveNonMember() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](1);
        initialMembers[0] = bob;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        settings.requireVoteToRemoveMember = false;
        
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        // Try to remove non-member
        vm.expectRevert("Not a Member");
        groupChatDao.removeMember(groupId, charlie);
        
        vm.stopPrank();
    }
    
    function testNonMemberCannotAddMember() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](1);
        initialMembers[0] = bob;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        vm.stopPrank();
        
        // Non-member tries to add member
        vm.startPrank(charlie);
        vm.expectRevert("Not a group Member");
        groupChatDao.addMember(groupId, dave);
        vm.stopPrank();
    }
    
    // Test when voting is not required but caller is not admin - should fail with "Unauthorized to remove member"
    function testNonAdminCannotRemoveMember() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](2);
        initialMembers[0] = bob;
        initialMembers[1] = charlie;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        // Set voting NOT required - this forces the logic to the else branch
        settings.requireVoteToRemoveMember = false;
        
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        vm.stopPrank();
        
        // Non-admin tries to remove member when voting not required
        vm.startPrank(bob);
        vm.expectRevert("Unauthorized to remove member");
        groupChatDao.removeMember(groupId, charlie);
        vm.stopPrank();
    }
    
    // Test when non-admin creates removal proposal (voting required)
    function testNonAdminCreatesRemoveProposal() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](2);
        initialMembers[0] = bob;
        initialMembers[1] = charlie;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        // Voting is required for removal
        settings.requireVoteToRemoveMember = true;
        
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        vm.stopPrank();
        
        // Non-admin member creates proposal to remove another member
        vm.startPrank(bob);
        
        // This should create a proposal, not revert
        bytes32 expectedProposalId = keccak256(
            abi.encodePacked(groupId, bob, GroupChatDao.ProposalType.REMOVE_MEMBER, block.timestamp)
        );
        
        vm.expectEmit(true, true, false, true);
        emit ProposalCreated(expectedProposalId, groupId, GroupChatDao.ProposalType.REMOVE_MEMBER);
        
        groupChatDao.removeMember(groupId, charlie);
        
        // Verify charlie is still a member (only proposal created)
        (, , address[] memory members, , , ) = groupChatDao.getGroupInfo(groupId);
        assertEq(members.length, 3); // Still all members
        
        vm.stopPrank();
    }

    // Test admin can remove directly regardless of voting settings
    function testAdminCanRemoveDirectly() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](2);
        initialMembers[0] = bob;
        initialMembers[1] = charlie;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        settings.requireVoteToRemoveMember = true; // Even with voting required
        
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        // Admin removes member directly
        vm.expectEmit(true, false, false, true);
        emit MemberRemoved(groupId, bob);
        
        groupChatDao.removeMember(groupId, bob);
        
        // Verify bob was removed immediately
        (, , address[] memory members, , , ) = groupChatDao.getGroupInfo(groupId);
        assertEq(members.length, 2); // alice and charlie remain
        
        vm.stopPrank();
    }
    
    function testCannotVoteOnExecutedProposal() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](2);
        initialMembers[0] = bob;
        initialMembers[1] = charlie;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        settings.minimumVotesRequired = 2;
        settings.votingThreshold = 60;
        
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        vm.stopPrank();
        
        // Bob creates proposal
        vm.startPrank(bob);
        groupChatDao.addMember(groupId, dave);
        vm.stopPrank();
        
        bytes32 proposalId = keccak256(
            abi.encodePacked(groupId, bob, GroupChatDao.ProposalType.ADD_MEMBER, block.timestamp)
        );
        
        // Execute proposal with enough votes
        vm.startPrank(alice);
        groupChatDao.vote(proposalId, true);
        vm.stopPrank();
        
        vm.startPrank(charlie);
        groupChatDao.vote(proposalId, true);
        vm.stopPrank();
        
        // Try to vote again after execution
        vm.startPrank(dave);
        vm.expectRevert("Proposal already executed");
        groupChatDao.vote(proposalId, true);
        vm.stopPrank();
    }
    
    function testRemoveMemberProposal() public {
        vm.startPrank(alice);
        
        address[] memory initialMembers = new address[](2);
        initialMembers[0] = bob;
        initialMembers[1] = charlie;
        
        GroupChatDao.GroupSettings memory settings = getDefaultSettings();
        settings.minimumVotesRequired = 2;
        settings.votingThreshold = 60;
        
        bytes32 groupId = groupChatDao.createGroup(groupName, initialMembers, settings);
        
        vm.stopPrank();
        
        // Non-admin member (Bob) creates proposal to remove Charlie
        vm.startPrank(bob);
        
        // Expected proposal ID calculation
        bytes32 expectedProposalId = keccak256(
            abi.encodePacked(groupId, bob, GroupChatDao.ProposalType.REMOVE_MEMBER, block.timestamp)
        );
        
        // Expect proposal creation event
        vm.expectEmit(true, true, false, true);
        emit ProposalCreated(expectedProposalId, groupId, GroupChatDao.ProposalType.REMOVE_MEMBER);
        
        groupChatDao.removeMember(groupId, charlie);
        
        vm.stopPrank();
        
        // Verify charlie is still a member (proposal created, not executed yet)
        (, , address[] memory members, , , ) = groupChatDao.getGroupInfo(groupId);
        assertEq(members.length, 3); // alice, bob, charlie still there
        
        // Now vote on the proposal
        bytes32 proposalId = keccak256(
            abi.encodePacked(groupId, bob, GroupChatDao.ProposalType.REMOVE_MEMBER, block.timestamp)
        );
        
        // Alice votes to remove charlie
        vm.startPrank(alice);
        groupChatDao.vote(proposalId, true);
        vm.stopPrank();
        
        // Bob votes to remove charlie (he proposed it)
        vm.startPrank(bob);
        groupChatDao.vote(proposalId, true);
        vm.stopPrank();
        
        // Verify charlie was removed after successful voting (2 votes for, 0 against = 100% > 60%)
        (, , address[] memory finalMembers, , , ) = groupChatDao.getGroupInfo(groupId);
        assertEq(finalMembers.length, 2); // alice and bob remain
        
        // Verify charlie's user groups updated
        bytes32[] memory charlieGroups = groupChatDao.getUserGroups(charlie);
        assertEq(charlieGroups.length, 0);
    }
}