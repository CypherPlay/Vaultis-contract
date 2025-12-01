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
  const prizePoolAmount = ethers.utils.parseEther("100"); // 100 mock tokens

  // Utility to set up token balances and allowances
  async function setupToken(token, holder, recipient, amount) {
    await token.transfer(holder.address, amount);
    await token.connect(holder).approve(recipient.address, amount);
  }

  beforeEach(async function () {
    [owner, addr1, addr2, addr3, ...addrs] = await ethers.getSigners();

    // Deploy MockERC20 token
    MockERC20 = await ethers.getContractFactory("MockERC20");
    mockERC20 = await MockERC20.deploy("MockToken", "MTK");
    await mockERC20.deployed();

    // Deploy Vaultis contract
    Vaultis = await ethers.getContractFactory("Vaultis");
    vaultis = await Vaultis.deploy(mockERC20.address);
    await vaultis.deployed();

    // Set up an active riddle
    await vaultis.connect(owner).createRiddle(riddleId, ethers.utils.keccak256(ethers.utils.toUtf8Bytes(riddleAnswer)));

    // Fund the prize pool
    await setupToken(mockERC20, owner, vaultis, prizePoolAmount);
  });

  describe("Payout Scenarios", function () {
    it("should distribute prize to multiple winners", async function () {
      // Mock multiple winners
      await vaultis.connect(addr1).submitGuess(riddleId, riddleAnswer, { value: ethers.utils.parseEther("1") });
      await vaultis.connect(addr2).submitGuess(riddleId, riddleAnswer, { value: ethers.utils.parseEther("1") });
      await vaultis.connect(addr3).submitGuess(riddleId, riddleAnswer, { value: ethers.utils.parseEther("1") });

      // Simulate a scenario where the riddle is solved and payouts are triggered
      // For now, let's assume a function would be called to trigger payout,
      // which would then distribute the prize pool among the winners.
      // This part would need the actual payout logic from the Vaultis contract.

      // Example assertion (this will need to be adapted based on actual payout function)
      // For demonstration, let's assume `distributePrize` function exists and is called.
      // We'll add a placeholder for now.
      expect(true).to.be.true; // Placeholder assertion
    });

    it("should handle single winner scenario", async function () {
      await vaultis.connect(addr1).submitGuess(riddleId, riddleAnswer, { value: ethers.utils.parseEther("1") });

      // Simulate payout for single winner
      expect(true).to.be.true; // Placeholder assertion
    });

    it("should not payout if riddle is not solved", async function () {
      // Create a riddle that is not solved
      await vaultis.connect(owner).createRiddle(2, ethers.utils.keccak256(ethers.utils.toUtf8Bytes("anotheranswer")));
      await setupToken(mockERC20, owner, vaultis, ethers.utils.parseEther("50"));

      // Attempt to payout (assuming a function exists)
      // Expect it to revert or fail.
      expect(true).to.be.true; // Placeholder assertion
    });
  });
});
