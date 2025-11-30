
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Vaultis - Guess Submission", function () {
    let vaultis;
    let mockERC20;
    let owner;
    let addr1;
    let addr2;

    // Riddle configuration
    const RIDDLE_ID = 1;
    const PRIZE_AMOUNT = ethers.utils.parseEther("50");
    const ENTRY_FEE = ethers.utils.parseEther("1");

    // Hashed values for guesses
    const SECRET_ANSWER = "mysecretanswer";
    const SECRET_HASHED_ANSWER = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(SECRET_ANSWER));
    const INCORRECT_GUESS = "wrongguess";
    const INCORRECT_HASHED_GUESS = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(INCORRECT_GUESS));

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        // Deploy MockERC20 (will be used as entry fee token and retry token)
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        mockERC20 = await MockERC20.deploy();
        await mockERC20.deployed();

        // Deploy Vaultis
        const Vaultis = await ethers.getContractFactory("Vaultis");
        vaultis = await Vaultis.deploy(mockERC20.address); // Pass mockERC20 as retry token
        await vaultis.deployed();

        // Mint some tokens for testing
        await mockERC20.mint(owner.address, ethers.utils.parseEther("10000"));
        await mockERC20.mint(addr1.address, ethers.utils.parseEther("1000"));
        await mockERC20.mint(addr2.address, ethers.utils.parseEther("1000"));

        // Owner sets up a new riddle
        // PrizeType.ETH = 0, PrizeType.ERC20 = 1
        await vaultis.connect(owner).setRiddle(
            RIDDLE_ID,
            SECRET_HASHED_ANSWER,
            0, // PrizeType.ETH
            ethers.constants.AddressZero,
            PRIZE_AMOUNT,
            mockERC20.address // Entry fee token
        );

        // Fund the ETH prize pool (since PrizeType is ETH)
        await owner.sendTransaction({
            to: vaultis.address,
            value: PRIZE_AMOUNT,
        });
    });

    it("Should allow a user to submit a guess after entering the game and emit GuessSubmitted", async function () {
        // Player approves Vaultis to spend entry fee tokens
        await mockERC20.connect(addr1).approve(vaultis.address, ENTRY_FEE);

        // Player enters the game
        await expect(vaultis.connect(addr1).enterGame(RIDDLE_ID))
            .to.emit(vaultis, "EntryFeeCollected")
            .withArgs(addr1.address, mockERC20.address, ENTRY_FEE, RIDDLE_ID);

        // Player submits a guess
        await expect(vaultis.connect(addr1).submitGuess(RIDDLE_ID, SECRET_HASHED_ANSWER))
            .to.emit(vaultis, "GuessSubmitted")
            .withArgs(addr1.address, RIDDLE_ID, SECRET_HASHED_ANSWER);

        // Verify that the player is now a winner
        expect(await vaultis.isWinner(RIDDLE_ID, addr1.address)).to.be.true;
    });

    it("Should revert if the riddle ID is zero", async function () {
        await expect(vaultis.connect(addr1).submitGuess(0, SECRET_HASHED_ANSWER))
            .to.be.revertedWith("Riddle ID cannot be zero");
    });

    it("Should revert if not the active riddle ID", async function () {
        const inactiveRiddleId = 99;
        await expect(vaultis.connect(addr1).submitGuess(inactiveRiddleId, SECRET_HASHED_ANSWER))
            .to.be.revertedWith("Not the active riddle ID");
    });

    it("Should revert if guess hash is zero", async function () {
        // Player approves Vaultis to spend entry fee tokens
        await mockERC20.connect(addr1).approve(vaultis.address, ENTRY_FEE);
        // Player enters the game
        await vaultis.connect(addr1).enterGame(RIDDLE_ID);

        await expect(vaultis.connect(addr1).submitGuess(RIDDLE_ID, ethers.constants.HashZero))
            .to.be.revertedWith("Guess hash cannot be zero");
    });

    it("Should revert if player has not participated in the riddle", async function () {
        // addr2 has not entered the game
        await expect(vaultis.connect(addr2).submitGuess(RIDDLE_ID, SECRET_HASHED_ANSWER))
            .to.be.revertedWith("Vaultis: Player has not participated in this riddle.");
    });

    it("Should consume a retry if a wrong guess is submitted after a previous guess", async function () {
        // Player enters the game
        await mockERC20.connect(addr1).approve(vaultis.address, ENTRY_FEE);
        await vaultis.connect(addr1).enterGame(RIDDLE_ID);

        // First guess (incorrect)
        await vaultis.connect(addr1).submitGuess(RIDDLE_ID, INCORRECT_HASHED_GUESS);
        expect(await vaultis.retries(addr1.address)).to.equal(3); // Initial retries should be 3 if MAX_RETRIES is 3

        // Purchase a retry
        const retryCost = await vaultis.RETRY_COST();
        await mockERC20.connect(addr1).approve(vaultis.address, retryCost);
        await vaultis.connect(addr1).purchaseRetry(RIDDLE_ID);
        expect(await vaultis.retries(addr1.address)).to.equal(4); // Should have 4 retries after purchase

        // Second guess (still incorrect, consumes a retry)
        await vaultis.connect(addr1).submitGuess(RIDDLE_ID, INCORRECT_HASHED_GUESS);
        expect(await vaultis.retries(addr1.address)).to.equal(3); // Should be 3 now

        // Subsequent incorrect guesses until max retries reached
        await mockERC20.connect(addr1).approve(vaultis.address, retryCost);
        await vaultis.connect(addr1).purchaseRetry(RIDDLE_ID);
        await vaultis.connect(addr1).submitGuess(RIDDLE_ID, INCORRECT_HASHED_GUESS); // retries = 3
        await mockERC20.connect(addr1).approve(vaultis.address, retryCost);
        await vaultis.connect(addr1).purchaseRetry(RIDDLE_ID);
        await vaultis.connect(addr1).submitGuess(RIDDLE_ID, INCORRECT_HASHED_GUESS); // retries = 3

        // Try to submit another guess without retries
        await expect(vaultis.connect(addr1).submitGuess(RIDDLE_ID, INCORRECT_HASHED_GUESS))
            .to.be.revertedWith("Vaultis: No retries available to submit a new guess.");
    });

    it("Should mark player as winner if correct guess is submitted", async function () {
        // Player enters the game
        await mockERC20.connect(addr1).approve(vaultis.address, ENTRY_FEE);
        await vaultis.connect(addr1).enterGame(RIDDLE_ID);

        // Submit the correct guess
        await expect(vaultis.connect(addr1).submitGuess(RIDDLE_ID, SECRET_HASHED_ANSWER))
            .to.emit(vaultis, "WinnerFound")
            .withArgs(addr1.address, RIDDLE_ID)
            .and.to.emit(vaultis, "GuessEvaluated")
            .withArgs(RIDDLE_ID, addr1.address, (await ethers.provider.getBlock("latest")).timestamp + 1, true);

        expect(await vaultis.isWinner(RIDDLE_ID, addr1.address)).to.be.true;
    });

    it("Should not consume retry if correct guess is submitted after an incorrect one", async function () {
        // Player enters the game
        await mockERC20.connect(addr1).approve(vaultis.address, ENTRY_FEE);
        await vaultis.connect(addr1).enterGame(RIDDLE_ID);

        // Submit an incorrect guess
        await vaultis.connect(addr1).submitGuess(RIDDLE_ID, INCORRECT_HASHED_GUESS);
        const initialRetries = await vaultis.retries(addr1.address);

        // Submit the correct guess
        await vaultis.connect(addr1).submitGuess(RIDDLE_ID, SECRET_HASHED_ANSWER);

        // Retries should not change
        expect(await vaultis.retries(addr1.address)).to.equal(initialRetries);
        expect(await vaultis.isWinner(RIDDLE_ID, addr1.address)).to.be.true;
    });

    it("Should reset committed guess and revealed state when a retry is consumed", async function () {
        // Player enters the game
        await mockERC20.connect(addr1).approve(vaultis.address, ENTRY_FEE);
        await vaultis.connect(addr1).enterGame(RIDDLE_ID);

        // First guess (incorrect) and commit
        const firstGuessHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("first_incorrect"));
        await vaultis.connect(addr1).submitGuess(RIDDLE_ID, firstGuessHash);
        expect(await vaultis.committedGuesses(RIDDLE_ID, addr1.address)).to.equal(firstGuessHash);

        // Advance time to allow reveal
        await ethers.provider.send("evm_increaseTime", [3600]); // 1 hour
        await ethers.provider.send("evm_mine", []);

        // Reveal the first guess
        await vaultis.connect(addr1).revealGuess(RIDDLE_ID, "first_incorrect");
        expect(await vaultis.hasRevealed(RIDDLE_ID, addr1.address)).to.be.true;

        // Purchase a retry
        const retryCost = await vaultis.RETRY_COST();
        await mockERC20.connect(addr1).approve(vaultis.address, retryCost);
        await vaultis.connect(addr1).purchaseRetry(RIDDLE_ID);

        // Submit a second (incorrect) guess, which should consume a retry and clear previous states
        const secondGuessHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("second_incorrect"));
        await vaultis.connect(addr1).submitGuess(RIDDLE_ID, secondGuessHash);

        expect(await vaultis.committedGuesses(RIDDLE_ID, addr1.address)).to.equal(secondGuessHash);
        expect(await vaultis.hasRevealed(RIDDLE_ID, addr1.address)).to.be.false; // Should be reset
        expect(await vaultis.revealedGuessHash(RIDDLE_ID, addr1.address)).to.equal(ethers.constants.HashZero); // Should be reset
    });
});

