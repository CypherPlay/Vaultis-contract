// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Vaultis} from "./Vaultis.sol";
import {MockERC20} from "./MockERC20.sol";

contract VaultisEventsTest is Test {
    Vaultis public vaultis;
    MockERC20 public mockERC20;
    MockERC20 public mockERC20ForEntryFee;

    address public owner;
    address public player1;
    address public feeRecipient;

    function setUp() public {
        owner = address(uint160(uint256(keccak256(abi.encodePacked("owner")))));
        player1 = address(uint160(uint256(keccak256(abi.encodePacked("player1")))));
        feeRecipient = address(uint160(uint256(keccak256(abi.encodePacked("feeRecipient")))));
        
        mockERC20 = new MockERC20("RetryToken", "RTK");
        mockERC20ForEntryFee = new MockERC20("EntryToken", "ETK");
        
        vaultis = new Vaultis(owner, address(mockERC20)); // Initialize Vaultis with mockERC20 as retryToken

        vm.deal(address(this), 100 ether); // Give the test contract some Ether
        vm.deal(owner, 100 ether);
        vm.deal(player1, 100 ether);
        vm.deal(feeRecipient, 100 ether);
    }

    function testEntryFeesWithdrawnEvent() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 1 ether;
        uint256 riddleId = 1;

        vm.startPrank(owner);
        vaultis.setRiddle(riddleId, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20ForEntryFee));
        vm.stopPrank();

        // Player1 enters the game to generate entry fees
        mockERC20ForEntryFee.mint(player1, vaultis.ENTRY_FEE());
        vm.startPrank(player1);
        mockERC20ForEntryFee.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(riddleId);
        vm.stopPrank();

        uint256 expectedEntryFees = vaultis.ENTRY_FEE();
        assertEq(vaultis.entryFeeBalance(), expectedEntryFees, "Vaultis should have collected entry fees");

        // Expect the EntryFeesWithdrawn event
        vm.expectEmit(true, true, false, true);
        emit Vaultis.EntryFeesWithdrawn(feeRecipient, expectedEntryFees);

        vm.startPrank(owner);
        vaultis.withdrawEntryFees(feeRecipient);
        vm.stopPrank();

        assertEq(vaultis.entryFeeBalance(), 0, "Entry fee balance should be zero after withdrawal");
        assertEq(mockERC20ForEntryFee.balanceOf(feeRecipient), expectedEntryFees, "Fee recipient should receive entry fees");
    }

    function testRetryFeesWithdrawnEvent() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 1 ether;
        uint256 riddleId = 1;

        vm.startPrank(owner);
        vaultis.setRiddle(riddleId, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20ForEntryFee));
        vm.stopPrank();

        // Player1 enters the game and purchases retries to generate fees
        mockERC20ForEntryFee.mint(player1, vaultis.ENTRY_FEE());
        vm.startPrank(player1);
        mockERC20ForEntryFee.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(riddleId);
        vm.stopPrank();

        mockERC20.mint(player1, vaultis.RETRY_COST() * 2);
        vm.startPrank(player1);
        mockERC20.approve(address(vaultis), vaultis.RETRY_COST() * 2);
        vaultis.purchaseRetry(riddleId);
        vaultis.purchaseRetry(riddleId);
        vm.stopPrank();

        uint256 expectedRetryFees = vaultis.RETRY_COST() * 2;
        assertEq(vaultis.retryFeeBalance(), expectedRetryFees, "Vaultis should have collected retry fees");

        // Expect the RetryFeesWithdrawn event
        vm.expectEmit(true, true, false, true);
        emit Vaultis.RetryFeesWithdrawn(feeRecipient, expectedRetryFees);

        vm.startPrank(owner);
        vaultis.withdrawRetryFees(feeRecipient);
        vm.stopPrank();

        assertEq(vaultis.retryFeeBalance(), 0, "Retry fee balance should be zero after withdrawal");
        assertEq(mockERC20.balanceOf(feeRecipient), expectedRetryFees, "Fee recipient should receive retry fees");
    }
}
