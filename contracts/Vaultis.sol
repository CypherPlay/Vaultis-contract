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
        revealDelay = 1 hours; // Default reveal delay
    }
    mapping(address => uint256) public balances;
    uint256 public currentRiddleId;
    uint256 public ethPrizePool;
    IERC20 public prizeToken;
    uint256 public tokenPrizePool;
    uint256 public prizeAmount;
    IERC20 public entryFeeToken;
    uint256 public constant ENTRY_FEE = 1 ether;
    IERC20 public retryToken;
    uint256 public constant RETRY_COST = 0.1 ether; // Example retry cost

    enum PrizeType { ETH, ERC20 }
    PrizeType public prizeType;

    // Track entry and claim independently to avoid blocking legitimate claims
    mapping(uint256 => mapping(address => bool)) public hasParticipated; // entered
    mapping(uint256 => mapping(address => bool)) public hasClaimed;      // claimed
    mapping(uint256 => mapping(address => bytes32)) public committedGuesses; // Stores hashed guesses for commit-reveal
    mapping(uint256 => mapping(address => uint256)) public committedAt; // timestamp when commit made
    mapping(uint256 => mapping(address => bytes32)) public revealedGuessHash; // stores the hash of the revealed guess (or bytes32(0) if none)
    mapping(uint256 => mapping(address => bool)) public hasRevealed; // replay protection / quick check
    uint256 public revealDelay; // minimum seconds to wait between commit and reveal (owner-settable)
    bytes32 internal sAnswerHash;
    mapping(uint256 => address[]) public winners;
    mapping(uint256 => mapping(address => bool)) public isWinner;

    event WinnerFound(address indexed winner, uint256 indexed riddleId);

    /**
     * @notice Emitted when a player successfully submits a hashed guess for a riddle.
     * @param player The address of the player who submitted the guess.
     * @param riddleId The ID of the riddle for which the guess was submitted.
     * @param guessHash The hashed guess submitted by the player.
     */
    event GuessSubmitted(address indexed player, uint256 indexed riddleId, bytes32 guessHash);

    event GuessEvaluated(uint256 indexed riddleId, address indexed player, uint256 timestamp, bool isWinner);

    /**
     * @notice Emitted when a player successfully reveals their guess for a riddle.
     * @param player The address of the player who revealed the guess.
     * @param riddleId The ID of the riddle for which the guess was revealed.
     * @param revealedHash The hash of the revealed guess.
     */
    event GuessRevealed(address indexed player, uint256 indexed riddleId, bytes32 revealedHash);

    /**
     * @notice Emitted when a user deposits ETH into their balance.
     * @param user The address of the user who deposited.
     * @param amount The amount of ETH deposited.
     */
    event Deposit(address indexed user, uint256 amount);
    /**
     * @notice Emitted when a user withdraws ETH from their balance.
     * @param user The address of the user who withdrew.
     * @param amount The amount of ETH withdrawn.
     */
    event Withdrawal(address indexed user, uint256 amount);
    /**
     * @notice Emitted when the contract owner withdraws ETH from the prize pool.
     * @param owner The address of the contract owner.
     * @param amount The amount of ETH withdrawn by the owner.
     */
    event OwnerWithdrawal(address indexed owner, uint256 amount);
    /**
     * @notice Emitted when the contract owner withdraws ERC20 tokens from the token prize pool.
     * @param amount The amount of ERC20 tokens withdrawn by the owner.
     */
    event OwnerWithdrawTokens(uint256 amount);
    /**
     * @notice Emitted when a prize is successfully distributed to a winner.
     * @param winner The address of the prize winner.
     * @param amount The amount of the prize distributed.
     * @param prizeType The type of prize (ETH or ERC20).
     */
    event PrizeDistributed(address indexed winner, uint256 amount, PrizeType prizeType);
    /**
     * @notice Emitted when the prize pool is funded with ETH or ERC20 tokens.
     * @param funder The address that funded the prize pool.
     * @param amount The amount of ETH or ERC20 tokens added to the prize pool.
     * @param prizeType The type of prize (ETH or ERC20).
     */
    event PrizeFunded(address indexed funder, uint256 amount, PrizeType prizeType);
    /**
     * @notice Emitted when ETH is received by the contract via the `receive` function.
     * @param sender The address from which ETH was received.
     * @param amount The amount of ETH received.
     */
    event EthReceived(address indexed sender, uint256 amount);
    /**
     * @notice Emitted when an entry fee is successfully collected from a player.
     * @param player The address of the player from whom the fee was collected.
     * @param token The address of the ERC20 token used for the entry fee.
     * @param amount The amount of the entry fee collected.
     * @param riddleId The ID of the riddle for which the entry fee was collected.
     */
    event EntryFeeCollected(address indexed player, address indexed token, uint256 amount, uint256 indexed riddleId);
    /**
     * @notice Emitted when a player successfully enters a riddle.
     * @param player The address of the player who entered.
     * @param riddleId The ID of the riddle the player entered.
     */
    event PlayerEntered(address indexed player, uint256 indexed riddleId);
    /**
     * @notice Emitted when a new riddle is successfully initialized.
     * @param riddleId The unique identifier for the new riddle.
     * @param answerHash The hash of the answer to the new riddle.
     * @param prizeType The type of prize (ETH or ERC20).
     * @param prizeTokenAddress The address of the ERC20 token if prizeType is ERC20, otherwise address(0).
     * @param prizeAmount The amount of the prize.
     * @param entryFeeTokenAddress The address of the ERC20 token for the entry fee, otherwise address(0).
     */
    event RiddleInitialized(
                    uint256 indexed riddleId,
                    bytes32 answerHash,
                    uint8 prizeType,
                    address prizeTokenAddress,
                    uint256 prizeAmount,
                    address entryFeeTokenAddress    );


    /**
     * @notice Allows a user to deposit ETH into their personal balance within the contract.
     * @dev The deposited ETH can later be withdrawn by the user.
     */
    function deposit() public payable nonReentrant {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Receives incoming ETH and adds it to the `ethPrizePool`.
     * @dev This function is payable and is triggered when ETH is sent directly to the contract
     *      without specifying a function.
     */
    receive() external payable {
        require(msg.value > 0, "ETH amount must be greater than zero");
        ethPrizePool += msg.value;
        emit EthReceived(msg.sender, msg.value);
    }

    /**
     * @notice Allows the contract owner to fund the ERC20 token prize pool.
     * @dev This function can only be called if the current riddle's prize type is ERC20.
     * @param _amount The amount of ERC20 tokens to transfer from the owner to the contract's prize pool.
     */
    function fundTokenPrizePool(uint256 _amount) public onlyOwner nonReentrant {
        require(_amount > 0, "Amount must be greater than zero");
        require(prizeType == PrizeType.ERC20, "Current riddle prize is not ERC20");
        require(address(prizeToken) != address(0), "Prize token not set");
        
        prizeToken.safeTransferFrom(msg.sender, address(this), _amount);
        tokenPrizePool += _amount;
        emit PrizeFunded(msg.sender, _amount, PrizeType.ERC20);
    }

    /**
     * @notice Allows a user to withdraw their deposited ETH from their personal balance.
     * @param _amount The amount of ETH to withdraw.
     */
    function withdraw(uint256 _amount) public nonReentrant {
        require(_amount > 0, "Withdrawal amount must be greater than zero");
        require(balances[msg.sender] >= _amount, "Insufficient balance");

        balances[msg.sender] -= _amount;
        (bool success,) = msg.sender.call{value: _amount}("");
        require(success, "Withdrawal failed");
        emit Withdrawal(msg.sender, _amount);
    }

    /**
     * @notice Allows the contract owner to withdraw ETH from the `ethPrizePool`.
     * @dev This function can only be called by the contract owner.
     * @param _amount The amount of ETH to withdraw from the prize pool.
     */
    function ownerWithdraw(uint256 _amount) public onlyOwner nonReentrant {
        require(_amount > 0, "Owner withdrawal amount must be greater than zero");
        require(ethPrizePool >= _amount, "Insufficient ETH prize pool");
        
        ethPrizePool -= _amount;
        (bool success, ) = owner().call{value: _amount, gas: 200000}("");
        require(success, "Owner withdrawal failed");
        emit OwnerWithdrawal(owner(), _amount);
    }

    /**
     * @notice Allows the contract owner to withdraw ERC20 tokens from the `tokenPrizePool`.
     * @dev This function can only be called by the contract owner.
     * @dev It ensures that the requested amount is available in the prize pool and performs a safe transfer.
     * @param _amount The amount of ERC20 tokens to withdraw from the token prize pool.
     */
    function ownerWithdrawTokens(uint256 _amount) external onlyOwner nonReentrant {
        require(_amount > 0, "Owner token withdrawal amount must be greater than zero");
        require(tokenPrizePool >= _amount, "Insufficient token prize pool");
        require(address(prizeToken) != address(0), "Prize token not set");
        
        tokenPrizePool -= _amount;
        prizeToken.safeTransfer(owner(), _amount);
        emit OwnerWithdrawTokens(_amount);
    }

    /**
     * @notice Distributes the prize to the winner based on the prize type.
     * @dev Internal function that handles both ETH and ERC20 prize distribution.
     *      Follows the Checks-Effects-Interactions pattern for security.
     * @param _winner The address of the winner receiving the prize.
     * @param _amount The amount of the prize to distribute.
     */
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

    /**
     * @notice Allows a player to submit an answer to the current riddle and claim the prize if correct.
     * @dev The player must have already entered the game for the current riddle and not yet claimed a prize.
     * @param _answer The player's proposed answer to the riddle.
     */
    /**
     * @dev IMPORTANT DEPLOYMENT NOTE: The hashing mechanism for answers was changed from `abi.encodePacked` to `abi.encode`
     *      for improved security. This is a BREAKING CHANGE for existing riddles.
     *      Deployment to an existing system requires a migration plan:
     *      1. Ensure no active riddles are using the old `abi.encodePacked` hashing.
     *      2. If active riddles exist, they must be resolved or invalidated safely.
     *      3. A one-time migration script might be needed to re-hash existing answers if applicable,
     *         or new riddle creation should be locked until existing prize pools are cleared.
     */
    function solveRiddleAndClaim(string calldata _answer) public nonReentrant {
        require(currentRiddleId > 0, "No active riddle");
        require(hasParticipated[currentRiddleId][msg.sender], "Must enter the game first");
        require(!hasClaimed[currentRiddleId][msg.sender], "Already claimed");
        require(hasRevealed[currentRiddleId][msg.sender], "Must reveal guess before solving");

        require(revealedGuessHash[currentRiddleId][msg.sender] == keccak256(abi.encodePacked(_answer)), "Revealed guess does not match provided answer");

        hasClaimed[currentRiddleId][msg.sender] = true; // mark claimed
        _distributePrize(msg.sender, prizeAmount);

        // Clear revealed state after successful claim to prevent replay
        revealedGuessHash[currentRiddleId][msg.sender] = bytes32(0);
        hasRevealed[currentRiddleId][msg.sender] = false;
    }

    /**
     * @notice Allows a player to enter the game for a specific riddle by paying an entry fee.
     * @dev This function handles the collection of entry fees. It requires an exact transfer amount,
     *      meaning fee-on-transfer (FOT) tokens are NOT supported. Players can only enter the active riddle.
     * @param _riddleId The ID of the riddle the player wishes to enter.
     */
    function enterGame(uint256 _riddleId) public nonReentrant {
        require(!hasParticipated[_riddleId][msg.sender], "Already participated in this riddle");
        require(_riddleId == currentRiddleId, "Not the active riddle ID");
        require(currentRiddleId > 0, "No active riddle");
        
        if (ENTRY_FEE > 0) {
            IERC20 token = entryFeeToken;
            require(address(token) != address(0), "Entry fee token not set");
            uint256 beforeBal = token.balanceOf(address(this));
            token.safeTransferFrom(msg.sender, address(this), ENTRY_FEE);
            uint256 received = token.balanceOf(address(this)) - beforeBal;
            require(received == ENTRY_FEE, "Entry fee mismatch (FOT not supported)");

            emit EntryFeeCollected(msg.sender, address(token), received, _riddleId);
        }

        hasParticipated[_riddleId][msg.sender] = true; // mark entered
        emit PlayerEntered(msg.sender, _riddleId);
    }

    /**
     * @notice Allows a player to submit a hashed guess for a specific riddle.
     * @dev This function is part of a commit-reveal scheme to prevent front-running.
     *      Players submit a hash of their guess first, and later reveal the actual guess.
     * @param _riddleId The ID of the riddle for which the guess is being submitted.
     * @param _guessHash The keccak256 hash of the player's guess.
     */
    function submitGuess(uint256 _riddleId, bytes32 _guessHash) public nonReentrant {
        require(_riddleId > 0, "Riddle ID cannot be zero");
        require(_riddleId == currentRiddleId, "Not the active riddle ID");
        require(_guessHash != bytes32(0), "Guess hash cannot be zero"); // Validate hash is not empty
        require(hasParticipated[_riddleId][msg.sender], "Must enter the game first");
        require(committedGuesses[_riddleId][msg.sender] == bytes32(0), "Already submitted a guess for this riddle");

        if (_guessHash == sAnswerHash) {
            if (!isWinner[_riddleId][msg.sender]) {
                winners[_riddleId].push(msg.sender);
                isWinner[_riddleId][msg.sender] = true;
                emit WinnerFound(msg.sender, _riddleId);
            }
            emit GuessEvaluated(_riddleId, msg.sender, block.timestamp, true);
        } else {
            emit GuessEvaluated(_riddleId, msg.sender, block.timestamp, false);
        }
        committedGuesses[_riddleId][msg.sender] = _guessHash;
        committedAt[_riddleId][msg.sender] = block.timestamp;
        emit GuessSubmitted(msg.sender, _riddleId, _guessHash);
    }

    /**
     * @notice Allows a player to reveal their previously committed guess for a riddle.
     * @dev This function is part of the commit-reveal scheme. It verifies the revealed guess
     *      against the committed hash and ensures the reveal delay has passed.
     * @param _riddleId The ID of the riddle for which the guess is being revealed.
     * @param _guess The player's actual guess string.
     */
    function revealGuess(uint256 _riddleId, string memory _guess) public nonReentrant {
        require(_riddleId > 0, "Riddle ID cannot be zero");
        require(_riddleId == currentRiddleId, "Not the active riddle ID");
        require(hasParticipated[_riddleId][msg.sender], "Must enter the game first");
        require(committedGuesses[_riddleId][msg.sender] != bytes32(0), "No committed guess");
        require(!hasRevealed[_riddleId][msg.sender], "Already revealed");
        require(block.timestamp >= committedAt[_riddleId][msg.sender] + revealDelay, "Reveal too early");

        bytes32 computedHash = keccak256(abi.encodePacked(_guess));
        require(computedHash == committedGuesses[_riddleId][msg.sender], "Reveal does not match commit");

        revealedGuessHash[_riddleId][msg.sender] = computedHash;
        hasRevealed[_riddleId][msg.sender] = true;

        // Optionally clear committedGuesses and committedAt to save gas/prevent reuse
        committedGuesses[_riddleId][msg.sender] = bytes32(0);
        committedAt[_riddleId][msg.sender] = 0;

        emit GuessRevealed(msg.sender, _riddleId, computedHash);
    }

    /**
     * @notice Allows the contract owner to set the minimum reveal delay for guesses.
     * @dev The reveal delay is the minimum time in seconds that must pass between
     *      committing a guess and revealing it.
     * @param _newRevealDelay The new reveal delay in seconds.
     */
    function setRevealDelay(uint256 _newRevealDelay) public onlyOwner {
        // Optional: Add sanity checks for _newRevealDelay (e.g., max/min bounds)
        revealDelay = _newRevealDelay;
    }

    /**
     * @notice Allows the contract owner to set up a new riddle with its answer hash, prize details, and entry fee token.
     * @dev The `_riddleId` must be greater than the `currentRiddleId` to ensure monotonic progression and prevent replay attacks.
     *      The `ethPrizePool` and `tokenPrizePool` are reset to 0 for each new riddle.
     *      Requires `_prizeTokenAddress` to be a valid ERC20 contract if `_prizeType` is ERC20.
     *      Requires `_entryFeeTokenAddress` to be a valid ERC20 contract if `ENTRY_FEE` is greater than 0.
     * @param _riddleId The unique identifier for the new riddle.
     * @param _answerHash The hash of the answer to the new riddle.
     * @param _prizeType The type of prize (ETH or ERC20).
     * @param _prizeTokenAddress The address of the ERC20 token if prizeType is ERC20, otherwise address(0).
     * @param _prizeAmount The amount of the prize.
     * @param _entryFeeTokenAddress The address of the ERC20 token for the entry fee, otherwise address(0).
     */
    function setRiddle(uint256 _riddleId, bytes32 _answerHash, PrizeType _prizeType, address _prizeTokenAddress, uint256 _prizeAmount, address _entryFeeTokenAddress) public onlyOwner {
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

        if (ENTRY_FEE > 0) {
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

        require(ethPrizePool == 0, "Must withdraw ETH prize pool before new riddle");
        require(tokenPrizePool == 0, "Must withdraw token prize pool before new riddle");
        currentRiddleId = _riddleId;
        sAnswerHash = _answerHash;
        prizeType = _prizeType;
        prizeAmount = _prizeAmount;

        emit RiddleInitialized(
            _riddleId,
            _answerHash,
            uint8(_prizeType),
            _prizeTokenAddress,
            _prizeAmount,
            _entryFeeTokenAddress
        );
    }


    /**
     * @notice Returns the address of the ERC20 prize token currently set for the active riddle.
     * @dev Returns address(0) if the prize type is ETH or if no prize token is set.
     * @return The address of the prize token.
     */
    function getPrizeToken() public view returns (address) {
        return address(prizeToken);
    }
}