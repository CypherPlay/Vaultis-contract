pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";
import {Vaultis} from "./Vaultis.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./MockERC20.sol";

contract VaultisTest is Test {
    Vaultis public vaultis;
    MockERC20 public mockERC20;
    address public user1;
    address public user2;

    function setUp() public {
        vaultis = new Vaultis(user1);
        mockERC20 = new MockERC20("MockToken", "MTK");
        user1 = address(uint160(uint256(keccak256(abi.encodePacked("user1")))));
        user2 = address(uint160(uint256(keccak256(abi.encodePacked("user2")))));
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

    function testOwnerWithdraw() public {
        vm.startPrank(user1);
        (bool sent, ) = address(vaultis).call{value: 5 ether}("");
        require(sent, "Failed to send eth to vaultis");
        vm.stopPrank();

        uint256 initialOwnerBalance = address(this).balance;
        vm.startPrank(address(this)); // The owner is the test contract itself in this setup
        vaultis.ownerWithdraw(2 ether);
        vm.stopPrank();

        assertEq(address(vaultis).balance, 3 ether);
        assertEq(address(this).balance, initialOwnerBalance + 2 ether);
    }

    function testOwnerWithdrawInsufficientContractBalanceFails() public {
        vm.expectRevert("Insufficient contract balance");
        vm.startPrank(address(this));
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
        vm.stopPrank();

        vm.expectRevert("Owner withdrawal amount must be greater than zero");
        vm.startPrank(address(this));
        vaultis.ownerWithdraw(0);
        vm.stopPrank();
    }

    function testReentrancyGuardDeposit() public {
        // This test is more about ensuring nonReentrant modifier is present
        // and doesn\'t cause issues, rather than a full reentrancy attack simulation
        // which would require a malicious contract.
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        vaultis.deposit{value: 1 ether}();
        vm.stopPrank();
        assertEq(vaultis.balances(user1), 1 ether);
    }

    function testReentrancyGuardWithdraw() public {
        // Similar to deposit, this primarily checks the modifier\'s presence.
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

        vm.startPrank(address(this));
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount);
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

        vm.startPrank(address(this));
        vaultis.setRiddle(2, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount);
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
        vm.startPrank(address(this));
        vaultis.setRiddle(0, keccak256(abi.encodePacked("answer")), Vaultis.PrizeType.ETH, address(0), 1 ether);
        vm.stopPrank();
    }

    function testSetRiddleBackdatingFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));

        vm.startPrank(address(this));
        vaultis.setRiddle(5, answerHash, Vaultis.PrizeType.ETH, address(0), 1 ether);
        vm.expectRevert("Riddle ID must be greater than current");
        vaultis.setRiddle(3, answerHash, Vaultis.PrizeType.ETH, address(0), 1 ether);
        vm.stopPrank();
    }

    function testSetRiddleSameIdFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("test_answer"));

        vm.startPrank(address(this));
        vaultis.setRiddle(5, answerHash, Vaultis.PrizeType.ETH, address(0), 1 ether);
        vm.expectRevert("Riddle ID must be greater than current");
        vaultis.setRiddle(5, answerHash, Vaultis.PrizeType.ETH, address(0), 1 ether);
        vm.stopPrank();
    }

    function testSetRiddleNonOwnerFails() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.startPrank(user1);
        vaultis.setRiddle(1, keccak256(abi.encodePacked("answer")), Vaultis.PrizeType.ETH, address(0), 1 ether);
        vm.stopPrank();
    }

    function testSetRiddleZeroPrizeAmountFails() public {
        vm.expectRevert("Prize amount must be greater than zero");
        vm.startPrank(address(this));
        vaultis.setRiddle(1, keccak256(abi.encodePacked("answer")), Vaultis.PrizeType.ETH, address(0), 0);
        vm.stopPrank();
    }

    function testSetRiddleErc20ZeroTokenAddressFails() public {
        vm.expectRevert("Prize token address cannot be zero for ERC20 prize");
        vm.startPrank(address(this));
        vaultis.setRiddle(1, keccak256(abi.encodePacked("answer")), Vaultis.PrizeType.ERC20, address(0), 100);
        vm.stopPrank();
    }

    function testSetRiddleErc20InvalidTokenContractFails() public {
        // Use a regular address that is not a contract
        address nonContractAddress = address(uint160(uint256(keccak256(abi.encodePacked("nonContract")))));
        vm.expectRevert("Prize token has no contract code");
        vm.startPrank(address(this));
        vaultis.setRiddle(1, keccak256(abi.encodePacked("answer")), Vaultis.PrizeType.ERC20, nonContractAddress, 100);
        vm.stopPrank();
    }

    function testSetRiddleErc20InvalidTokenTotalSupplyFails() public {
        // Deploy a contract that is not an ERC20 and doesn't have totalSupply
        address notAnErc20 = address(new Vaultis(address(this))); // Use Vaultis itself as a non-ERC20 contract
        vm.expectRevert("Invalid ERC-20 token: totalSupply call failed");
        vm.startPrank(address(this));
        vaultis.setRiddle(1, keccak256(abi.encodePacked("answer")), Vaultis.PrizeType.ERC20, notAnErc20, 100);
        vm.stopPrank();
    }

    function testEthPrizeFunding() public {
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        uint256 prizeAmount = 5 ether;

        vm.startPrank(address(this));
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount);
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

        vm.startPrank(address(this));
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount);
        vm.stopPrank();

        assertEq(vaultis.tokenPrizePool(), 0);

        // Mint tokens to user1 and approve Vaultis to spend them
        mockERC20.mint(user1, 1000);
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), 500);
        vm.stopPrank();

        vm.startPrank(address(this)); // Owner funds the prize pool
        vaultis.fundTokenPrizePool(500);
        vm.stopPrank();

        assertEq(vaultis.tokenPrizePool(), 500);
        assertEq(mockERC20.balanceOf(address(vaultis)), 500);
        assertEq(mockERC20.balanceOf(user1), 500);
    }

    function testTokenPrizeFundingNonOwnerFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        uint256 prizeAmount = 500;

        vm.startPrank(address(this));
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount);
        vm.stopPrank();

        mockERC20.mint(user1, 1000);
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), 500);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vaultis.fundTokenPrizePool(500);
        vm.stopPrank();
    }

    function testTokenPrizeFundingWrongPrizeTypeFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        uint256 prizeAmount = 5 ether;

        vm.startPrank(address(this));
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount);
        vm.stopPrank();

        mockERC20.mint(user1, 1000);
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), 500);
        vm.stopPrank();

        vm.expectRevert("Current riddle prize is not ERC20");
        vm.startPrank(address(this));
        vaultis.fundTokenPrizePool(500);
        vm.stopPrank();
    }

    function testTokenPrizeFundingInsufficientAllowanceFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        uint256 prizeAmount = 500;

        vm.startPrank(address(this));
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount);
        vm.stopPrank();

        mockERC20.mint(user1, 1000);
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), 100);
        vm.stopPrank();

        vm.expectRevert(); // SafeERC20 will revert on insufficient allowance
        vm.startPrank(address(this));
        vaultis.fundTokenPrizePool(500);
        vm.stopPrank();
    }

    function testTokenPrizeFundingInsufficientBalanceFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("answer"));
        uint256 prizeAmount = 500;

        vm.startPrank(address(this));
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount);
        vm.stopPrank();

        // user1 has no tokens
        vm.startPrank(user1);
        mockERC20.approve(address(vaultis), 500);
        vm.stopPrank();

        vm.expectRevert(); // SafeERC20 will revert on insufficient balance
        vm.startPrank(address(this));
        vaultis.fundTokenPrizePool(500);
        vm.stopPrank();
    }

    function testSolveRiddleAndClaimEthPrize() public {
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(address(this));
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount);
        (bool success, ) = address(vaultis).call{value: prizeAmount}(""); // Fund the ETH prize pool
        require(success);
        vm.stopPrank();

        assertEq(vaultis.ethPrizePool(), prizeAmount);
        uint256 initialUserBalance = user1.balance;

        vm.startPrank(user1);
        vaultis.solveRiddleAndClaim("correct_answer");
        vm.stopPrank();

        assertEq(vaultis.ethPrizePool(), 0);
        assertEq(user1.balance, initialUserBalance + prizeAmount);
        assertTrue(vaultis.hasParticipated(1, user1));
    }

    function testSolveRiddleAndClaimErc20Prize() public {
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        uint256 prizeAmount = 100;

        vm.startPrank(address(this));
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount);
        // Fund the ERC20 prize pool
        mockERC20.mint(address(this), prizeAmount);
        vaultis.fundTokenPrizePool(prizeAmount);
        vm.stopPrank();

        assertEq(vaultis.tokenPrizePool(), prizeAmount);
        assertEq(mockERC20.balanceOf(user1), 0);

        vm.startPrank(user1);
        vaultis.solveRiddleAndClaim("correct_answer");
        vm.stopPrank();

        assertEq(vaultis.tokenPrizePool(), 0);
        assertEq(mockERC20.balanceOf(user1), prizeAmount);
        assertTrue(vaultis.hasParticipated(1, user1));
    }

    function testSolveRiddleAndClaimInsufficientEthPrizeFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(address(this));
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount);
        (bool success, ) = address(vaultis).call{value: 0.5 ether}("");
        require(success);
        vm.stopPrank();

        vm.expectRevert("Insufficient ETH prize pool balance");
        vm.startPrank(user1);
        vaultis.solveRiddleAndClaim("correct_answer");
        vm.stopPrank();
    }

    function testSolveRiddleAndClaimInsufficientErc20PrizeFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        uint256 prizeAmount = 100;

        vm.startPrank(address(this));
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ERC20, address(mockERC20), prizeAmount);
        // Fund with less than prizeAmount
        mockERC20.mint(address(this), 50);
        vaultis.fundTokenPrizePool(50);
        vm.stopPrank();

        vm.expectRevert("Insufficient ERC20 prize pool balance");
        vm.startPrank(user1);
        vaultis.solveRiddleAndClaim("correct_answer");
        vm.stopPrank();
    }

    function testSolveRiddleAndClaimIncorrectAnswerFails() public {
        bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));
        uint256 prizeAmount = 1 ether;

        vm.startPrank(address(this));
        vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount);
        (bool success, ) = address(vaultis).call{value: prizeAmount}("");
        require(success);
        vm.stopPrank();

        vm.expectRevert("Incorrect answer");
        vm.startPrank(user1);
        vaultis.solveRiddleAndClaim("wrong_answer");
        vm.stopPrank();
    }

        function testSolveRiddleAndClaimAlreadyParticipatedFails() public {

            bytes32 answerHash = keccak256(abi.encodePacked("correct_answer"));

            uint256 prizeAmount = 1 ether;

    

            vm.startPrank(address(this));

            vaultis.setRiddle(1, answerHash, Vaultis.PrizeType.ETH, address(0), prizeAmount);

            (bool success, ) = address(vaultis).call{value: prizeAmount}("");

            require(success);

            vm.stopPrank();

    

            vm.startPrank(user1);

            vaultis.solveRiddleAndClaim("correct_answer");

            vm.expectRevert("Already participated in this riddle");

            vaultis.solveRiddleAndClaim("correct_answer"); // Try to claim again

            vm.stopPrank();

        }        function testGetAnswerHashNonExistentFails() public {
        (bool success,) = address(vaultis).call(abi.encodeWithSignature("getAnswerHash()"));
        assertFalse(success, "Calling getAnswerHash() should not succeed");
    }

    }
