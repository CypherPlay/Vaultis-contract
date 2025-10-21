// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Vaultis is Ownable, ReentrancyGuard {
    constructor(address initialOwner) Ownable(initialOwner) {
    }
    mapping(address => uint256) public balances;
    uint256 public currentRiddleId;
    uint256 public prizePool;
    mapping(uint256 => mapping(address => bool)) public hasParticipated;
    private bytes32 s_answerHash;
    private address s_prizeToken;

    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event OwnerWithdrawal(address indexed owner, uint256 amount);
    event RiddleSet(uint256 indexed riddleId, bytes32 answerHash, address prizeToken);


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

    function setRiddle(uint256 _riddleId, bytes32 _answerHash, address _prizeToken) public onlyOwner {
        require(_riddleId > 0, "Riddle ID cannot be zero");
        require(_prizeToken != address(0), "Prize token address cannot be zero");

        currentRiddleId = _riddleId;
        s_answerHash = _answerHash;
        s_prizeToken = _prizeToken;
        emit RiddleSet(_riddleId, _answerHash, _prizeToken);
    }
}
