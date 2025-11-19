// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Vaultis} from "./Vaultis.sol";

/// @title ReentrancyAttack
/// @notice A contract designed to demonstrate and test reentrancy vulnerabilities in the Vaultis contract.
/// @dev This contract is intended for testing purposes only. It implements a controlled reentrancy attack
/// @dev to exercise the withdrawal behavior of the Vaultis contract, specifically targeting `ownerWithdraw`.
/// @dev For the attack to be successful, this contract must be set as the owner of the target Vaultis instance.
contract ReentrancyAttack {
    /// @notice The instance of the Vaultis contract that this contract will attempt to attack.
    Vaultis public vaultis;
    /// @notice The owner of this ReentrancyAttack contract.
    address public owner;

    /// @notice Constructs the ReentrancyAttack contract.
    /// @dev Initializes the target Vaultis contract address.
    /// @param _vaultisAddress The address of the Vaultis contract to attack.
    constructor(address payable _vaultisAddress) {
        vaultis = Vaultis(_vaultisAddress);
        owner = msg.sender;
    }

    /// @notice Initiates a controlled reentrancy attack on the Vaultis contract's `ownerWithdraw` function.
    /// @dev This function assumes the ReentrancyAttack contract is the owner of the Vaultis instance.
    /// @dev It attempts to recursively withdraw funds up to a specified maximum recursion depth.
    /// @dev The `ownerWithdraw` function in Vaultis uses a gas limit (200,000) for external calls,
    /// @dev which will naturally limit the depth of reentrancy.
    /// @param amount The amount of ETH to withdraw in each reentrant call.
    /// @param maxRecursions The maximum number of recursive calls to attempt.
    function attackStart(uint256 amount, uint256 maxRecursions) public payable {
        require(msg.sender == owner, "Only owner can start attack");
        require(address(this).balance >= amount, "Insufficient balance for initial withdraw");

        if (maxRecursions == 0) {
            return;
        }

        // Perform the initial withdrawal, which will trigger the receive function
        // if the call is successful and sends ETH back.
        vaultis.ownerWithdraw(amount);

        // The receive function will handle subsequent recursive calls up to maxRecursions.
        // The actual recursion depth will be limited by Vaultis's gas stipend for external calls.
    }

    /// @notice Fallback function to receive Ether.
    /// @dev This function is called when Ether is sent to the contract.
    /// @dev It only accepts ETH and does not perform any external state-changing calls directly.
    /// @dev This prevents uncontrolled reentrancy from the receive function itself.
    receive() external payable {
        // Optionally, you could increment a counter here for testing purposes.
        // No external calls are made from receive() to prevent uncontrolled reentrancy.
    }

    /// @notice Allows the owner to withdraw any ETH held by this contract.
    /// @dev This is a safety function to recover funds from the attack contract.
    function withdrawEther() public {
        require(msg.sender == owner, "Only owner can withdraw");
        payable(owner).transfer(address(this).balance);
    }
}

