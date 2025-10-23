// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Vaultis is Ownable, ReentrancyGuard {
    constructor(address initialOwner) Ownable(initialOwner) {
    }
    mapping(address => uint256) public balances;
    uint256 public currentRiddleId;
    uint256 public prizePool;
    IERC20 public prizeToken;
    mapping(uint256 => mapping(address => bool)) public hasParticipated;
    bytes32 private sAnswerHash;

    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event OwnerWithdrawal(address indexed owner, uint256 amount);
    event RiddleSet(uint256 indexed riddleId, bytes32 answerHash, IERC20 prizeToken);


    function deposit() public payable nonReentrant {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        require(!hasParticipated[currentRiddleId][msg.sender], "Already participated in this riddle");
        balances[msg.sender] += msg.value;
        hasParticipated[currentRiddleId][msg.sender] = true;
        addToPrizePool();
        emit Deposit(msg.sender, msg.value);
    }

    function addToPrizePool() internal {
        prizePool += msg.value;
    }

    function withdraw(uint256 _amount) public nonReentrant {
        require(_amount > 0, "Withdrawal amount must be greater than zero");
        require(balances[msg.sender] >= _amount, "Insufficient balance");

        balances[msg.sender] -= _amount;
        (bool success,) = msg.sender.call{value: _amount}("");
        require(success, "Withdrawal failed");
        emit Withdrawal(msg.sender, _amount);
    }

    function ownerWithdraw(uint256 _amount) public onlyOwner nonReentrant {
        require(_amount > 0, "Owner withdrawal amount must be greater than zero");
                require(address(this).balance >= _amount, "Insufficient contract balance");
        
                                (bool success, ) = owner().call{value: _amount, gas: 200000}("");
                                require(success, "Owner withdrawal failed");
                                emit OwnerWithdrawal(owner(), _amount);    }



    function resetPrizePool() internal {
        prizePool = 0;
    }

    /**
     * @dev Sets a new riddle.
     * The `_riddleId` must be greater than the `currentRiddleId` to ensure monotonic progression and prevent replay attacks.
     * The `prizePool` is reset to 0 for each new riddle.
     * @param _riddleId The unique identifier for the new riddle.
     * @param _answerHash The hash of the answer to the new riddle.
     * @param _prizeToken The address of the ERC20 token used as prize for the new riddle.
     */
    function setRiddle(uint256 _riddleId, bytes32 _answerHash, IERC20 _prizeToken) public onlyOwner {
        require(_riddleId > 0, "Riddle ID cannot be zero");
        require(_riddleId > currentRiddleId, "Riddle ID must be greater than current");
        require(address(_prizeToken) != address(0), "Prize token address cannot be zero");

        currentRiddleId = _riddleId;
        sAnswerHash = _answerHash;
        prizeToken = _prizeToken;
        prizePool = 0;
        emit RiddleSet(_riddleId, _answerHash, _prizeToken);
    }

    function getAnswerHash() public view returns (bytes32) {
        return sAnswerHash;
    }

    function getPrizeToken() public view returns (address) {
        return address(prizeToken);
    }
}
