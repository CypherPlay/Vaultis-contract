// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Vaultis is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    constructor(address initialOwner, address _retryTokenAddress) Ownable(initialOwner) {
        require(_retryTokenAddress != address(0), "Retry token address cannot be zero");
        require(address(_retryTokenAddress).code.length > 0, "Retry token has no contract code");
        try IERC20(_retryTokenAddress).totalSupply() returns (uint256) {
        // Token is valid
        }
        catch {
            revert("Invalid ERC-20 token for retry: totalSupply call failed");
        }
        entryFeeToken = IERC20(address(0));
        revealDelay = 1 hours; // Default reveal delay
        retryToken = IERC20(_retryTokenAddress);
    }
    mapping(address => uint256) public balances;
    uint256 public currentRiddleId;
    uint256 public ethPrizePool;
    // IERC20 public prizeToken; // Removed, now part of RiddleConfig
    uint256 public tokenPrizePool;
    uint256 public entryFeeBalance;
    // uint256 public prizeAmount; // Removed, now part of RiddleConfig
    IERC20 public entryFeeToken;

    struct RiddleConfig {
        uint256 prizeAmount;
        PrizeType prizeType;
        IERC20 prizeToken;
    }

    mapping(uint256 => RiddleConfig) public riddleConfigs;
    uint256 public constant ENTRY_FEE = 1 ether;
    IERC20 public retryToken;
    uint256 public constant RETRY_COST = 0.1 ether; // Example retry cost
    uint256 public constant MAX_RETRIES = 3; // Max retries per player per riddle

    enum PrizeType {
        ETH,
        ERC20
    }

    // Track entry and claim independently to avoid blocking legitimate claims
    mapping(uint256 => mapping(address => bool)) public hasParticipated; // entered
    mapping(uint256 => mapping(address => bool)) public hasClaimed; // claimed
    mapping(address => uint256) public retries;
    mapping(address => uint256) private lastRiddleIdForUser;
    mapping(uint256 => mapping(address => bytes32)) public committedGuesses; // Stores hashed guesses for commit-reveal
    mapping(uint256 => mapping(address => uint256)) public committedAt; // timestamp when commit made
    mapping(uint256 => mapping(address => bytes32)) public revealedGuessHash; // stores the hash of the revealed guess (or bytes32(0) if none)
    mapping(uint256 => mapping(address => bool)) public hasRevealed; // replay protection / quick check
    uint256 public revealDelay; // minimum seconds to wait between commit and reveal (owner-settable)
    bytes32 internal sAnswerHash;
    mapping(uint256 => address[]) public winners;
    mapping(uint256 => mapping(address => bool)) public isWinner;
    mapping(uint256 => uint256) public totalPrizeDistributed;
    mapping(uint256 => mapping(address => bool)) public hasReceivedRemainder;
    mapping(uint256 => bool) public isPaidOut;
    mapping(uint256 => uint256) public totalWinnersCount; // New: Total number of winners for a riddle
    mapping(uint256 => uint256) public paidWinnersCount; // New: Number of winners paid for a riddle

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
     * @notice Emitted after a batch payout to multiple winners is successfully executed.
     * @param riddleId The ID of the riddle for which the payout occurred.
     * @param winners The array of addresses of the winners who received a payout in this batch.
     * @param totalAmount The total amount of prize distributed in this batch.
     */
    event PayoutExecuted(uint256 indexed riddleId, address[] winners, uint256 totalAmount);
    /**
     * @notice Emitted when a player successfully enters a riddle.
     * @param player The address of the player who entered.
     * @param riddleId The ID of the riddle the player entered.
     */
    event PlayerEntered(address indexed player, uint256 indexed riddleId);
    event EntryFeesWithdrawn(address indexed recipient, uint256 amount);
    /**
     * @notice Emitted when a player successfully purchases a retry for a riddle.
     * @dev While `_riddleId` indicates the active riddle at the time of purchase, retries are tracked globally per user and are reset when a user interacts with a new riddle.
     * @param player The address of the player who purchased the retry.
     * @param riddleId The ID of the riddle for which the retry was purchased.
     * @param cost The cost of the retry.
     * @param newRetryCount The new number of retries available to the player.
     */
    event RetryPurchased(address indexed player, uint256 indexed riddleId, uint256 cost, uint256 newRetryCount);
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
        address entryFeeTokenAddress
    );

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
        RiddleConfig storage currentRiddleConfig = riddleConfigs[currentRiddleId];
        require(currentRiddleConfig.prizeType == PrizeType.ERC20, "Current riddle prize is not ERC20");
        require(address(currentRiddleConfig.prizeToken) != address(0), "Prize token not set");

        currentRiddleConfig.prizeToken.safeTransferFrom(msg.sender, address(this), _amount);
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
        (bool success,) = owner().call{value: _amount, gas: 200000}("");
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
        RiddleConfig storage currentRiddleConfig = riddleConfigs[currentRiddleId];
        require(address(currentRiddleConfig.prizeToken) != address(0), "Prize token not set");

        tokenPrizePool -= _amount;
        currentRiddleConfig.prizeToken.safeTransfer(owner(), _amount);
        emit OwnerWithdrawTokens(_amount);
    }

    /**
     * @notice Allows the contract owner to withdraw accumulated entry fee tokens.
     * @dev Only the contract owner can call this function.
     * @param to The address to which the entry fee tokens will be transferred.
     */
    function withdrawEntryFees(address to) public onlyOwner nonReentrant {
        require(entryFeeBalance > 0, "No entry fees to withdraw");
        require(to != address(0), "Recipient address cannot be zero");
        
        uint256 amount = entryFeeBalance;
        entryFeeBalance = 0; // Set to zero before transfer to follow Checks-Effects-Interactions pattern

        IERC20(entryFeeToken).safeTransfer(to, amount);
        emit EntryFeesWithdrawn(to, amount);
    }

    /**
     * @notice Distributes the prize to the winner based on the prize type.
     * @dev Internal function that handles both ETH and ERC20 prize distribution.
     *      Follows the Checks-Effects-Interactions pattern for security.
     * @param _winner The address of the winner receiving the prize.
     * @param _amount The amount of the prize to distribute.
     */
    function _distributePrize(address _winner, uint256 _amount, PrizeType _prizeType, IERC20 _prizeToken) internal {
        require(_winner != address(0), "Winner address cannot be zero");
        require(_amount > 0, "Prize amount must be greater than zero");

        if (_prizeType == PrizeType.ETH) {
            require(ethPrizePool >= _amount, "Insufficient ETH prize pool balance");
            require(address(this).balance >= _amount, "Insufficient contract ETH balance");
            ethPrizePool -= _amount;
            (bool success,) = _winner.call{value: _amount}("");
            require(success, "ETH transfer failed");
        } else if (_prizeType == PrizeType.ERC20) {
            require(address(_prizeToken) != address(0), "Prize token not set");
            require(tokenPrizePool >= _amount, "Insufficient ERC20 prize pool balance");
            tokenPrizePool -= _amount;
            _prizeToken.safeTransfer(_winner, _amount);
        }
        emit PrizeDistributed(_winner, _amount, _prizeType);
    }

    /**
     * @notice Allows a player to submit an answer to the current riddle and claim the prize if correct.
     * @dev The player must have already entered the game for the current riddle and not yet claimed a prize.
     * @param _answer The player's proposed answer to the riddle.
     */
    /**
     * @dev IMPORTANT DEPLOYMENT NOTE: The hashing mechanism for answers was changed from `abi.encode` to `abi.encodePacked`
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
        require(isWinner[currentRiddleId][msg.sender], "Not a registered winner for the current riddle");

        require(
            revealedGuessHash[currentRiddleId][msg.sender] == keccak256(abi.encodePacked(_answer)),
            "Revealed guess does not match provided answer"
        );

        hasClaimed[currentRiddleId][msg.sender] = true; // mark claimed
        RiddleConfig storage currentRiddleConfig = riddleConfigs[currentRiddleId];
        _distributePrize(
            msg.sender, currentRiddleConfig.prizeAmount, currentRiddleConfig.prizeType, currentRiddleConfig.prizeToken
        );

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

        if (lastRiddleIdForUser[msg.sender] != _riddleId) {
            retries[msg.sender] = 0;
            lastRiddleIdForUser[msg.sender] = _riddleId;
        }

        if (ENTRY_FEE > 0) {
            IERC20 token = entryFeeToken;
            require(address(token) != address(0), "Entry fee token not set");
            uint256 beforeBal = token.balanceOf(address(this));
            token.safeTransferFrom(msg.sender, address(this), ENTRY_FEE);
            uint256 received = token.balanceOf(address(this)) - beforeBal;
            require(received == ENTRY_FEE, "Entry fee mismatch (FOT not supported)");

            emit EntryFeeCollected(msg.sender, address(token), received, _riddleId);
            entryFeeBalance += received;
        }

        hasParticipated[_riddleId][msg.sender] = true; // mark entered
        emit PlayerEntered(msg.sender, _riddleId);
    }

    /**
     * @notice Allows a player to purchase an additional retry attempt for the current riddle.
     * @dev This function facilitates the retry mechanism within the Vaultis game.
     *      Players can purchase retries to submit new guesses after an incorrect attempt,
     *      up to a maximum defined by `MAX_RETRIES`.
     *
     *      **Process:**
     *      1.  **Validation:** Checks if the provided `_riddleId` matches the `currentRiddleId`,
     *          if the player has already participated in the riddle, if the `retryToken` is set,
     *          and if the player has not exceeded `MAX_RETRIES`.
     *      2.  **Retry Reset:** If the player is interacting with a new riddle (i.e., `lastRiddleIdForUser[msg.sender]`
     *          is different from `_riddleId`), their retry count is reset to 0. This ensures retries are
     *          per-riddle and not carried over.
     *      3.  **Token Transfer:** Requires the player to transfer `RETRY_COST` amount of the
     *          `retryToken` (an ERC20 token, referred to as `$Y` token in documentation) to the contract.
     *          This transfer uses `SafeERC20.safeTransferFrom` and explicitly checks for an exact transfer amount,
     *          meaning fee-on-transfer (FOT) tokens are **NOT** supported for retry payments.
     *      4.  **State Update:** Increments the player's `retries[msg.sender]` count for the current riddle.
     *      5.  **Event Emission:** Emits a `RetryPurchased` event upon successful purchase.
     *
     *      **State Changes:**
     *      -   `retries[msg.sender]` is incremented (or reset to 0 if a new riddle).
     *      -   `lastRiddleIdForUser[msg.sender]` is updated to `_riddleId` if it's a new riddle for the user.
     *      -   `retryToken` balance of the contract increases by `RETRY_COST`.
     *      -   `retryToken` balance of `msg.sender` decreases by `RETRY_COST`.
     *
     *      **Error Messages:**
     *      -   `"Not the active riddle ID"`: If `_riddleId` does not match `currentRiddleId`.
     *      -   `"Must participate in the riddle first"`: If the player has not called `enterGame` for the riddle.
     *      -   `"Retry token not set"`: If the `retryToken` address is `address(0)`.
     *      -   `"Max retries reached"`: If `retries[msg.sender]` is already equal to `MAX_RETRIES`.
     *      -   `"Retry cost mismatch (FOT not supported)"`: If the amount of `retryToken` transferred
     *          is not exactly `RETRY_COST`, typically due to fee-on-transfer tokens.
     *
     *      **Usage Examples (Solidity):**
     *      ```solidity
     *      // Assuming 'vaultisContract' is an instance of Vaultis and 'retryTokenContract' is an IERC20 instance
     *      // First, approve the Vaultis contract to spend the retry tokens
     *      retryTokenContract.approve(address(vaultisContract), vaultisContract.RETRY_COST());
     *
     *      // Then, purchase a retry for the current riddle
     *      vaultisContract.purchaseRetry(vaultisContract.currentRiddleId());
     *      ```
     *
     *      **Usage Examples (Web3.js/Ethers.js):**
     *      ```javascript
     *      // Assuming 'vaultisContract' and 'retryTokenContract' are contract instances
     *      // and 'playerAddress' is the address of the player
     *
     *      // Approve the Vaultis contract to spend retry tokens
     *      const retryCost = await vaultisContract.RETRY_COST();
     *      await retryTokenContract.methods.approve(vaultisContract.address, retryCost).send({ from: playerAddress });
     *
     *      // Purchase a retry
     *      const currentRiddleId = await vaultisContract.currentRiddleId();
     *      await vaultisContract.methods.purchaseRetry(currentRiddleId).send({ from: playerAddress });
     *      ```
     *
     * @param _riddleId The ID of the riddle for which the retry is being purchased.
     */
    function purchaseRetry(uint256 _riddleId) public nonReentrant {
        require(_riddleId == currentRiddleId, "Not the active riddle ID");
        require(hasParticipated[_riddleId][msg.sender], "Must participate in the riddle first");
        require(address(retryToken) != address(0), "Retry token not set");
        require(retries[msg.sender] < MAX_RETRIES, "Max retries reached");

        if (lastRiddleIdForUser[msg.sender] != _riddleId) {
            retries[msg.sender] = 0;
            lastRiddleIdForUser[msg.sender] = _riddleId;
        }

        // Ensure player has enough retry tokens
        uint256 beforeBal = retryToken.balanceOf(address(this));
        retryToken.safeTransferFrom(msg.sender, address(this), RETRY_COST);
        uint256 received = retryToken.balanceOf(address(this)) - beforeBal;
        require(received == RETRY_COST, "Retry cost mismatch (FOT not supported)");

        retries[msg.sender]++;
        emit RetryPurchased(msg.sender, _riddleId, RETRY_COST, retries[msg.sender]);
    }

    /**
     * @notice Allows a player to submit a hashed guess for a specific riddle as part of a commit-reveal scheme.
     * @dev This function records a player's commitment to a guess. The actual guess is revealed later using `revealGuess`.
     *      This prevents front-running and ensures fair play.
     *
     *      **Hash Requirements:**
     *      The `_guessHash` must be the `keccak256` hash of the player's intended guess.
     *      It is crucial to use `abi.encodePacked` for hashing the guess string to match the contract's internal hashing mechanism.
     *      Example: `keccak256(abi.encodePacked("mysecretguess"))`
     *
     *      **Winner Evaluation:**
     *      If the submitted `_guessHash` matches the riddle's `sAnswerHash`, the player is immediately marked as a potential winner.
     *      However, the prize is only claimable after successfully revealing the guess via `revealGuess` and then calling `solveRiddleAndClaim`.
     *
     *      **Retry Usage:**
     *      If a player has previously submitted a guess for the current riddle and their new `_guessHash` does not match the `sAnswerHash`,
     *      a retry is consumed. Players can purchase retries using `purchaseRetry` up to `MAX_RETRIES`.
     *      If a retry is used, the previous committed guess and its timestamp are cleared, allowing a new guess to be committed. This also clears any previously revealed guess and its state for the current riddle, requiring a fresh commit-reveal cycle.
     *
     *      **Emitted Events:**
     *      - `GuessSubmitted(player, riddleId, guessHash)`: Always emitted when a guess is successfully committed.
     *      - `WinnerFound(winner, riddleId)`: Emitted if the `_guessHash` matches the `sAnswerHash` and the player was not already a winner.
     *      - `GuessEvaluated(riddleId, player, timestamp, isWinner)`: Emitted after evaluating the guess, indicating if it was correct.
     *
     *      **Example Usage (Solidity):**
     *      ```solidity
     *      string memory playerGuess = "mysecretanswer";
     *      bytes32 hashedGuess = keccak256(abi.encodePacked(playerGuess));
     *      vaultisContract.submitGuess(currentRiddleId, hashedGuess);
     *      ```
     *
     *      **Example Usage (Web3.js/Ethers.js):**
     *      ```javascript
     *      const playerGuess = "mysecretanswer";
     *      const hashedGuess = web3.utils.soliditySha3({ type: "string", value: playerGuess });
     *      // Or for ethers.js:
     *      // const hashedGuess = ethers.utils.solidityKeccak256(["string"], [playerGuess]); // For ethers v5.x
     *      // const hashedGuess = ethers.solidityPackedKeccak256(["string"], [playerGuess]); // For ethers v6.x
     *      await vaultisContract.methods.submitGuess(currentRiddleId, hashedGuess).send({ from: playerAddress });
     *      ```
     *
     * @param _riddleId The ID of the riddle for which the guess is being submitted. Must be the `currentRiddleId`.
     * @param _guessHash The `keccak256` hash of the player's guess. Must not be `bytes32(0)`.
     */
    function submitGuess(uint256 _riddleId, bytes32 _guessHash) public nonReentrant {
        require(_riddleId > 0, "Riddle ID cannot be zero");
        require(_riddleId == currentRiddleId, "Not the active riddle ID");
        require(_guessHash != bytes32(0), "Guess hash cannot be zero"); // Validate hash is not empty
        require(hasParticipated[_riddleId][msg.sender], "Vaultis: Player has not participated in this riddle.");

        bool hadPreviousGuess = committedGuesses[_riddleId][msg.sender] != bytes32(0);

        if (_guessHash == sAnswerHash) {
            if (!isWinner[_riddleId][msg.sender]) {
                winners[_riddleId].push(msg.sender);
                isWinner[_riddleId][msg.sender] = true;
                totalWinnersCount[_riddleId]++; // Increment totalWinnersCount
                emit WinnerFound(msg.sender, _riddleId);
            }
            emit GuessEvaluated(_riddleId, msg.sender, block.timestamp, true);
        } else {
            emit GuessEvaluated(_riddleId, msg.sender, block.timestamp, false);
            if (hadPreviousGuess) {
                require(retries[msg.sender] > 0, "Vaultis: No retries available to submit a new guess.");
                retries[msg.sender]--;
                // Clear previous guess to allow new submission
                committedGuesses[_riddleId][msg.sender] = bytes32(0);
                committedAt[_riddleId][msg.sender] = 0;
                // Also clear revealed state if any, to ensure a fresh attempt
                revealedGuessHash[_riddleId][msg.sender] = bytes32(0);
                hasRevealed[_riddleId][msg.sender] = false;
            }
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
    function setRiddle(
        uint256 _riddleId,
        bytes32 _answerHash,
        PrizeType _prizeType,
        address _prizeTokenAddress,
        uint256 _prizeAmount,
        address _entryFeeTokenAddress
    ) public onlyOwner {
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
            }
            catch {
                revert("Invalid ERC-20 token: totalSupply call failed");
            }
            // prizeToken = IERC20(_prizeTokenAddress);
        } else {
            require(_prizeTokenAddress == address(0), "Prize token address must be zero for ETH prize");
            // prizeToken = IERC20(address(0));
        }

        if (ENTRY_FEE > 0) {
            require(
                _entryFeeTokenAddress != address(0),
                "Entry fee token address cannot be zero if entry fee amount is greater than zero"
            );
            require(address(_entryFeeTokenAddress).code.length > 0, "Entry fee token has no contract code");
            try IERC20(_entryFeeTokenAddress).totalSupply() returns (uint256) {
            // Token is valid
            }
            catch {
                revert("Invalid ERC-20 token for entry fee: totalSupply call failed");
            }
            entryFeeToken = IERC20(_entryFeeTokenAddress);
        } else {
            require(
                _entryFeeTokenAddress == address(0), "Entry fee token address must be zero if entry fee amount is zero"
            );
            entryFeeToken = IERC20(address(0));
        }

        require(ethPrizePool == 0, "Must withdraw ETH prize pool before new riddle");
        require(tokenPrizePool == 0, "Must withdraw token prize pool before new riddle");
        require(entryFeeBalance == 0, "Withdraw entry fees before creating new riddle");
        currentRiddleId = _riddleId;
        sAnswerHash = _answerHash;

        riddleConfigs[_riddleId] =
            RiddleConfig({prizeAmount: _prizeAmount, prizeType: _prizeType, prizeToken: IERC20(_prizeTokenAddress)});

        emit RiddleInitialized(
            _riddleId, _answerHash, uint8(_prizeType), _prizeTokenAddress, _prizeAmount, _entryFeeTokenAddress
        );
    }

    /**
     * @notice Handles prize distribution to the winning addresses for a specific riddle.
     * @dev This function can only be called by the contract owner.
     * @param _riddleId The ID of the riddle for which prizes are being paid out.
     * @param _winners An array of addresses of the winners for the specified riddle.
     */
    /**
     * @notice Handles prize distribution to a batch of winning addresses for a specific riddle.
     * @dev This function can only be called by the contract owner.
     *      It allows for batched payouts to manage gas limits for riddles with many winners.
     *      The riddle is marked as fully paid out only when all registered winners have received their prize.
     *
     *      **Prize Calculation and Distribution:**
     *      1.  **Per-Winner Amount:** The total `prizeAmount` for the riddle (from `riddleConfigs[_riddleId].prizeAmount`)
     *          is divided equally among `totalWinnersCount[_riddleId]` to determine the base `perWinnerAmount`.
     *      2.  **Remainder Distribution:** Any remainder from the division (`prizeAmount % totalWinnersCount`)
     *          is distributed by adding 1 unit to the `perWinnerAmount` for the first `remainder` number of
     *          *unpaid* winners. This ensures all prize funds are distributed.
     *      3.  **Batch Processing:** The function processes winners in batches (`_winnersBatch`) to manage gas costs.
     *          It first calculates the `totalAmountToDistributeInBatch` by summing the individual prize amounts
     *          (including any remainder portions) for eligible winners within the current batch.
     *      4.  **Eligibility:** Only winners who are registered (`isWinner[_riddleId][winner]`) and have not yet
     *          claimed their prize (`!hasClaimed[_riddleId][winner]`) are eligible for payout in a batch.
     *      5.  **Fund Check:** Before initiating transfers, the function verifies that the respective prize pool
     *          (ETH or ERC20) has sufficient balance to cover the `totalAmountToDistributeInBatch`.
     *      6.  **Individual Distribution:** Each eligible winner in the batch receives their calculated prize amount
     *          via the internal `_distributePrize` function.
     *
     *      **Reentrancy Safety:**
     *      -   The `nonReentrant` modifier is used to prevent reentrancy attacks during external calls
     *          made by `_distributePrize` (e.g., ETH transfers).
     *      -   The `hasClaimed[_riddleId][winner]` state is updated *before* the external prize distribution call
     *          to adhere to the Checks-Effects-Interactions pattern, further mitigating reentrancy risks.
     *
     *      **State Updates:**
     *      -   `hasClaimed[_riddleId][winner]` is set to `true` for each winner successfully paid.
     *      -   `paidWinnersCount[_riddleId]` is incremented for each winner paid.
     *      -   `totalPrizeDistributed[_riddleId]` accumulates the total prize paid for the riddle.
     *      -   `hasReceivedRemainder[_riddleId][winner]` is set to `true` for winners who receive a remainder portion.
     *      -   `isPaidOut[_riddleId]` is set to `true` once `paidWinnersCount[_riddleId]` equals `totalWinnersCount[_riddleId]`,
     *          indicating all winners for the riddle have been paid.
     *
     *      **Event Emission:**
     *      -   `PayoutExecuted(_riddleId, _winnersBatch, totalAmountToDistributeInBatch)` is emitted after each
     *          successful batch payout, providing details of the riddle, the winners in the batch, and the total
     *          amount distributed in that batch.
     *
     * @param _riddleId The ID of the riddle for which prizes are being paid out.
     * @param _winnersBatch An array of addresses of the winners to be paid in this batch.
     */
    function payout(uint256 _riddleId, address[] memory _winnersBatch) public onlyOwner nonReentrant {
        // Input validation
        require(_riddleId > 0, "Riddle ID must be greater than zero");
        require(_riddleId <= currentRiddleId, "Riddle ID must be current or past");
        require(_winnersBatch.length > 0, "Winners array cannot be empty");
        require(!isPaidOut[_riddleId], "Payout already executed for this riddle");

        RiddleConfig storage riddleConfig = riddleConfigs[_riddleId];

        // Implement duplicate winner checking for the _winnersBatch array
        for (uint256 i = 0; i < _winnersBatch.length; i++) {
            for (uint256 j = i + 1; j < _winnersBatch.length; j++) {
                require(_winnersBatch[i] != _winnersBatch[j], "Duplicate winner address in batch not allowed");
            }
        }

        // Calculate the prize amount per winner by dividing riddleConfig.prizeAmount by the total number of winners.
        // The remainder is distributed to the first 'remainder' number of *unpaid* winners.
        uint256 winnersCount = totalWinnersCount[_riddleId];
        require(winnersCount > 0, "No winners registered for this riddle");
        uint256 perWinnerAmount = riddleConfig.prizeAmount / winnersCount;
        uint256 remainder = riddleConfig.prizeAmount % winnersCount;

        require(perWinnerAmount > 0 || remainder > 0, "Per-winner amount must be greater than zero");

        uint256 currentBatchDistributedCount = 0;
        uint256 totalAmountToDistributeInBatch = 0;

        // Determine which winners in the batch are eligible for payout and calculate batch total
        for (uint256 i = 0; i < _winnersBatch.length; i++) {
            address winner = _winnersBatch[i];
            if (isWinner[_riddleId][winner] && !hasClaimed[_riddleId][winner]) {
                currentBatchDistributedCount++;
                uint256 amountForThisWinner = perWinnerAmount;

                // Check if this winner should receive a portion of the remainder
                // The remainder is distributed to the first 'remainder' number of *unpaid* winners
                if (
                    remainder > 0 && !hasReceivedRemainder[_riddleId][winner]
                        && paidWinnersCount[_riddleId] + currentBatchDistributedCount <= remainder
                ) {
                    amountForThisWinner += 1; // Distribute 1 unit of remainder to this winner
                    hasReceivedRemainder[_riddleId][winner] = true;
                }
                totalAmountToDistributeInBatch += amountForThisWinner;
            }
        }

        require(currentBatchDistributedCount > 0, "No new winners in this batch to pay out");

        // Ensure respective pool has sufficient total balance before starting distribution
        if (riddleConfig.prizeType == PrizeType.ETH) {
            require(
                ethPrizePool >= totalAmountToDistributeInBatch, "Insufficient ETH prize pool balance for payout batch"
            );
        } else if (riddleConfig.prizeType == PrizeType.ERC20) {
            require(
                tokenPrizePool >= totalAmountToDistributeInBatch,
                "Insufficient ERC20 prize pool balance for payout batch"
            );
        }

        // Distribute prizes for the current batch
        uint256 distributedInThisBatch = 0;
        for (uint256 i = 0; i < _winnersBatch.length; i++) {
            address winner = _winnersBatch[i];
            if (isWinner[_riddleId][winner] && !hasClaimed[_riddleId][winner]) {
                hasClaimed[_riddleId][winner] = true; // Mark as claimed before external call
                paidWinnersCount[_riddleId]++; // Increment global paid winners count

                uint256 amountForThisWinner = perWinnerAmount;
                if (hasReceivedRemainder[_riddleId][winner]) {
                    // Check if this winner was marked to receive remainder
                    amountForThisWinner += 1;
                }

                totalPrizeDistributed[_riddleId] += amountForThisWinner;
                _distributePrize(winner, amountForThisWinner, riddleConfig.prizeType, riddleConfig.prizeToken);
                distributedInThisBatch++;
            }
        }

        emit PayoutExecuted(_riddleId, _winnersBatch, totalAmountToDistributeInBatch);

        // Mark riddle as fully paid out if all winners have been processed
        if (paidWinnersCount[_riddleId] == totalWinnersCount[_riddleId]) {
            isPaidOut[_riddleId] = true;
        }
    }

    /**
     * @notice Returns the address of the ERC20 prize token currently set for the active riddle.
     * @dev Returns address(0) if the prize type is ETH or if no prize token is set.
     * @return The address of the prize token.
     */
    /**
     * @notice Returns the full list of winners for a specific riddle.
     * @param _riddleId The ID of the riddle to get the winner list for.
     * @return An array of addresses of the winners for the specified riddle.
     */
    function getWinnerList(uint256 _riddleId) public view returns (address[] memory) {
        return winners[_riddleId];
    }

    function getPrizeToken() public view returns (address) {
        return address(riddleConfigs[currentRiddleId].prizeToken);
    }

    /**
     * @notice Returns the current prize pool amount for the active riddle.
     * @dev This function is a view function and does not modify the contract state.
     * @return The current prize pool amount (either ETH or ERC20 tokens).
     */
    function getCurrentPrizePool() public view returns (uint256) {
        RiddleConfig storage currentRiddleConfig = riddleConfigs[currentRiddleId];
        if (currentRiddleConfig.prizeType == PrizeType.ETH) {
            return ethPrizePool;
        } else if (currentRiddleConfig.prizeType == PrizeType.ERC20) {
            return tokenPrizePool;
        }
        return 0; // Should not be reached if prizeType is always set
    }

    /**
     * @notice Returns true if the player has entered the current riddle, false otherwise.
     * @param player The address of the player to check.
     * @return True if the player has entered, false otherwise.
     */
    function hasPlayerEntered(address player) public view returns (bool) {
        return hasParticipated[currentRiddleId][player];
    }

    /**
     * @notice Returns the number of remaining retries for a given player for the current riddle.
     * @param player The address of the player to check.
     * @return The number of retries remaining for the player.
     */
    function getRetryCount(address player) public view returns (uint256) {
        return retries[player];
    }
}
