// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Token} from "../src/Token.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {Treasury} from "../src/Treasury.sol";

contract GovernanceTreasuryTest is Test {
    Token public token;
    MyGovernor public governor;
    TimeLock public timeLock;
    Treasury public treasury;

    bytes32 proposerRole;
    bytes32 executorRole;

    uint256 degree;

    function setUp() public {
        uint256 minDelay = 1;
        address[] memory proposers = new address[](1);
        proposers[0] = msg.sender;
        address[] memory executors = new address[](1);
        executors[0] = msg.sender;

        timeLock = new TimeLock(minDelay, proposers, executors, msg.sender);
        token = new Token(address(timeLock)); // owner timeLock
        treasury = (new Treasury){value: 1 ether}(address(123), address(timeLock)); // owner timeLock
        governor = new MyGovernor(token, timeLock);

        // roles
        proposerRole = timeLock.PROPOSER_ROLE();
        executorRole = timeLock.EXECUTOR_ROLE();

        vm.prank(msg.sender);
        timeLock.grantRole(proposerRole, address(governor));
        vm.prank(msg.sender);
        timeLock.grantRole(executorRole, address(governor));

        degree = 10 ** token.decimals();

        sendTokens();

        vm.roll(block.number + 1);

        delegateTokens();
    }

    function test_Deploed() public {
        uint256 totalSupply = 1000 * degree;

        // treasury
        assertEq(address(treasury).balance, 1 ether);
        assertEq(treasury.owner(), address(timeLock));
        assertEq(treasury.payee(), address(123));
        assertEq(treasury.isReleased(), false);
        // token
        assertEq(token.owner(), address(timeLock));
        assertEq(token.decimals(), 18);
        assertEq(token.balanceOf(address(1)), 50 * degree);
        assertEq(token.balanceOf(address(2)), 50 * degree);
        assertEq(token.balanceOf(address(3)), 50 * degree);
        assertEq(token.balanceOf(address(4)), 50 * degree);
        assertEq(token.balanceOf(address(5)), 50 * degree);
        assertEq(token.totalSupply(), totalSupply);
        // timelock
        assertEq(timeLock.PROPOSER_ROLE(), keccak256("PROPOSER_ROLE"));
        assertEq(timeLock.EXECUTOR_ROLE(), keccak256("EXECUTOR_ROLE"));
        assertEq(timeLock.CANCELLER_ROLE(), keccak256("CANCELLER_ROLE"));
        assertTrue(timeLock.hasRole(proposerRole, address(governor)));
        assertTrue(timeLock.hasRole(executorRole, address(governor)));
    }

    function test_CreateProposalTreasury() public returns (uint256) {
        string memory description = "Release Funds from Treasury";
        address[] memory targets;
        uint256[] memory values;
        bytes[] memory calldatas;
        bytes32 descriptionHash;
        (targets, values, calldatas, descriptionHash) =
            getParams(Treasury.releaseFunds.selector, description, address(treasury), 0);

        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        uint256 hashProposal = governor.hashProposal(targets, values, calldatas, descriptionHash);
        assertEq(hashProposal, proposalId);

        uint256 snapshot = governor.proposalSnapshot(proposalId);
        console.log("%s #%d", "Proposal created on block", snapshot);

        uint256 deadline = governor.proposalDeadline(proposalId);
        console.log("%s #%d", "Proposal deadline on block", deadline);

        uint256 blockNumber = block.number;
        uint256 quorum = governor.quorum(blockNumber - 1);
        console.log("%s %d", "Number of votes required to pass:", quorum / 1e18);

        // States: Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed
        uint256 state = uint256(governor.state(proposalId));
        console.log("%s %d", "Current state of proposal = Pending", state);

        return proposalId;
    }

    function test_VoutingTreasury() public {
        uint256 proposalId = test_CreateProposalTreasury();

        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        // States: Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed
        uint256 state = uint256(governor.state(proposalId));
        console.log("%s %d", "Current state of proposal = Active", state);

        // 0 = Against, 1 = For, 2 = Abstain
        vm.prank(address(1));
        governor.castVote(proposalId, 1);
        vm.prank(address(2));
        governor.castVote(proposalId, 1);
        vm.prank(address(3));
        governor.castVote(proposalId, 1);
        vm.prank(address(4));
        governor.castVote(proposalId, 0);
        vm.prank(address(5));
        governor.castVote(proposalId, 2);

        // Checking to see if the person has voted
        bool voted = governor.hasVoted(proposalId, address(5));
        assertEq(voted, true);

        vm.roll(governor.proposalDeadline(proposalId) + 1);

        // States: Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed
        state = uint256(governor.state(proposalId));
        console.log("%s %d", "Current state of proposal = Succeeded", state);

        uint256 againstVotes;
        uint256 forVotes;
        uint256 abstainVotes;
        (againstVotes, forVotes, abstainVotes) = governor.proposalVotes(proposalId);

        logVotes(forVotes, againstVotes, abstainVotes);

        string memory description = "Release Funds from Treasury";
        address[] memory targets;
        uint256[] memory values;
        bytes[] memory calldatas;
        bytes32 descriptionHash;
        (targets, values, calldatas, descriptionHash) =
            getParams(Treasury.releaseFunds.selector, description, address(treasury), 0);

        governor.queue(targets, values, calldatas, descriptionHash);

        // States: Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed
        state = uint256(governor.state(proposalId));
        console.log("%s %d", "Current state of proposal - Queued", state);

        // voting depends on block numbers, but execution depends on the timestamp
        vm.warp(block.timestamp + 2);
        governor.execute(targets, values, calldatas, descriptionHash);

        // States: Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed
        state = uint256(governor.state(proposalId));
        console.log("%s %d", "Current state of proposal - Executed", state);

        // Verification of function execution
        assertEq(treasury.isReleased(), true);
        assertEq(address(123).balance, 1 ether);
    }

    function test_CalcelProposalTreasury() public {
        uint256 proposalId = test_CreateProposalTreasury();
        // States: Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed
        uint256 state = uint256(governor.state(proposalId));
        console.log("%s %d", "Current state of proposal = Active", state);

        string memory description = "Release Funds from Treasury";
        address[] memory targets;
        uint256[] memory values;
        bytes[] memory calldatas;
        bytes32 descriptionHash;
        (targets, values, calldatas, descriptionHash) =
            getParams(Treasury.releaseFunds.selector, description, address(treasury), 0);

        governor.cancel(targets, values, calldatas, descriptionHash);

        // States: Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed
        state = uint256(governor.state(proposalId));
        console.log("%s %d", "Current state of proposal = Canceled", state);
    }

    function sendTokens() internal {
        vm.prank(address(timeLock));
        token.transfer(address(1), 50 * degree);
        vm.prank(address(timeLock));
        token.transfer(address(2), 50 * degree);
        vm.prank(address(timeLock));
        token.transfer(address(3), 50 * degree);
        vm.prank(address(timeLock));
        token.transfer(address(4), 50 * degree);
        vm.prank(address(timeLock));
        token.transfer(address(5), 50 * degree);
    }

    function delegateTokens() internal {
        vm.prank(address(1));
        token.delegate(address(1));
        vm.prank(address(2));
        token.delegate(address(2));
        vm.prank(address(3));
        token.delegate(address(3));
        vm.prank(address(4));
        token.delegate(address(4));
        vm.prank(address(5));
        token.delegate(address(5));
    }

    function logVotes(uint256 forVotes, uint256 againstVotes, uint256 abstainVotes) internal view {
        console.log("Votes For:", forVotes / 1e18);
        console.log("Votes Against:", againstVotes / 1e18);
        console.log("Votes Neutral:", abstainVotes / 1e18);
    }

    function getParams(bytes4 selector, string memory description, address target, uint256 value)
        internal
        pure
        returns (address[] memory, uint256[] memory, bytes[] memory, bytes32)
    {
        bytes memory encodedFunc = abi.encodeWithSelector(selector);
        address[] memory targets = new address[](1);
        targets[0] = target;

        uint256[] memory values = new uint256[](1);
        values[0] = value;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = encodedFunc;

        bytes32 descriptionHash = keccak256(abi.encodePacked(description));

        return (targets, values, calldatas, descriptionHash);
    }
}
