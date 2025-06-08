// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// src/GroupChatDao.sol

contract GroupChatDao {
    struct GroupChat {
        bytes32 groupId;
        string groupName;
        address creator;
        address[] members;
        mapping(address => bool) isMember;
        mapping(address => bool) isAdmin;
        GroupSettings settings;
        uint256 createdAt;
        bool isActive;
    }

    struct GroupSettings {
        bool requireVoteToAddMember;
        bool requireVoteToRemoveMember;
        bool requireVoteToChangeSettings;
        uint256 votingDuration; //in seconds
        uint256 minimumVotesRequired;
        uint256 votingThreshold; // in percentage
    }

    struct Proposal {
        bytes32 proposalId;
        bytes32 groupId;
        address proposer;
        ProposalType proposalType;
        address targetMember; // for add/remove member proposals
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        mapping(address => bool) hasVoted;
        mapping(address => bool) vote; //true - for, false - against
        uint256 createdAt;
        uint256 deadline;
        bool executed;
        bool passed;
    }

    enum ProposalType {
        ADD_MEMBER,
        REMOVE_MEMBER,
        CHANGE_ADMIN,
        UPDATE_SETTINGS,
        CHANGE_GROUP_NAME
    }

    mapping(bytes32 => GroupChat) public groups;
    mapping(bytes32 => Proposal) public proposals;
    mapping(address => bytes32[]) public userGroups;

    event GroupCreated(bytes32 indexed groupId, string groupName, address creator);
    event MemberAdded(bytes32 indexed groupId, address member);
    event MemberRemoved(bytes32 indexed groupId, address member);
    event ProposalCreated(bytes32 indexed proposalId, bytes32 indexed groupId, ProposalType proposalType);
    event VoteCast(bytes32 indexed proposalId, address voter, bool vote);
    event ProposalExecuted(bytes32 indexed proposalId, bool passed);

    modifier onlyGroupMember(bytes32 _groupId) {
        require(groups[_groupId].isMember[msg.sender], "Not a group Member");
        _;
    }
    
    modifier onlyGroupAdmin(bytes32 _groupId) {
        require(groups[_groupId].isAdmin[msg.sender], "Not a group admin");
        _;
    }

    //create new group chat
    function createGroup(
        string memory _groupName,
        address[] memory _initialMembers,
        GroupSettings memory _settings
    ) external returns (bytes32) {
        bytes32 groupId = keccak256(
            abi.encodePacked(msg.sender, _groupName, block.timestamp)
        );

        GroupChat storage newGroup = groups[groupId];
        newGroup.groupId = groupId;
        newGroup.groupName = _groupName;
        newGroup.creator = msg.sender;
        newGroup.settings = _settings;
        newGroup.createdAt = block.timestamp;
        newGroup.isActive = true;

        //Add creator as First Admin
        newGroup.members.push(msg.sender);
        newGroup.isMember[msg.sender] = true;
        newGroup.isAdmin[msg.sender] = true;
        userGroups[msg.sender].push(groupId);

        //Add inital Members 
        for (uint i = 0; i < _initialMembers.length; i++) {
            if(_initialMembers[i] != msg.sender) {
                newGroup.members.push(_initialMembers[i]);
                newGroup.isMember[_initialMembers[i]] = true;
                userGroups[_initialMembers[i]].push(groupId);
                emit MemberAdded(groupId, _initialMembers[i]);
            }
        }

        emit GroupCreated(groupId, _groupName, msg.sender);
        return groupId;

    }

    //Add member directly(if Voting not required) or create proposal
    function addMember(bytes32 _groupId, address _newMember) external onlyGroupMember(_groupId) {
        GroupChat storage group = groups[_groupId];
        require(!group.isMember[_newMember], "Already a member");

        if (group.settings.requireVoteToAddMember && !group.isAdmin[msg.sender]) {
            //create proposal for voting
            _createProposal(_groupId, ProposalType.ADD_MEMBER, _newMember, "Add new member");
        } else {
            //Add directly (admin privilege or no voting required)
            group.members.push(_newMember);
            group.isMember[_newMember] = true;
            userGroups[_newMember].push(_groupId);
            emit MemberAdded(_groupId, _newMember);
        }
    }

    //Remove member with voting mechanism
    function removeMember(bytes32 _groupId, address _member) external onlyGroupMember(_groupId) {
        GroupChat storage group = groups[_groupId];
        require(group.isMember[_member], "Not a Member");
        require(_member != group.creator, "Cannot remove group creator");

        if (group.settings.requireVoteToRemoveMember && !group.isAdmin[msg.sender]) {
            // Non-admin members must create proposal
            _createProposal(_groupId, ProposalType.REMOVE_MEMBER, _member, "Remove member");
        } else if (group.isAdmin[msg.sender]) {
            // Admins can remove directly
            _removeMemberDirectly(_groupId, _member);
        } else {
            // This case shouldn't happen with proper settings
            revert("Unauthorized to remove member");
        }
    }

    //Create Proposal for group decisions
    function _createProposal(
        bytes32 _groupId,
        ProposalType _type,
        address _targetMember,
        string memory _description
    ) internal {
        bytes32 proposalId = keccak256(
            abi.encodePacked(_groupId, msg.sender, _type, block.timestamp)
        );
        
        GroupChat storage group = groups[_groupId];
        
        Proposal storage newProposal = proposals[proposalId];
        newProposal.proposalId = proposalId;
        newProposal.groupId = _groupId;
        newProposal.proposer = msg.sender;
        newProposal.proposalType = _type;
        newProposal.targetMember = _targetMember;
        newProposal.description = _description;
        newProposal.createdAt = block.timestamp;
        newProposal.deadline = block.timestamp + group.settings.votingDuration;
        
        emit ProposalCreated(proposalId, _groupId, _type);
    }

    // Vote on proposal
    function vote(bytes32 _proposalId, bool _vote) external {
        Proposal storage proposal = proposals[_proposalId];
        require(groups[proposal.groupId].isMember[msg.sender], "Not a group member");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        require(block.timestamp <= proposal.deadline, "Voting period ended");
        require(!proposal.executed, "Proposal already executed");
        
        proposal.hasVoted[msg.sender] = true;
        proposal.vote[msg.sender] = _vote;
        
        if (_vote) {
            proposal.votesFor++;
        } else {
            proposal.votesAgainst++;
        }
        
        emit VoteCast(_proposalId, msg.sender, _vote);
        
        // Auto-execute if enough votes
        _checkAndExecuteProposal(_proposalId);
    }

    // Execute proposal if voting passed
    function _checkAndExecuteProposal(bytes32 _proposalId) internal {
        Proposal storage proposal = proposals[_proposalId];
        GroupChat storage group = groups[proposal.groupId];
        
        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        uint256 memberCount = group.members.length;
        
        // Check if minimum votes reached and threshold met
        if (totalVotes >= group.settings.minimumVotesRequired &&
            (proposal.votesFor * 100 / totalVotes) >= group.settings.votingThreshold) {
            
            proposal.passed = true;
            proposal.executed = true;
            
            // Execute based on proposal type
            if (proposal.proposalType == ProposalType.ADD_MEMBER) {
                group.members.push(proposal.targetMember);
                group.isMember[proposal.targetMember] = true;
                userGroups[proposal.targetMember].push(proposal.groupId);
                emit MemberAdded(proposal.groupId, proposal.targetMember);
                
            } else if (proposal.proposalType == ProposalType.REMOVE_MEMBER) {
                _removeMemberDirectly(proposal.groupId, proposal.targetMember);
            }
            
            emit ProposalExecuted(_proposalId, true);
        } else if (block.timestamp > proposal.deadline) {
            // Proposal failed
            proposal.executed = true;
            proposal.passed = false;
            emit ProposalExecuted(_proposalId, false);
        }
    }

        // Internal function to remove member
    function _removeMemberDirectly(bytes32 _groupId, address _member) internal {
        GroupChat storage group = groups[_groupId];
        
        // Remove from members array
        for (uint i = 0; i < group.members.length; i++) {
            if (group.members[i] == _member) {
                group.members[i] = group.members[group.members.length - 1];
                group.members.pop();
                break;
            }
        }
        
        group.isMember[_member] = false;
        group.isAdmin[_member] = false;
        
        // Remove from user's groups
        bytes32[] storage memberGroups = userGroups[_member];
        for (uint i = 0; i < memberGroups.length; i++) {
            if (memberGroups[i] == _groupId) {
                memberGroups[i] = memberGroups[memberGroups.length - 1];
                memberGroups.pop();
                break;
            }
        }
        
        emit MemberRemoved(_groupId, _member);
    }

    // Get group info
    function getGroupInfo(bytes32 _groupId) external view returns (
        string memory groupName,
        address creator,
        address[] memory members,
        GroupSettings memory settings,
        uint256 createdAt,
        bool isActive
    ) {
        GroupChat storage group = groups[_groupId];
        return (
            group.groupName,
            group.creator,
            group.members,
            group.settings,
            group.createdAt,
            group.isActive
        );
    }
    
    // Get user's groups
    function getUserGroups(address _user) external view returns (bytes32[] memory) {
        return userGroups[_user];
    }
}
