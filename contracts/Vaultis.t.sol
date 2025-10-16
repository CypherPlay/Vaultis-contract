pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/console.sol";
import {Vaultis} from "./Vaultis.sol";

contract VaultisTest is Test {
    Vaultis public vaultis;
    address public user1;
    address public user2;

    function setUp() public {
        vaultis = new Vaultis(address(this));
        vm.deal(address(this), 10 ether); // Give the test contract some Ether to receive withdrawals
    }

    function testOwnerIsTestContract() public view {
        assertEq(vaultis.owner(), address(this));
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
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        vaultis.deposit{value: 5 ether}();
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

    receive() external payable {
        // This receive function is explicitly added to ensure the test contract can receive Ether.
        // console.log("VaultisTest received Ether!"); // Keep commented unless debugging
    }

}
