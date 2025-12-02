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
    uint256 public constant ENTRY_FEE = 100;

    function setUp() public {
        user1 = address(uint160(uint256(keccak256(abi.encodePacked("user1")))));
        user2 = address(uint160(uint256(keccak256(abi.encodePacked("user2")))));

        mockERC20 = new MockERC20("MockToken", "MTK");
        vaultis = new Vaultis(user1, address(mockERC20));
        reentrancyAttacker = new ReentrancyAttackPayout(address(vaultis), address(mockERC20), RIDDLE_ID);

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

        // The attack should be blocked by the nonReentrant modifier on Vaultis.payout
        vm.expectRevert("ReentrancyGuard: reentrant call");
        vm.startPrank(user1); // Owner calls payout with the attacker as a winner
        reentrancyAttacker.startPayoutAttack(PRIZE_AMOUNT, 5); // Attempt 5 reentrant calls
        vm.stopPrank();

        // Verify that the attacker only received the prize once (or not at all if the initial call also reverted)
        // Since it expects a revert, the balance should be unchanged from the initial state, or less if gas was consumed.
        // The important part is that the reentrancy attempt itself is reverted.
        assertEq(address(reentrancyAttacker).balance, initialAttackerBalance, "Attacker balance should not change due to revert");
        assertEq(vaultis.ethPrizePool(), PRIZE_AMOUNT, "Vaultis ETH prize pool should be unchanged after reverted attack");
        assertFalse(vaultis.isPaidOut(RIDDLE_ID), "Riddle should not be marked as paid out");
    }

    function testReentrancyAttackOnPayoutIsBlockedErc20() public {
        // Setup for ERC20 prize
        bytes32 erc20AnswerHash = keccak256(abi.encodePacked("erc20_answer"));
        uint256 erc20PrizeAmount = 200;
        uint256 erc20RiddleId = 2;

        vm.startPrank(user1);
        vaultis.setRiddle(erc20RiddleId, erc20AnswerHash, Vaultis.PrizeType.ERC20, address(mockERC20), erc20PrizeAmount, address(mockERC20));
        vaultis.setRevealDelay(0); // No delay for testing
        mockERC20.mint(user1, erc20PrizeAmount);
        mockERC20.approve(address(vaultis), erc20PrizeAmount);
        vaultis.fundTokenPrizePool(erc20PrizeAmount);
        vm.stopPrank();

        // Deploy a new attacker for ERC20 scenario
        ReentrancyAttackPayout erc20Attacker = new ReentrancyAttackPayout(address(vaultis), address(mockERC20), erc20RiddleId);

        // Make the erc20Attacker a winner for the ERC20 riddle
        mockERC20.mint(address(erc20Attacker), ENTRY_FEE);
        vm.startPrank(address(erc20Attacker));
        mockERC20.approve(address(vaultis), ENTRY_FEE);
        vaultis.enterGame(erc20RiddleId);
        bytes32 guessHash = keccak256(abi.encodePacked("erc20_answer"));
        vaultis.submitGuess(erc20RiddleId, guessHash);
        vaultis.revealGuess(erc20RiddleId, "erc20_answer");
        vm.stopPrank();

        // Sanity check
        assertEq(vaultis.tokenPrizePool(), erc20PrizeAmount, "Vaultis ERC20 prize pool not funded correctly");
        assertTrue(vaultis.hasParticipated(erc20RiddleId, address(erc20Attacker)), "ERC20 Attacker not participated");
        assertTrue(vaultis.hasRevealed(erc20RiddleId, address(erc20Attacker)), "ERC20 Attacker not revealed guess");

        uint256 initialAttackerTokenBalance = mockERC20.balanceOf(address(erc20Attacker));

        // The attack should be blocked by the nonReentrant modifier on Vaultis.payout
        vm.expectRevert("ReentrancyGuard: reentrant call");
        vm.startPrank(user1); // Owner calls payout with the attacker as a winner
        erc20Attacker.startPayoutAttack(erc20PrizeAmount, 5); // Attempt 5 reentrant calls
        vm.stopPrank();

        // Verify that the attacker's token balance is unchanged
        assertEq(mockERC20.balanceOf(address(erc20Attacker)), initialAttackerTokenBalance, "Attacker token balance should not change due to revert");
        assertEq(vaultis.tokenPrizePool(), erc20PrizeAmount, "Vaultis ERC20 prize pool should be unchanged after reverted attack");
        assertFalse(vaultis.isPaidOut(erc20RiddleId), "Riddle should not be marked as paid out");
    }
}
