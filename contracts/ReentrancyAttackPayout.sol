// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Vaultis} from "./Vaultis.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ReentrancyAttackPayout
/// @notice A contract designed to demonstrate and test reentrancy vulnerabilities in the Vaultis contract's payout function.
/// @dev This contract is intended for testing purposes only. It implements a controlled reentrancy attack
/// @dev to exercise the payout behavior of the Vaultis contract, specifically targeting `payout`.
contract ReentrancyAttackPayout {
    /// @notice The instance of the Vaultis contract that this contract will attempt to attack.
    Vaultis public vaultis;
    /// @notice The ERC20 token used for prizes in Vaultis.
    IERC20 public prizeToken;
    /// @notice The owner of this ReentrancyAttackPayout contract.
    address public owner;

    uint256 public immutable riddleId;
    uint256 public payoutAmount;
    uint256 public currentRecursion;
    uint256 public maxRecursions;

    /// @notice Constructs the ReentrancyAttackPayout contract.
    /// @dev Initializes the target Vaultis contract address, prize token, and other parameters.
    /// @param _vaultisAddress The address of the Vaultis contract to attack.
    /// @param _prizeTokenAddress The address of the ERC20 token used as a prize.
    /// @param _riddleId The ID of the riddle this contract will try to claim for.
    constructor(address payable _vaultisAddress, address _prizeTokenAddress, uint256 _riddleId) {
        vaultis = Vaultis(_vaultisAddress);
        prizeToken = IERC20(_prizeTokenAddress);
        riddleId = _riddleId;
        owner = msg.sender;
    }

    /// @notice Initiates a controlled reentrancy attack on the Vaultis contract's `payout` function.
    /// @dev This function is intended to be called by the Vaultis owner.
    /// @dev It attempts to recursively call `payout` within its `receive` function.
    /// @param _payoutAmount The amount of prize to expect in each successful payout.
    /// @param _maxRecursions The maximum number of recursive calls to attempt.
    function startPayoutAttack(uint256 _payoutAmount, uint256 _maxRecursions) public returns (bool) {
        require(msg.sender == owner, "Only owner can start attack");
        payoutAmount = _payoutAmount;
        maxRecursions = _maxRecursions;
        currentRecursion = 0;

        address[] memory winners = new address[](1);
        winners[0] = address(this);

        bool success = false;
        try vaultis.payout(riddleId, winners) {
            success = true;
        } catch Error(string memory reason) {
            // Expected reentrancy revert or other reverts from payout
        } catch {
            // Catch all other revert types
        }
        return success;
    }

    /// @notice Fallback function to receive Ether.
    /// @dev This function is called when Ether is sent to the contract (e.g., during payout).
    /// @dev It attempts to reenter the `payout` function if `maxRecursions` has not been reached.
    receive() external payable {
        if (currentRecursion < maxRecursions) {
            currentRecursion++;
            address[] memory winners = new address[](1);
            winners[0] = address(this);
            // This reentrant call should be blocked by Vaultis's nonReentrant modifier
            vaultis.payout(riddleId, winners);
        }
    }

    /// @notice Allows the owner to withdraw any ETH held by this contract.
    function withdrawEther() public {
        require(msg.sender == owner, "Only owner can withdraw");
        payable(owner).transfer(address(this).balance);
    }

    /// @notice Allows the owner to withdraw any ERC20 tokens held by this contract.
    function withdrawTokens(address tokenAddress) public {
        require(msg.sender == owner, "Only owner can withdraw");
        IERC20 token = IERC20(tokenAddress);
        token.transfer(owner, token.balanceOf(address(this)));
    }
}
