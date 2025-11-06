pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";
import {Vaultis} from "./Vaultis.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockERC20FeeOnTransfer is MockERC20 {
    uint256 public feePercentage;

    constructor(string memory name, string memory symbol, uint256 _feePercentage) MockERC20(name, symbol) {
        feePercentage = _feePercentage;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        uint256 fee = (amount * feePercentage) / 100;
        uint256 amountToSend = amount - fee;
        _transfer(msg.sender, to, amountToSend);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        uint256 fee = (amount * feePercentage) / 100;
        uint256 amountToSend = amount - fee;
        _approve(from, msg.sender, allowance(from, msg.sender) - amount);
        _transfer(from, to, amountToSend);
        return true;
    }
}

contract VaultisTest is Test {
    Vaultis public vaultis;
    MockERC20 public mockERC20;
    MockERC20FeeOnTransfer public mockERC20FeeOnTransfer;
    address public user1;
    address public user2;

    function setUp() public {
        user1 = address(uint160(uint256(keccak256(abi.encodePacked("user1")))));
        user2 = address(uint160(uint256(keccak256(abi.encodePacked("user2")))));
        mockERC20 = new MockERC20("MockToken", "MTK");
        vaultis = new Vaultis(user1, address(mockERC20));
        mockERC20FeeOnTransfer = new MockERC20FeeOnTransfer("FeeToken", "FOT", 5); // 5% fee
        vm.deal(address(this), 100 ether); // Give the test contract some Ether to receive withdrawals and fund prizes
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    function testOwnerIsTestContract() public view {
        assertEq(vaultis.owner(), user1);
    }

    function testDeposit() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        vaultis.deposit{value: 1 ether}();
        vm.stopPrank();

        assertEq(vaultis.balances(user1), 1 ether);
        assertEq(address(vaultis).balance, 1 ether);
    }

    function testDepositZeroAmountFails() public {
        vm.expectRevert("Deposit amount must be greater than zero");
        vm.startPrank(user1);
        vaultis.deposit{value: 0}();
        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        vaultis.deposit{value: 5 ether}();
        vaultis.withdraw(2 ether);
        vm.stopPrank();

        assertEq(vaultis.balances(user1), 3 ether);
        assertEq(address(vaultis).balance, 3 ether);
    }

    function testWithdrawInsufficientBalanceFails() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        vaultis.deposit{value: 1 ether}();
        vm.expectRevert("Insufficient balance");
        vaultis.withdraw(2 ether);
        vm.stopPrank();
    }

    function testWithdrawZeroAmountFails() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        vaultis.deposit{value: 1 ether}();
        vm.expectRevert("Withdrawal amount must be greater than zero");
        vaultis.withdraw(0);
        vm.stopPrank();
    }

    function testEnterGame() public {
        bytes32 answerHash = keccak256(abi.encode("test_answer"));
        uint256 prizeAmount = 1 ether;

        // Set an active riddle
        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        // user2 enters the game
        vm.startPrank(user2);
        mockERC20.mint(user2, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        assertTrue(vaultis.hasParticipated(1, user2), "user2 should have participated in riddle 1");

        // user2 tries to re-enter the same game
        vm.expectRevert("Already participated in this riddle");
        vm.startPrank(user2);
        vaultis.enterGame(1);
        vm.stopPrank();

        // user2 tries to enter an inactive riddle
        vm.expectRevert("Not the active riddle ID");
        vm.startPrank(user2);
        vaultis.enterGame(2);
        vm.stopPrank();
    }

    function testSubmitGuessSuccess() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        bytes32 guessHash = keccak256(abi.encodePacked("my_guess"));
        vm.startPrank(user1);
        vaultis.submitGuess(1, guessHash);
        vm.stopPrank();

        assertEq(vaultis.committedGuesses(1, user1), guessHash);
        assertTrue(vaultis.committedAt(1, user1) > 0);
    }

    function testSubmitGuessAlreadyCommittedFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        bytes32 guessHash = keccak256(abi.encodePacked("my_guess"));
        vm.startPrank(user1);
        vaultis.submitGuess(1, guessHash);
        vm.expectRevert("No retries available");
        vaultis.submitGuess(1, guessHash);
        vm.stopPrank();
    }

    function testRevealGuessBeforeRevealDelayFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vaultis.setRevealDelay(100); // 100 seconds delay
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        bytes32 guessHash = keccak256(abi.encodePacked("my_guess"));
        vm.startPrank(user1);
        vaultis.submitGuess(1, guessHash);
        vm.stopPrank();

        vm.expectRevert("Reveal too early");
        vm.startPrank(user1);
        vaultis.revealGuess(1, "my_guess");
        vm.stopPrank();
    }

    function testRevealGuessMismatchFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vaultis.setRevealDelay(0); // No delay for testing
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        bytes32 guessHash = keccak256(abi.encodePacked("my_guess"));
        vm.startPrank(user1);
        vaultis.submitGuess(1, guessHash);
        vm.stopPrank();

        vm.expectRevert("Reveal does not match commit");
        vm.startPrank(user1);
        vaultis.revealGuess(1, "wrong_guess");
        vm.stopPrank();
    }

    function testRevealGuessSuccess() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vaultis.setRevealDelay(0); // No delay for testing
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        bytes32 guessHash = keccak256(abi.encodePacked("my_guess"));
        vm.startPrank(user1);
        vaultis.submitGuess(1, guessHash);
        vm.stopPrank();

        vm.startPrank(user1);
        vaultis.revealGuess(1, "my_guess");
        vm.stopPrank();

        assertEq(vaultis.revealedGuessHash(1, user1), guessHash);
        assertTrue(vaultis.hasRevealed(1, user1));
        assertEq(vaultis.committedGuesses(1, user1), bytes32(0)); // Should be cleared
        assertEq(vaultis.committedAt(1, user1), 0); // Should be cleared
    }

    function testSolveRiddleAndClaimWithoutRevealFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        (bool success, ) = address(vaultis).call{value: prizeAmount}(""); // Fund the ETH prize pool
        require(success);
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        bytes32 guessHash = keccak256(abi.encodePacked("correct_answer"));
        vm.startPrank(user1);
        vaultis.submitGuess(1, guessHash);
        vm.stopPrank();

        vm.expectRevert("Must reveal guess before solving");
        vm.startPrank(user1);
        vaultis.solveRiddleAndClaim("correct_answer");
        vm.stopPrank();
    }

    function testSolveRiddleAndClaimWithRevealSuccess() public {
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vaultis.setRevealDelay(0); // No delay for testing
        (bool success, ) = address(vaultis).call{value: prizeAmount}(""); // Fund the ETH prize pool
        require(success);
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        bytes32 guessHash = keccak256(abi.encodePacked("correct_answer"));
        vm.startPrank(user1);
        vaultis.submitGuess(1, guessHash);
        vm.stopPrank();

        vm.startPrank(user1);
        vaultis.revealGuess(1, "correct_answer");
        vm.stopPrank();

        assertEq(vaultis.ethPrizePool(), prizeAmount);
        uint256 initialUserBalance = user1.balance;

        vm.startPrank(user1);
        vaultis.solveRiddleAndClaim("correct_answer");
        vm.stopPrank();

        assertEq(vaultis.ethPrizePool(), 0);
        assertEq(user1.balance, initialUserBalance + prizeAmount);
        assertTrue(vaultis.hasParticipated(1, user1));
        assertFalse(vaultis.hasRevealed(1, user1)); // Should be cleared
        assertEq(vaultis.revealedGuessHash(1, user1), bytes32(0)); // Should be cleared
    }

    function testSetRevealDelaySuccess() public {
        vm.startPrank(user1);
        vaultis.setRevealDelay(3600); // 1 hour
        vm.stopPrank();
        assertEq(vaultis.revealDelay(), 3600);
    }

    function testSetRevealDelayNonOwnerFails() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user2));
        vm.startPrank(user2);
        vaultis.setRevealDelay(3600);
        vm.stopPrank();
    }

    function testOwnerWithdraw() public {
        vm.startPrank(user1);
        (bool sent, ) = address(vaultis).call{value: 5 ether}("");
        require(sent, "Failed to send eth to vaultis");
        uint256 initialPool = vaultis.ethPrizePool();
        vaultis.ownerWithdraw(2 ether);
        vm.stopPrank();

        assertEq(address(vaultis).balance, 3 ether);
        assertEq(user1.balance, 97 ether); // user1's balance should increase by 2 ether
        assertEq(vaultis.ethPrizePool(), initialPool - 2 ether);
    }

    function testOwnerWithdrawInsufficientContractBalanceFails() public {
        vm.expectRevert("Insufficient ETH prize pool");
        vm.startPrank(user1);
        vaultis.ownerWithdraw(1 ether);
        vm.stopPrank();
    }

    function testOwnerWithdrawNonOwnerFails() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        vaultis.deposit{value: 5 ether}();
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user2));
        vm.startPrank(user2);
        vaultis.ownerWithdraw(1 ether);
        vm.stopPrank();
    }

    function testOwnerWithdrawZeroAmountFails() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        vaultis.deposit{value: 5 ether}();
        vm.expectRevert("Owner withdrawal amount must be greater than zero");
        vaultis.ownerWithdraw(0);
        vm.stopPrank();
    }

    function testReentrancyGuardDeposit() public {
        // This test is more about ensuring nonReentrant modifier is present
        // and doesn't cause issues, rather than a full reentrancy attack simulation
        // which would require a malicious contract.
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        vaultis.deposit{value: 1 ether}();
        vm.stopPrank();
        assertEq(vaultis.balances(user1), 1 ether);
    }

    function testReentrancyGuardWithdraw() public {
        // Similar to deposit, this primarily checks the modifier's presence.
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        vaultis.deposit{value: 1 ether}();
        vaultis.withdraw(1 ether);
        vm.stopPrank();
        assertEq(vaultis.balances(user1), 0 ether);
    }

    function testSetRiddleEthPrize() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        assertEq(vaultis.currentRiddleId(), 1);
        assertEq(uint256(vaultis.prizeType()), uint256(Vaultis.PrizeType.ETH));
        assertEq(vaultis.getPrizeToken(), address(0));
        assertEq(vaultis.prizeAmount(), prizeAmount);
        assertEq(vaultis.ethPrizePool(), 0);
        assertEq(vaultis.tokenPrizePool(), 0);
    }

    function testSetRiddleErc20Prize() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 100 * 10 ** mockERC20.decimals();

        vm.startPrank(user1);
        vaultis.setRiddle(2, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount, address(mockERC20));
        vm.stopPrank();

        assertEq(vaultis.currentRiddleId(), 2);
        assertEq(uint256(vaultis.prizeType()), uint256(Vaultis.PrizeType.ERC20));
        assertEq(vaultis.getPrizeToken(), address(mockERC20));
        assertEq(vaultis.prizeAmount(), prizeAmount);
        assertEq(vaultis.ethPrizePool(), 0);
        assertEq(vaultis.tokenPrizePool(), 0);
    }

    function testSetRiddleZeroIdFails() public {
        vm.expectRevert("Riddle ID cannot be zero");
        vm.startPrank(user1);
        vaultis.setRiddle(0, keccak256(abi.encodePacked("answer")), Vaultis.PrizeType.ETH, address(0), 1 ether, address(mockERC20));
        vm.stopPrank();
    }

    function testSetRiddleBackdatingFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));

        vm.startPrank(user1);
        vaultis.setRiddle(5, answerHash, Vaultis.PrizeType.ETH, address(0), 1 ether, address(mockERC20));
        vm.expectRevert("Riddle ID must be greater than current");
        vaultis.setRiddle(3, answerHash, Vaultis.PrizeType.ETH, address(0), 1 ether, address(mockERC20));
        vm.stopPrank();
    }

    function testSetRiddleSameIdFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));

        vm.startPrank(user1);
        vaultis.setRiddle(5, answerHash, Vaultis.PrizeType.ETH, address(0), 1 ether, address(mockERC20));
        vm.expectRevert("Riddle ID must be greater than current");
        vaultis.setRiddle(5, answerHash, Vaultis.PrizeType.ETH, address(0), 1 ether, address(mockERC20));
        vm.stopPrank();
    }

    function testSetRiddleNonOwnerFails() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user2));
        vm.startPrank(user2);
        vaultis.setRiddle(1, keccak256(abi.encodePacked("answer")), Vaultis.PrizeType.ETH, address(0), 1 ether, address(mockERC20));
        vm.stopPrank();
    }

    function testSetRiddleOwnerSucceeds() public {
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        vm.startPrank(user1); // owner
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), 500, address(mockERC20));
        // assert riddle state or emitted event
        assertEq(vaultis.currentRiddleId(), 1);
        assertEq(vaultis.prizeAmount(), 500);
        assertEq(vaultis.getPrizeToken(), address(mockERC20));
        vm.stopPrank();
    }

    function testSetRiddleZeroPrizeAmountFails() public {
        vm.expectRevert("Prize amount must be greater than zero");
        vm.startPrank(user1);
        vaultis.setRiddle(1, keccak256(abi.encodePacked("answer")), Vaultis.PrizeType.ETH, address(0), 0, address(mockERC20));
        vm.stopPrank();
    }

    function testSetRiddleErc20ZeroTokenAddressFails() public {
        vm.expectRevert("Prize token address cannot be zero for ERC20 prize");
        vm.startPrank(user1);
        vaultis.setRiddle(1, keccak256(abi.encodePacked("answer")), Vaultis.PrizeType.ERC20, address(0), 100, address(mockERC20));
        vm.stopPrank();
    }

    function testSetRiddleErc20InvalidTokenContractFails() public {
        // Use a regular address that is not a contract
        address nonContractAddress = address(uint160(uint256(keccak256(abi.encodePacked("nonContract")))));
        vm.expectRevert("Prize token has no contract code");
        vm.startPrank(user1);
        vaultis.setRiddle(1, keccak256(abi.encodePacked("answer")), Vaultis.PrizeType.ERC20, nonContractAddress, 100, address(mockERC20));
        vm.stopPrank();
    }

    function testSetRiddleErc20InvalidTokenTotalSupplyFails() public {
        // Deploy a contract that is not an ERC20 and doesn't have totalSupply
        address notAnErc20 = address(new Vaultis(user1, address(mockERC20))); // Use Vaultis itself as a non-ERC20 contract
        vm.expectRevert("Invalid ERC-20 token: totalSupply call failed");
        vm.startPrank(user1);
        vaultis.setRiddle(1, keccak256(abi.encodePacked("answer")), Vaultis.PrizeType.ERC20, notAnErc20, 100, address(mockERC20));
        vm.stopPrank();
    }

    function testEthPrizeFunding() public {
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        uint256 prizeAmount = 5 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        assertEq(vaultis.ethPrizePool(), 0);

        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        (bool success, ) = address(vaultis).call{value: 3 ether}("");
        require(success);
        vm.stopPrank();

        assertEq(vaultis.ethPrizePool(), 3 ether);
        assertEq(address(vaultis).balance, 3 ether);
    }

    function testTokenPrizeFunding() public {
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        uint256 prizeAmount = 500;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount, address(mockERC20));
        vm.stopPrank();

        assertEq(vaultis.tokenPrizePool(), 0);

        // Mint tokens to user1 and approve Vaultis to spend them
        mockERC20.mint(user1, 1000);
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), 500);
        vaultis.fundTokenPrizePool(500);
        vm.stopPrank();

        assertEq(vaultis.tokenPrizePool(), 500);
        assertEq(mockERC20.balanceOf(address(vaultis)), 500);
        assertEq(mockERC20.balanceOf(user1), 500);
    }

    function testTokenPrizeFundingNonOwnerFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        uint256 prizeAmount = 500;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount, address(mockERC20));
        vm.stopPrank();

        mockERC20.mint(user2, 1000);
        vm.startPrank(user2);
        mockERC20.approve(address(vaultis), 500);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user2));
        vaultis.fundTokenPrizePool(500);
        vm.stopPrank();
    }

    function testTokenPrizeFundingWrongPrizeTypeFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        uint256 prizeAmount = 5 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        mockERC20.mint(user1, 1000);
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), 500);
        vm.stopPrank();

        vm.expectRevert("Current riddle prize is not ERC20");
        vm.startPrank(user1);
        vaultis.fundTokenPrizePool(500);
        vm.stopPrank();
    }



    function testTokenPrizeFundingInsufficientAllowanceFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        uint256 prizeAmount = 500;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount, address(mockERC20));
        vm.stopPrank();

        mockERC20.mint(user1, 1000);
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), 100);
        vm.stopPrank();

        vm.expectRevert(); // SafeERC20 will revert on insufficient allowance
        vm.startPrank(user1);
        vaultis.fundTokenPrizePool(500);
        vm.stopPrank();
    }

    function testTokenPrizeFundingInsufficientBalanceFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        uint256 prizeAmount = 500;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount, address(mockERC20));
        vm.stopPrank();

        // user1 has no tokens
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), 500);
        vm.stopPrank();

        vm.expectRevert(); // SafeERC20 will revert on insufficient balance
        vm.startPrank(user1);
        vaultis.fundTokenPrizePool(500);
        vm.stopPrank();
    }

    function testSolveRiddleAndClaimEthPrize() public {
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vaultis.setRevealDelay(0); // No delay for testing
        (bool success, ) = address(vaultis).call{value: prizeAmount}(""); // Fund the ETH prize pool
        require(success);
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        assertEq(vaultis.ethPrizePool(), prizeAmount);
        uint256 initialUserBalance = user1.balance;

        bytes32 guessHash = keccak256(abi.encodePacked("correct_answer"));
        vm.startPrank(user1);
        vaultis.submitGuess(1, guessHash);
        vm.stopPrank();

        vm.startPrank(user1);
        vaultis.revealGuess(1, "correct_answer");
        vaultis.solveRiddleAndClaim("correct_answer");
        vm.stopPrank();

        assertEq(vaultis.ethPrizePool(), 0);
        assertEq(user1.balance, initialUserBalance + prizeAmount);
        assertTrue(vaultis.hasParticipated(1, user1));
    }

    function testSolveRiddleAndClaimErc20Prize() public {
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        uint256 prizeAmount = 100;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount, address(mockERC20));
        vaultis.setRevealDelay(0); // No delay for testing
        // Fund the ERC20 prize pool
        mockERC20.mint(user1, prizeAmount);
        mockERC20.approve(address(vaultis), prizeAmount);
        vaultis.fundTokenPrizePool(prizeAmount);
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        assertEq(vaultis.tokenPrizePool(), prizeAmount);
        assertEq(mockERC20.balanceOf(user1), 0);

        bytes32 guessHash = keccak256(abi.encodePacked("correct_answer"));
        vm.startPrank(user1);
        vaultis.submitGuess(1, guessHash);
        vm.stopPrank();

        vm.startPrank(user1);
        vaultis.revealGuess(1, "correct_answer");
        vaultis.solveRiddleAndClaim("correct_answer");
        vm.stopPrank();

        assertEq(vaultis.tokenPrizePool(), 0);
        assertEq(mockERC20.balanceOf(user1), prizeAmount);
        assertTrue(vaultis.hasParticipated(1, user1));
    }

    function testSolveRiddleAndClaimInsufficientEthPrizeFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vaultis.setRevealDelay(0); // No delay for testing
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        bytes32 guessHash = keccak256(abi.encodePacked("correct_answer"));
        vm.startPrank(user1);
        vaultis.submitGuess(1, guessHash);
        vm.stopPrank();

        vm.startPrank(user1);
        vaultis.revealGuess(1, "correct_answer");
        vm.expectRevert("Insufficient ETH prize pool balance");
        vaultis.solveRiddleAndClaim("correct_answer");
        vm.stopPrank();
    }

    function testSolveRiddleAndClaimInsufficientErc20PrizeFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        uint256 prizeAmount = 100;
        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount, address(mockERC20));
        vaultis.setRevealDelay(0); // No delay for testing
        mockERC20.mint(user1, 50);
        mockERC20.approve(address(vaultis), 50);
        vaultis.fundTokenPrizePool(50);
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        assertEq(vaultis.tokenPrizePool(), 50);

        bytes32 guessHash = keccak256(abi.encodePacked("correct_answer"));
        vm.startPrank(user1);
        vaultis.submitGuess(1, guessHash);
        vm.stopPrank();

        vm.startPrank(user1);
        vaultis.revealGuess(1, "correct_answer");
        vm.expectRevert("Insufficient ERC20 prize pool balance");
        vaultis.solveRiddleAndClaim("correct_answer");
        vm.stopPrank();
    }

    function testSolveRiddleAndClaimIncorrectAnswerFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vaultis.setRevealDelay(0); // No delay for testing
        (bool success, ) = address(vaultis).call{value: prizeAmount}("");
        require(success);
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        bytes32 guessHash = keccak256(abi.encodePacked("correct_answer"));
        vm.startPrank(user1);
        vaultis.submitGuess(1, guessHash);
        vm.stopPrank();

        vm.startPrank(user1);
        vaultis.revealGuess(1, "correct_answer");
        vm.expectRevert("Revealed guess does not match provided answer");
        vaultis.solveRiddleAndClaim("wrong_answer");
        vm.stopPrank();
    }

    function testSolveRiddleAndClaimAlreadyClaimedFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vaultis.setRevealDelay(0); // No delay for testing
        (bool success, ) = address(vaultis).call{value: prizeAmount}("");
        require(success);
        mockERC20.mint(user1, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        bytes32 guessHash = keccak256(abi.encodePacked("correct_answer"));
        vm.startPrank(user1);
        vaultis.submitGuess(1, guessHash);
        vm.stopPrank();

        vm.startPrank(user1);
        vaultis.revealGuess(1, "correct_answer");
        vaultis.solveRiddleAndClaim("correct_answer");
        vm.expectRevert("Already claimed");
        vaultis.solveRiddleAndClaim("correct_answer"); // Try to claim again
        vm.stopPrank();
    }

    function testOwnerWithdrawRevertsWhenPoolInsufficient() public {
        // Deposit ETH into the contract via the public deposit function
        // This increases contract balance but not ethPrizePool
        vm.startPrank(user1);
        vaultis.deposit{value: 1 ether}();
        vm.stopPrank();

        // Owner attempts to withdraw but ethPrizePool is insufficient
        vm.expectRevert("Insufficient ETH prize pool");
        vm.startPrank(user1); // owner is user1
        vaultis.ownerWithdraw(2 ether);
        vm.stopPrank();
    }

    function testEnterGameWithEntryFeeERC20Success() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 1 ether;
        uint256 entryFee = vaultis.ENTRY_FEE();

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        mockERC20.mint(user2, entryFee);
        vm.startPrank(user2);
        mockERC20.approve(address(vaultis), entryFee);
        vaultis.enterGame(1);
        vm.stopPrank();

        assertTrue(vaultis.hasParticipated(1, user2));
        assertEq(mockERC20.balanceOf(address(vaultis)), entryFee);
        assertEq(mockERC20.balanceOf(user2), 0);
    }

    function testEnterGameWithEntryFeeERC20FeeOnTransferFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 1 ether;
        uint256 entryFee = vaultis.ENTRY_FEE();

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20FeeOnTransfer));
        vm.stopPrank();

        mockERC20FeeOnTransfer.mint(user2, entryFee);
        vm.startPrank(user2);
        mockERC20FeeOnTransfer.approve(address(vaultis), entryFee);
        vm.expectRevert("Entry fee mismatch (FOT not supported)");
        vaultis.enterGame(1);
        vm.stopPrank();
    }

    function testPurchaseRetrySuccess() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        // User2 enters the game
        vm.startPrank(user2);
        mockERC20.mint(user2, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        // User2 purchases a retry
        mockERC20.mint(user2, vaultis.RETRY_COST());
        vm.startPrank(user2);
        mockERC20.approve(address(vaultis), vaultis.RETRY_COST());
        vaultis.purchaseRetry(1);
        vm.stopPrank();

        assertEq(vaultis.retries(user2), 1, "User2 should have 1 retry");
        assertEq(mockERC20.balanceOf(address(vaultis)), vaultis.ENTRY_FEE() + vaultis.RETRY_COST(), "Vaultis should hold entry fee + retry cost");
        assertEq(mockERC20.balanceOf(user2), 0, "User2 should have 0 retry tokens left");
    }

    function testPurchaseRetryMaxRetriesFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        // User2 enters the game
        vm.startPrank(user2);
        mockERC20.mint(user2, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        vm.stopPrank();

        // User2 purchases MAX_RETRIES
        for (uint256 i = 0; i < vaultis.MAX_RETRIES(); i++) {
            mockERC20.mint(user2, vaultis.RETRY_COST());
            vm.startPrank(user2);
            mockERC20.approve(address(vaultis), vaultis.RETRY_COST());
            vaultis.purchaseRetry(1);
            vm.stopPrank();
        }

        assertEq(vaultis.retries(user2), vaultis.MAX_RETRIES(), "User2 should have MAX_RETRIES");

        // User2 tries to purchase one more retry, which should fail
        mockERC20.mint(user2, vaultis.RETRY_COST());
        vm.startPrank(user2);
        mockERC20.approve(address(vaultis), vaultis.RETRY_COST());
        vm.expectRevert("Max retries reached");
        vaultis.purchaseRetry(1);
        vm.stopPrank();
    }



    function testSetRiddleRevertsWithNonEmptyPrizePools() public {
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        uint256 prizeAmount = 1 ether;

        // Set initial riddle and fund ETH prize pool
        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        (bool success, ) = address(vaultis).call{value: prizeAmount}(""); // Fund the ETH prize pool
        require(success);
        vm.stopPrank();

        assertEq(vaultis.ethPrizePool(), prizeAmount);

        // Attempt to set a new riddle while ETH prize pool is not empty
        vm.expectRevert("Must withdraw ETH prize pool before new riddle");
        vm.startPrank(user1);
        vaultis.setRiddle(2, keccak256(abi.encode("new_answer")), Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        // Withdraw ETH prize pool
        vm.startPrank(user1);
        vaultis.ownerWithdraw(prizeAmount);
        vm.stopPrank();

        assertEq(vaultis.ethPrizePool(), 0);

        // Set initial riddle and fund ERC20 prize pool
        vm.startPrank(user1);
        vaultis.setRiddle(3, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount, address(mockERC20));
        mockERC20.mint(user1, prizeAmount);
        mockERC20.approve(address(vaultis), prizeAmount);
        vaultis.fundTokenPrizePool(prizeAmount);
        vm.stopPrank();

        assertEq(vaultis.tokenPrizePool(), prizeAmount);

        // Withdraw token prize pool
        vm.startPrank(user1);
        vaultis.ownerWithdrawTokens(prizeAmount);
        vm.stopPrank();

        assertEq(vaultis.tokenPrizePool(), 0);

        // Now setting a new riddle should succeed
        vm.startPrank(user1);
        vaultis.setRiddle(4, keccak256(abi.encode("another_answer")), Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount, address(mockERC20));
        vm.stopPrank();

        assertEq(vaultis.currentRiddleId(), 4);
    }

    function testOwnerWithdrawTokensSuccess() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 100;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount, address(mockERC20));
        vm.stopPrank();

        mockERC20.mint(user1, prizeAmount);
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), prizeAmount);
        vaultis.fundTokenPrizePool(prizeAmount);
        vm.stopPrank();

        assertEq(vaultis.tokenPrizePool(), prizeAmount);
        assertEq(mockERC20.balanceOf(address(vaultis)), prizeAmount);
        uint256 initialOwnerBalance = mockERC20.balanceOf(user1);

        vm.startPrank(user1);
        vaultis.ownerWithdrawTokens(prizeAmount);
        vm.stopPrank();

        assertEq(vaultis.tokenPrizePool(), 0);
        assertEq(mockERC20.balanceOf(address(vaultis)), 0);
        assertEq(mockERC20.balanceOf(user1), initialOwnerBalance + prizeAmount);
    }

    function testOwnerWithdrawTokensInsufficientPoolFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 100;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount, address(mockERC20));
        vm.stopPrank();

        mockERC20.mint(user1, 50);
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), 50);
        vaultis.fundTokenPrizePool(50);
        vm.stopPrank();

        assertEq(vaultis.tokenPrizePool(), 50);

        vm.expectRevert("Insufficient token prize pool");
        vm.startPrank(user1);
        vaultis.ownerWithdrawTokens(100);
        vm.stopPrank();
    }

    function testOwnerWithdrawTokensNonOwnerFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));
        uint256 prizeAmount = 100;

        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount, address(mockERC20));
        vm.stopPrank();

        mockERC20.mint(user1, prizeAmount);
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), prizeAmount);
        vaultis.fundTokenPrizePool(prizeAmount);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user2));
        vm.startPrank(user2);
        vaultis.ownerWithdrawTokens(prizeAmount);
        vm.stopPrank();
    }

    function testRetriesResetOnNewRiddleEntry() public {
        bytes32 answerHash1 = keccak256(abi.encodePacked("answer1"));
        bytes32 answerHash2 = keccak256(abi.encodePacked("answer2"));
        uint256 prizeAmount = 1 ether;

        // Riddle 1 setup
        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash1, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        // User2 enters riddle 1 and purchases a retry
        vm.startPrank(user2);
        mockERC20.mint(user2, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        mockERC20.mint(user2, vaultis.RETRY_COST());
        mockERC20.approve(address(vaultis), vaultis.RETRY_COST());
        vaultis.purchaseRetry(1);
        vm.stopPrank();

        assertEq(vaultis.retries(user2), 1, "User2 should have 1 retry for riddle 1");

        // Riddle 2 setup
        vm.startPrank(user1);
        vaultis.setRiddle(2, answerHash2, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        // User2 enters riddle 2
        vm.startPrank(user2);
        mockERC20.mint(user2, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(2);
        vm.stopPrank();

        assertEq(vaultis.retries(user2), 0, "User2 retries should be reset to 0 for riddle 2");
    }

    function testCannotUseRetriesFromOtherRiddleInEnterGame() public {
        bytes32 answerHash1 = keccak256(abi.encodePacked("answer1"));
        bytes32 answerHash2 = keccak256(abi.encodePacked("answer2"));
        uint256 prizeAmount = 1 ether;

        // Riddle 1 setup
        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash1, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        // User2 enters riddle 1 and purchases a retry
        vm.startPrank(user2);
        mockERC20.mint(user2, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        mockERC20.mint(user2, vaultis.RETRY_COST());
        mockERC20.approve(address(vaultis), vaultis.RETRY_COST());
        vaultis.purchaseRetry(1);
        vm.stopPrank();

        assertEq(vaultis.retries(user2), 1, "User2 should have 1 retry for riddle 1");

        // Riddle 2 setup
        vm.startPrank(user1);
        vaultis.setRiddle(2, answerHash2, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        // User2 tries to enter riddle 2 without resetting retries (should reset automatically)
        vm.startPrank(user2);
        mockERC20.mint(user2, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(2); // This should trigger the retry reset
        vm.stopPrank();

        assertEq(vaultis.retries(user2), 0, "Retries should be 0 after entering a new riddle");

        // Now, if user2 tries to submit a guess for riddle 2 and expects to use a retry, it should fail
        bytes32 guessHash = keccak256(abi.encodePacked("my_guess"));
        vm.startPrank(user2);
        vaultis.submitGuess(2, guessHash); // First guess for riddle 2, should succeed
        vm.expectRevert("No retries available");
        vaultis.submitGuess(2, guessHash); // Second guess for riddle 2, should fail as retries are 0
        vm.stopPrank();
    }

    function testCannotUseRetriesFromOtherRiddleInPurchaseRetry() public {
        bytes32 answerHash1 = keccak256(abi.encodePacked("answer1"));
        bytes32 answerHash2 = keccak256(abi.encodePacked("answer2"));
        uint256 prizeAmount = 1 ether;

        // Riddle 1 setup
        vm.startPrank(user1);
        vaultis.setRiddle(1, answerHash1, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        // User2 enters riddle 1 and purchases a retry
        vm.startPrank(user2);
        mockERC20.mint(user2, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(1);
        mockERC20.mint(user2, vaultis.RETRY_COST());
        mockERC20.approve(address(vaultis), vaultis.RETRY_COST());
        vaultis.purchaseRetry(1);
        vm.stopPrank();

        assertEq(vaultis.retries(user2), 1, "User2 should have 1 retry for riddle 1");

        // Riddle 2 setup
        vm.startPrank(user1);
        vaultis.setRiddle(2, answerHash2, Vaultis.PrizeType.ETH, address(0), prizeAmount, address(mockERC20));
        vm.stopPrank();

        // User2 enters riddle 2
        vm.startPrank(user2);
        mockERC20.mint(user2, vaultis.ENTRY_FEE());
        mockERC20.approve(address(vaultis), vaultis.ENTRY_FEE());
        vaultis.enterGame(2);
        vm.stopPrank();

        // User2 tries to purchase a retry for riddle 2, which should reset retries first
        vm.startPrank(user2);
        mockERC20.mint(user2, vaultis.RETRY_COST());
        mockERC20.approve(address(vaultis), vaultis.RETRY_COST());
        vaultis.purchaseRetry(2); // This should trigger the retry reset and then purchase for riddle 2
        vm.stopPrank();

        assertEq(vaultis.retries(user2), 1, "User2 should have 1 retry for riddle 2 after reset and purchase");
    }
}
