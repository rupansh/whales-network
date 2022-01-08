// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
// TODO: Remove this (not required in solidity 0.8)
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";


contract WhaleNetworkGovernance is Ownable, EIP712 {
	// TODO: remove this
    using SafeMath for uint256;

    enum ProposalStatus {
        VALID,
        FORFEITED,
        EXECUTED
    }

    enum Vote {
        AGAINST,
        FOR
    }

    struct VoteStatus {
        uint256 against;
        uint256 support;
    }

    struct Proposal {
        string title;
        string details;
        address creator;
        uint256 startBlock;
        uint256 endBlock;
        uint256 id;
        ProposalStatus status;
    }

    IERC20 public _token;

    uint256 private _minTokenForVoting;
    uint256 private _minTokenForProposal;
    uint256 public _nextProposalId = 1;

    mapping(uint256 => Proposal) _proposals;
    mapping(uint256 => VoteStatus) _votes;
    mapping(uint256 => mapping(address => bool)) _proposalVotingStatus;

    event ProposalCreated(address indexed creatorAddress, string title, string details, uint256 proposalId);
    event VoteCast(address indexed voter, uint256 weight, Vote status);
    event ProposalExecuted(uint256 proposalId);
    event ProposalForfeited(uint256 proposalId);

    constructor(
        IERC20 token,
        uint256 minForVoting,
        uint256 minForProposal
    ) EIP712("WhalesNetwork", "v1.0.0") {
        require(
            address(token) != address(0),
            "WhaleNetworkGovernance: Token address can not be zero address"
        );
        require(
            minForVoting > 0,
            "WhaleNetworkGovernance: Minimum tokens for voting must be greater then zero."
        );
        require(
            minForProposal > 0,
            "WhaleNetworkGovernance: Minimum tokens for creating proposals must be greater then zero."
        );
        _token = token;
        _minTokenForProposal = minForProposal * 1 ether;
        _minTokenForVoting = minForVoting * 1 ether;
    }

    function minimumTokenRequiredVoting() public view returns (uint256) {
        return _minTokenForVoting;
    }

    function minimumTokenRequiredProposal() public view returns (uint256) {
        return _minTokenForProposal;
    }

    function setMinimumTokenRequiredVoting(uint256 amount)
        external
        onlyOwner
        returns (bool)
    {
        require(
            amount > 0,
            "WhaleNetworkGovernance: Minimum tokens for voting must be greater then zero."
        );
        _minTokenForVoting = amount;
        return true;
    }

    function setMinimumTokenRequiredProposal(uint256 amount)
        external
        onlyOwner
        returns (bool)
    {
        require(
            amount > 0,
            "WhaleNetworkGovernance: Minimum tokens for creating proposals must be greater then zero."
        );
        _minTokenForProposal = amount;
        return true;
    }

    function createProposal(
        string memory proposalTitle,
        string memory proposalDetails,
        uint256 start,
        uint256 end
    ) external returns (bool) {
        require(
            bytes(proposalTitle).length > 0,
            "WhaleNetworkGovernance: Proposal Title cannot be empty"
        );
        require(
            bytes(proposalDetails).length > 0,
            "WhaleNetworkGovernance: Proposal Title cannot be empty"
        );
        require(
            _token.balanceOf(_msgSender()) >= _minTokenForProposal,
            "WhaleNetworkGovernance: Insufficient tokens for creating a proposal"
        );

        require(
            start > block.number,
            "WhaleNetworkGovernance: Start time of proposal must be in future."
        );
        require(
            end > start,
            "WhaleNetworkGovernance: End time of proposal must be after start time."
        );

        _proposals[_nextProposalId] = Proposal(
            proposalTitle,
            proposalDetails,
            _msgSender(),
            start,
            end,
            _nextProposalId,
            ProposalStatus.VALID
        );
        emit ProposalCreated(_msgSender(), proposalTitle, proposalDetails, _nextProposalId);
		_nextProposalId += 1;
        return true;
    }

    function getProposal(uint256 proposalId)
        public
        view
        returns (Proposal memory)
    {
        require(
            proposalId > 0 && proposalId < _nextProposalId,
            "WhaleNetworkGovernance: Invalid proposal Id"
        );
        return _proposals[proposalId];
    }

	function _castVote(address caster, uint256 proposalId, bool vote) private returns (bool) {
        //vote = 0 - NO
        //vote = 1 - YES
        require(
            _token.balanceOf(caster) >= _minTokenForVoting,
            "WhaleNetworkGovernance: Insufficient tokens for voting"
        );
        require(
            proposalId > 0 && proposalId < _nextProposalId,
            "WhaleNetworkGovernance: Invalid proposal Id"
        );
        require(
            !_proposalVotingStatus[proposalId][caster],
            "WhaleNetworkGovernance: You have already voted on this proposal"
        );

        VoteStatus storage proposalVote = _votes[proposalId];
        Proposal memory proposal = _proposals[proposalId];

        require(
            block.number > proposal.startBlock &&
                block.number < proposal.endBlock,
            "WhaleNetworkGovernance: Voting is not active on the proposal"
        );

        require(
            proposal.status == ProposalStatus.VALID,
            "WhaleNetworkGovernance: Votes can be casted only on the valid proposals."
        );

        _proposalVotingStatus[proposalId][caster] = true;
        if (vote) {
            proposalVote.support += _token.balanceOf(caster);
            emit VoteCast(
                caster,
                _token.balanceOf(caster),
                Vote.FOR
            );
        } else {
            proposalVote.against += _token.balanceOf(caster);
            emit VoteCast(
                caster,
                _token.balanceOf(caster),
                Vote.AGAINST
            );
        }

		return true;
	}

	function castVoteFor(bytes calldata sig, address caster, uint256 proposalId, bool vote) external returns (bool) {
		bytes32 hash = _hashTypedDataV4(keccak256(abi.encode(
			keccak256("castVote(address caster,uint256 proposalId,bool vote)"),
			caster,
			proposalId,
			vote
		)));
		address signer = ECDSA.recover(hash, sig);
		require(signer == caster, "castVote: invalid sig");
		require(signer != address(0), "castVote: invalid sig");

		return _castVote(caster, proposalId, vote);
	}

    function castVote(uint256 proposalId, bool vote)
        external
        returns (bool)
    {
		return _castVote(_msgSender(), proposalId, vote);
    }

    // whether user has voted or not
    function hasVoted(address voter, uint256 proposalId)
        public
        view
        returns (bool)
    {
        require(
            proposalId > 0 && proposalId < _nextProposalId,
            "WhaleNetworkGovernance: Invalid proposal Id"
        );
        return _proposalVotingStatus[proposalId][voter];
    }

    function getResult(uint256 proposalId)
        public
        view
        returns (VoteStatus memory)
    {
        require(
            proposalId > 0 && proposalId < _nextProposalId,
            "WhaleNetworkGovernance: Invalid proposal Id"
        );
        return _votes[proposalId];
    }

    function isVotingActive(uint256 proposalId) public view returns (bool) {
        require(
            proposalId > 0 && proposalId < _nextProposalId,
            "WhaleNetworkGovernance: Invalid proposal Id"
        );
        Proposal memory proposal = _proposals[proposalId];
        if (
            block.number > proposal.startBlock &&
            block.number < proposal.endBlock
        ) {
            return true;
        } else {
            return false;
        }
    }

    function isProposalPassed(uint256 proposalId) public view returns (bool) {
        require(
            proposalId > 0 && proposalId < _nextProposalId,
            "WhaleNetworkGovernance: Invalid proposal Id"
        );
        VoteStatus memory voteStatus = getResult(proposalId);
        
        if (voteStatus.support > voteStatus.support.add(voteStatus.against)) {
            return true;
        } else {
            return false;
        }
    }

    function executeProposal(uint256 proposalId)
        external
        onlyOwner
        returns (bool)
    {
        require(
            proposalId > 0 && proposalId < _nextProposalId,
            "WhaleNetworkGovernance: Invalid proposal Id"
        );

        require(
            isProposalPassed(proposalId),
            "WhaleNetworkGovernance: Proposal has not passed the voting"
        );
        Proposal memory proposal = _proposals[proposalId];
        proposal.status = ProposalStatus.EXECUTED;
        _proposals[proposalId] = proposal;
        emit ProposalExecuted(proposalId);
        return true;
    }

    function forfeitProposal(uint256 proposalId) public returns (bool) {
        require(
            proposalId > 0 && proposalId < _nextProposalId,
            "WhaleNetworkGovernance: Invalid proposal Id"
        );
        Proposal memory proposal = _proposals[proposalId];
        require(
            block.number < proposal.startBlock,
            "WhaleNetworkGovernance: Voting on the proposal has started and it can not be forfeited"
        );
        require(
            proposal.creator == _msgSender(),
            "WhaleNetworkGovernance: Proposal can be forfeited only by the proposal creator."
        );
        proposal.status = ProposalStatus.FORFEITED;
        _proposals[proposalId] = proposal;
        emit ProposalForfeited(proposalId);
        return true;
    }

    function proposalStartBlock(uint256 proposalId)
        public
        view
        returns (uint256)
    {
        require(
            proposalId > 0 && proposalId < _nextProposalId,
            "WhaleNetworkGovernance: Invalid proposal Id"
        );
        Proposal memory proposal = _proposals[proposalId];
        return proposal.startBlock;
    }

    function proposalEndBlock(uint256 proposalId)
        public
        view
        returns (uint256)
    {
        require(
            proposalId > 0 && proposalId < _nextProposalId,
            "WhaleNetworkGovernance: Invalid proposal Id"
        );
        Proposal memory proposal = _proposals[proposalId];
        return proposal.endBlock;
    }

    function getProposalStatus(uint256 proposalId)
        public
        view
        returns (ProposalStatus)
    {
        require(
            proposalId > 0 && proposalId < _nextProposalId,
            "WhaleNetworkGovernance: Invalid proposal Id"
        );
        Proposal memory proposal = _proposals[proposalId];
        return proposal.status;
    }
}
