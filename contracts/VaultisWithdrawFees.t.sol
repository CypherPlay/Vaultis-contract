// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";
import {Vaultis} from "./Vaultis.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./MockERC20.sol";
import {MockERC20FeeOnTransfer} from "./MockERC20.sol";

contract VaultisWithdrawFeesTest is Test {
    Vaultis public vaultis;
    MockERC20 public mockERC20;
    MockERC20FeeOnTransfer public mockERC20FeeOnTransfer;

    address public user1; // Owner
    address public user2; // Fee Recipient / Regular user

    function setUp() public {
        user1 = address(uint160(uint256(keccak256(abi.encodePacked("user1")))));
        user2 = address(uint160(uint256(keccak256(abi.encodePacked("user2")))));
        mockERC20 = new MockERC20("MockToken", "MTK");
        mockERC20FeeOnTransfer = new MockERC20FeeOnTransfer("FeeToken", "FOT", 5); // 5% fee
        vaultis = new Vaultis(user1, address(mockERC20)); // Initialize Vaultis with mockERC20 as retryToken
        vm.deal(address(this), 100 ether); // Give the test contract some Ether
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    function testWithdrawRetryFeesSuccess() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 1 ether;
        uint256 riddleId = 1;
        address feeRecipient = user2;

        vm.startPrank(user1);
        vaultis.setRiddle(riddleId, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        // User1 (owner) enters the game and purchases retries to generate fees
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(riddleId);
        vm.stopPrank();

        // User1 purchases two retries
        mockERC20.mint(user1, vaultis.RETRY_COST() * 2);
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), vaultis.RETRY_COST() * 2);
        vaultis.purchaseRetry(riddleId);
        vaultis.purchaseRetry(riddleId);
        vm.stopPrank();

        uint256 expectedRetryFees = vaultis.RETRY_COST() * 2;
        assertEq(vaultis.retryFeeBalance(), expectedRetryFees, "Vaultis should have collected retry fees");
        assertEq(mockERC20.balanceOf(address(vaultis)), vaultis.ENTRY_FEE() + expectedRetryFees, "Vaultis contract should hold entry fee + retry fees");

        // Owner withdraws retry fees to feeRecipient
        uint256 initialFeeRecipientBalance = mockERC20.balanceOf(feeRecipient);
        vm.startPrank(user1);
        vaultis.withdrawRetryFees(feeRecipient);
        vm.stopPrank();

        assertEq(vaultis.retryFeeBalance(), 0, "Retry fee balance should be zero after withdrawal");
        assertEq(mockERC20.balanceOf(address(vaultis)), vaultis.ENTRY_FEE(), "Vaultis contract should only hold entry fee after withdrawal");
        assertEq(mockERC20.balanceOf(feeRecipient), initialFeeRecipientBalance + expectedRetryFees, "Fee recipient should receive retry fees");
    }

    function testWithdrawRetryFeesNonOwnerFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 1 ether;
        uint256 riddleId = 1;

        vm.startPrank(user1);
        vaultis.setRiddle(riddleId, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        // User1 (owner) enters the game and purchases retries to generate fees
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(riddleId);
        vm.stopPrank();

        mockERC20.mint(user1, vaultis.RETRY_COST());
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), vaultis.RETRY_COST());
        vaultis.purchaseRetry(riddleId);
        vm.stopPrank();

        // Non-owner (user2) tries to withdraw retry fees
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user2));
        vm.startPrank(user2);
        vaultis.withdrawRetryFees(user2);
        vm.stopPrank();
    }

    function testWithdrawRetryFeesZeroBalanceFails() public {
        address feeRecipient = user2;
        // No retries purchased, so retryFeeBalance is 0

        vm.expectRevert("No retry fees to withdraw");
        vm.startPrank(user1);
        vaultis.withdrawRetryFees(feeRecipient);
        vm.stopPrank();
    }

    function testWithdrawRetryFeesZeroRecipientFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 1 ether;
        uint256 riddleId = 1;

        vm.startPrank(user1);
        vaultis.setRiddle(riddleId, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        // Purchase some retries to have a balance
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(riddleId);
        vm.stopPrank();

        mockERC20.mint(user1, vaultis.RETRY_COST());
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), vaultis.RETRY_COST());
        vaultis.purchaseRetry(riddleId);
        vm.stopPrank();

        vm.expectRevert("Recipient address cannot be zero");
        vm.startPrank(user1);
        vaultis.withdrawRetryFees(address(0));
        vm.stopPrank();
    }
}
