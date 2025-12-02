const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Vaultis Payouts", function () {
  let Vaultis;
  let vaultis;
  let MockERC20;
  let mockERC20;
  let owner;
  let addr1;
  let addr2;
  let addr3;
  let addrs;

      const riddleId = 1;
      const riddleAnswer = "testanswer";
      const prizePoolAmount = ethers.parseEther("100"); // 100 mock tokens
      const ENTRY_FEE = ethers.parseEther("1"); // Example entry fee, adapt as needed
  
    

  beforeEach(async function () {
    [owner, addr1, addr2, addr3, ...addrs] = await ethers.getSigners();

    // Deploy MockERC20 token
    MockERC20 = await ethers.getContractFactory("MockERC20");
    mockERC20 = await MockERC20.deploy("MockToken", "MTK");
    await mockERC20.deployed();

    // Mint tokens for players
    await mockERC20.mint(owner.address, ethers.parseEther("1000"));
    await mockERC20.mint(addr1.address, ethers.parseEther("100"));
    await mockERC20.mint(addr2.address, ethers.parseEther("100"));
    await mockERC20.mint(addr3.address, ethers.parseEther("100"));

    // Deploy Vaultis contract
    Vaultis = await ethers.getContractFactory("Vaultis");
    vaultis = await Vaultis.deploy(mockERC20.address);
    await vaultis.deployed();

    // Set up an active riddle
    await vaultis.connect(owner).setRiddle(
      riddleId,
      ethers.keccak256(ethers.toUtf8Bytes(riddleAnswer)),
      1, // PrizeType.ERC20
      mockERC20.address,
      prizePoolAmount,
      mockERC20.address // Entry fee token
    );

    // Initial funding for the prize pool (will be transferred in enterGame)
    await mockERC20.connect(owner).transfer(vaultis.address, prizePoolAmount);
  });

  describe("Payout Scenarios", function () {
    it("should distribute prize to multiple winners", async function () {
      // Players enter the game and submit correct guesses
      const entryFee = ENTRY_FEE; // Assuming ENTRY_FEE is defined and used for game entry

      // Player 1
      await mockERC20.connect(addr1).approve(vaultis.address, entryFee);
      await vaultis.connect(addr1).enterGame(riddleId);
      await vaultis.connect(addr1).submitGuess(riddleId, riddleAnswer);

      // Player 2
      await mockERC20.connect(addr2).approve(vaultis.address, entryFee);
      await vaultis.connect(addr2).enterGame(riddleId);
      await vaultis.connect(addr2).submitGuess(riddleId, riddleAnswer);

      // Player 3
      await mockERC20.connect(addr3).approve(vaultis.address, entryFee);
      await vaultis.connect(addr3).enterGame(riddleId);
      await vaultis.connect(addr3).submitGuess(riddleId, riddleAnswer);

      // Get initial balances
      const initialVaultisBalance = await mockERC20.balanceOf(vaultis.address);
      const initialAddr1Balance = await mockERC20.balanceOf(addr1.address);
      const initialAddr2Balance = await mockERC20.balanceOf(addr2.address);
      const initialAddr3Balance = await mockERC20.balanceOf(addr3.address);

      // Trigger payout
      await expect(vaultis.connect(owner).payout(riddleId))
        .to.emit(vaultis, "RiddlePayout")
        .withArgs(riddleId, prizePoolAmount, 3); // Assuming 3 winners

      // Verify final balances
      const finalVaultisBalance = await mockERC20.balanceOf(vaultis.address);
      const finalAddr1Balance = await mockERC20.balanceOf(addr1.address);
      const finalAddr2Balance = await mockERC20.balanceOf(addr2.address);
      const finalAddr3Balance = await mockERC20.balanceOf(addr3.address);

      // Each winner should receive prizePoolAmount / 3
      const expectedPayoutPerWinner = prizePoolAmount.div(3);

      expect(finalAddr1Balance).to.equal(initialAddr1Balance.add(expectedPayoutPerWinner));
      expect(finalAddr2Balance).to.equal(initialAddr2Balance.add(expectedPayoutPerWinner));
      expect(finalAddr3Balance).to.equal(initialAddr3Balance.add(expectedPayoutPerWinner));
      expect(finalVaultisBalance).to.equal(initialVaultisBalance.sub(prizePoolAmount));
    });

    it("should handle single winner scenario", async function () {
      const entryFee = ENTRY_FEE;

      // Player 1 enters the game and submits correct guess
      await mockERC20.connect(addr1).approve(vaultis.address, entryFee);
      await vaultis.connect(addr1).enterGame(riddleId);
      await vaultis.connect(addr1).submitGuess(riddleId, riddleAnswer);

      // Get initial balances
      const initialVaultisBalance = await mockERC20.balanceOf(vaultis.address);
      const initialAddr1Balance = await mockERC20.balanceOf(addr1.address);

      // Trigger payout
      await expect(vaultis.connect(owner).payout(riddleId))
        .to.emit(vaultis, "RiddlePayout")
        .withArgs(riddleId, prizePoolAmount, 1); // 1 winner

      // Verify final balances
      const finalVaultisBalance = await mockERC20.balanceOf(vaultis.address);
      const finalAddr1Balance = await mockERC20.balanceOf(addr1.address);

      expect(finalAddr1Balance).to.equal(initialAddr1Balance.add(prizePoolAmount));
      expect(finalVaultisBalance).to.equal(initialVaultisBalance.sub(prizePoolAmount));
    });

    it("should reset prize pool and mark riddle as paid out after payout", async function () {
      const entryFee = ENTRY_FEE;

      // Player 1 enters the game and submits correct guess
      await mockERC20.connect(addr1).approve(vaultis.address, entryFee);
      await vaultis.connect(addr1).enterGame(riddleId);
      await vaultis.connect(addr1).submitGuess(riddleId, riddleAnswer);

      // Get initial prize pool amount
      let riddle = await vaultis.getRiddle(riddleId);
      expect(riddle.prizePool).to.equal(prizePoolAmount);
      expect(await vaultis.isPaidOut(riddleId)).to.be.false;

      // Trigger payout
      await vaultis.connect(owner).payout(riddleId);

      // Verify prize pool is reset and isPaidOut is true
      riddle = await vaultis.getRiddle(riddleId); // Re-fetch riddle state
      expect(riddle.prizePool).to.equal(0);
      expect(await vaultis.isPaidOut(riddleId)).to.be.true;
    });
  });
});
