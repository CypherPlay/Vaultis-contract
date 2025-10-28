// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Vaultis is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    constructor(address initialOwner) Ownable(initialOwner) {
        entryFeeToken = IERC20(address(0));
    }
    mapping(address => uint256) public balances;
    uint256 public currentRiddleId;
    uint256 public ethPrizePool;
    IERC20 public prizeToken;
    uint256 public tokenPrizePool;
    uint256 public prizeAmount;
    uint256 public entryFeeAmount;
    IERC20 public entryFeeToken;

    enum PrizeType { ETH, ERC20 }
    PrizeType public prizeType;

    // Track entry and claim independently to avoid blocking legitimate claims
    mapping(uint256 => mapping(address => bool)) public hasParticipated; // entered
    mapping(uint256 => mapping(address => bool)) public hasClaimed;      // claimed
    bytes32 internal sAnswerHash;

    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event OwnerWithdrawal(address indexed owner, uint256 amount);
    event RiddleSet(uint256 indexed riddleId, bytes32 answerHash, PrizeType prizeType, address prizeTokenAddress, uint256 prizeAmount, uint256 entryFeeAmount, address entryFeeTokenAddress);
    event PrizeDistributed(address indexed winner, uint256 amount, PrizeType prizeType);
    event PrizeFunded(address indexed funder, uint256 amount, PrizeType prizeType);
    event EthReceived(address indexed sender, uint256 amount);
    event EntryFeeCollected(address indexed player, address indexed token, uint256 amount, uint256 indexed riddleId);


    function deposit() public payable nonReentrant {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    receive() external payable {
        require(msg.value > 0, "ETH amount must be greater than zero");
        ethPrizePool += msg.value;
        emit EthReceived(msg.sender, msg.value);
    }

    function fundTokenPrizePool(uint256 _amount) public onlyOwner nonReentrant {
        require(_amount > 0, "Amount must be greater than zero");
        require(prizeType == PrizeType.ERC20, "Current riddle prize is not ERC20");
        require(address(prizeToken) != address(0), "Prize token not set");
        
        prizeToken.safeTransferFrom(msg.sender, address(this), _amount);
        tokenPrizePool += _amount;
        emit PrizeFunded(msg.sender, _amount, PrizeType.ERC20);
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
        require(ethPrizePool >= _amount, "Insufficient ETH prize pool");
        
        (bool success, ) = owner().call{value: _amount, gas: 200000}("");
        require(success, "Owner withdrawal failed");
        ethPrizePool -= _amount;
        emit OwnerWithdrawal(owner(), _amount);
    }

    function _distributePrize(address _winner, uint256 _amount) internal {
        require(_winner != address(0), "Winner address cannot be zero");
        require(_amount > 0, "Prize amount must be greater than zero");

        if (prizeType == PrizeType.ETH) {
            require(ethPrizePool >= _amount, "Insufficient ETH prize pool balance");
            require(address(this).balance >= _amount, "Insufficient contract ETH balance");
            ethPrizePool -= _amount;
            (bool success, ) = _winner.call{value: _amount}("");
            require(success, "ETH transfer failed");
        } else if (prizeType == PrizeType.ERC20) {
            require(address(prizeToken) != address(0), "Prize token not set");
            require(tokenPrizePool >= _amount, "Insufficient ERC20 prize pool balance");
            tokenPrizePool -= _amount;
            prizeToken.safeTransfer(_winner, _amount);
        }
        emit PrizeDistributed(_winner, _amount, prizeType);
    }

    function solveRiddleAndClaim(string calldata _answer) public nonReentrant {
        require(currentRiddleId > 0, "No active riddle");
        require(hasParticipated[currentRiddleId][msg.sender], "Must enter the game first");
        require(!hasClaimed[currentRiddleId][msg.sender], "Already claimed");
        require(keccak256(abi.encodePacked(_answer)) == sAnswerHash, "Incorrect answer");

        hasClaimed[currentRiddleId][msg.sender] = true; // mark claimed
        _distributePrize(msg.sender, prizeAmount);
    }

    /**
     * @notice Allows a player to enter the game for a specific riddle.
     * @dev This function handles the collection of entry fees. It requires an exact transfer amount,
     *      meaning fee-on-transfer (FOT) tokens are NOT supported.
     * @param _riddleId The ID of the riddle the player wishes to enter.
     */
    function enterGame(uint256 _riddleId) public nonReentrant {
        require(_riddleId == currentRiddleId, "Not the active riddle ID");
        require(currentRiddleId > 0, "No active riddle");
        require(!hasParticipated[_riddleId][msg.sender], "Already participated in this riddle");
        
        if (entryFeeAmount > 0) {
            IERC20 token = entryFeeToken;
            require(address(token) != address(0), "Entry fee token not set");
            uint256 beforeBal = token.balanceOf(address(this));
            token.safeTransferFrom(msg.sender, address(this), entryFeeAmount);
            uint256 received = token.balanceOf(address(this)) - beforeBal;
            require(received == entryFeeAmount, "Entry fee mismatch (FOT not supported)");
            emit EntryFeeCollected(msg.sender, address(token), received, _riddleId);
        }

        hasParticipated[_riddleId][msg.sender] = true; // mark entered
    }

    /**
     * @dev Sets a new riddle.
     * The `_riddleId` must be greater than the `currentRiddleId` to ensure monotonic progression and prevent replay attacks.
     * The `prizePool` is reset to 0 for each new riddle.
     * @param _riddleId The unique identifier for the new riddle.
     * @param _answerHash The hash of the answer to the new riddle.
     * @param _prizeType The type of prize (ETH or ERC20).
     * @param _prizeTokenAddress The address of the ERC20 token if prizeType is ERC20, otherwise address(0).
     * @param _prizeAmount The amount of the prize.
     * @param _entryFeeAmount The amount of the entry fee.
     * @param _entryFeeTokenAddress The address of the ERC20 token for the entry fee, otherwise address(0).
     */
    function setRiddle(uint256 _riddleId, bytes32 _answerHash, PrizeType _prizeType, address _prizeTokenAddress, uint256 _prizeAmount, uint256 _entryFeeAmount, address _entryFeeTokenAddress) public onlyOwner {
        require(_riddleId > 0, "Riddle ID cannot be zero");
        require(_riddleId > currentRiddleId, "Riddle ID must be greater than current");
        require(_prizeAmount > 0, "Prize amount must be greater than zero");

        if (_prizeType == PrizeType.ERC20) {
            require(_prizeTokenAddress != address(0), "Prize token address cannot be zero for ERC20 prize");
            // Validate the token contract by checking it implements ERC-20
            // Check if the address contains contract bytecode
            require(address(_prizeTokenAddress).code.length > 0, "Prize token has no contract code");
            try IERC20(_prizeTokenAddress).totalSupply() returns (uint256) {
                // Token is valid
            } catch {
                revert("Invalid ERC-20 token: totalSupply call failed");
            }
            prizeToken = IERC20(_prizeTokenAddress);
        } else {
            require(_prizeTokenAddress == address(0), "Prize token address must be zero for ETH prize");
            prizeToken = IERC20(address(0)); // Explicitly set to zero address for ETH prizes
        }

        if (_entryFeeAmount > 0) {
            require(_entryFeeTokenAddress != address(0), "Entry fee token address cannot be zero if entry fee amount is greater than zero");
            require(address(_entryFeeTokenAddress).code.length > 0, "Entry fee token has no contract code");
            try IERC20(_entryFeeTokenAddress).totalSupply() returns (uint256) {
                // Token is valid
            } catch {
                revert("Invalid ERC-20 token for entry fee: totalSupply call failed");
            }
            entryFeeToken = IERC20(_entryFeeTokenAddress);
        } else {
            require(_entryFeeTokenAddress == address(0), "Entry fee token address must be zero if entry fee amount is zero");
            entryFeeToken = IERC20(address(0));
        }

        currentRiddleId = _riddleId;
        sAnswerHash = _answerHash;
        prizeType = _prizeType;
        prizeAmount = _prizeAmount;
        entryFeeAmount = _entryFeeAmount;
        ethPrizePool = 0;
        tokenPrizePool = 0;
        emit RiddleSet(_riddleId, _answerHash, _prizeType, _prizeTokenAddress, _prizeAmount, _entryFeeAmount, _entryFeeTokenAddress);
    }


    function getPrizeToken() public view returns (address) {
        return address(prizeToken);
    }
}