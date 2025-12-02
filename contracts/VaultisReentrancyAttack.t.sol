pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";
import {Vaultis} from "./Vaultis.sol";
import {MockERC20} from "./MockERC20.sol";
import {ReentrancyAttackPayout} from "./ReentrancyAttackPayout.sol";

contract VaultisReentrancyAttackTest is Test {
    Vaultis public vaultis;
    MockERC20 public mockERC20;
    ReentrancyAttackPayout public reentrancyAttacker;
    address public user1; // Vaultis owner
    address public user2; // A regular user, not involved in attack directly

    uint256 public constant RIDDLE_ID = 1;
    bytes32 public constant ANSWER_HASH = keccak256(abi.encodePacked("correct_answer"));
    uint256 public constant PRIZE_AMOUNT = 1 ether;
    uint256 public constant ENTRY_FEE = 1 ether;

    function setUp() public {
        user1 = address(uint160(uint256(keccak256(abi.encodePacked("user1")))));
        user2 = address(uint160(uint256(keccak256(abi.encodePacked("user2")))));

        mockERC20 = new MockERC20("MockToken", "MTK");
        vaultis = new Vaultis(user1, address(mockERC20));
        reentrancyAttacker = new ReentrancyAttackPayout(payable(address(vaultis)), address(mockERC20), RIDDLE_ID);

        // Give the test contract some Ether to receive withdrawals and fund prizes
        vm.deal(address(this), 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(address(reentrancyAttacker), 100 ether); // Give attacker some ETH for gas if needed

        // Set a riddle with ETH prize type
        vm.startPrank(user1);
        vaultis.setRiddle(RIDDLE_ID, ANSWER_HASH, Vaultis.PrizeType.ETH, address(0), PRIZE_AMOUNT, address(mockERC20));
        vaultis.setRevealDelay(0); // No delay for testing
        // Fund the ETH prize pool
        (bool success,) = address(vaultis).call{value: PRIZE_AMOUNT}("");
        require(success, "Failed to fund Vaultis with ETH prize");
        vm.stopPrank();

        // Make the reentrancyAttacker a winner for the riddle
        mockERC20.mint(address(reentrancyAttacker), ENTRY_FEE);
        vm.startPrank(address(reentrancyAttacker));
        mockERC20.approve(address(vaultis), ENTRY_FEE);
        vaultis.enterGame(RIDDLE_ID);
        bytes32 guessHash = keccak256(abi.encodePacked("correct_answer"));
        vaultis.submitGuess(RIDDLE_ID, guessHash);
        vaultis.revealGuess(RIDDLE_ID, "correct_answer");
        vm.stopPrank();

        // Sanity check
        assertEq(vaultis.ethPrizePool(), PRIZE_AMOUNT, "Vaultis ETH prize pool not funded correctly");
        assertTrue(vaultis.hasParticipated(RIDDLE_ID, address(reentrancyAttacker)), "Attacker not participated");
        assertTrue(vaultis.hasRevealed(RIDDLE_ID, address(reentrancyAttacker)), "Attacker not revealed guess");
    }

    function testReentrancyAttackOnPayoutIsBlocked() public {
        uint256 initialAttackerBalance = address(reentrancyAttacker).balance;
        bool success = false;
        vm.startPrank(user1); // Vaultis owner initiates payout
        address[] memory winnersBatch = new address[](1);
        winnersBatch[0] = address(reentrancyAttacker);
        try vaultis.payout(RIDDLE_ID, winnersBatch) {
            success = true;
        } catch Error(string memory reason) {
            // Expected revert from Vaultis, either ReentrancyGuard or ETH transfer failed
            if (keccak256(abi.encodePacked(reason)) == keccak256(abi.encodePacked("ETH transfer failed"))) {
                // Expected revert due to reentrancy being blocked
            } else {
                // Unexpected revert
                revert(reason);
            }
        } catch {
            // Catch for any other revert types
        }
        vm.stopPrank();

        // Verify that the attacker only received the prize once (or not at all if the initial call also reverted)
        // The attacker's balance should increase by at most PRIZE_AMOUNT.
        assertLe(address(reentrancyAttacker).balance, initialAttackerBalance + PRIZE_AMOUNT, "Attacker balance increased by more than PRIZE_AMOUNT");

        // The Vaultis ETH prize pool should be reduced by at most PRIZE_AMOUNT.
        // If the payout was successful, it should be 0. If it reverted, it should be PRIZE_AMOUNT.
        uint256 expectedEthPrizePool = success ? 0 : PRIZE_AMOUNT;
        assertEq(vaultis.ethPrizePool(), expectedEthPrizePool, "Vaultis ETH prize pool is incorrect after attack");

        // isPaidOut should be true only if the payout was successful (i.e., not reverted)
        assertEq(vaultis.isPaidOut(RIDDLE_ID), success, "Riddle paid out status is incorrect");
    }

    // The current ERC20 reentrancy test is invalid because standard ERC20 transfers
    // do not trigger `receive()` or `fallback()` functions, which are necessary
    // for reentrant logic to execute within the attacker contract during a transfer.
    // Therefore, a simple ERC20 transfer cannot be used to reenter the `Vaultis.payout`
    // function in the same way an ETH transfer (which triggers `receive()`) can.
    // To test ERC20 reentrancy, a malicious token with a transfer hook (e.g., ERC777)
    // would be required, where the hook calls back to Vaultis during the transfer.
}
