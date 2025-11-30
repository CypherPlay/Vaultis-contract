const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Vaultis", function () {
  let Vaultis;
  let vaultis;
  let MockERC20;
  let mockERC20;
  let owner;
  let addr1;
  let addr2;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    MockERC20 = await ethers.getContractFactory("MockERC20");
    mockERC20 = await MockERC20.deploy();
    await mockERC20.waitForDeployment();

    Vaultis = await ethers.getContractFactory("Vaultis");
    vaultis = await Vaultis.deploy(mockERC20.target);
    await vaultis.waitForDeployment();

    // Set a riddle to allow entering the game
    const riddleId = 1;
    const answerHash = ethers.keccak256(ethers.toUtf8Bytes("test_answer")); // Example hash
    const prizeAmount = ethers.parseEther("100");
    await vaultis.setRiddle(riddleId, answerHash, 0, ethers.ZeroAddress, prizeAmount, mockERC20.target);
  });

  describe("enterGame", function () {
    it("Should allow a user to enter the game with a minimum deposit", async function () {
      const riddleId = 1;
      await expect(vaultis.connect(addr1).enterGame(riddleId))
        .to.emit(vaultis, "PlayerEntered")
        .withArgs(addr1.address, riddleId);

      // Assertions
      expect(await mockERC20.balanceOf(vaultis.target)).to.equal(depositAmount);
      expect(await vaultis.hasPlayerEntered(addr1.address)).to.be.true;
    });

    it("Should revert if the deposit amount is less than the minimum", async function () {
      const depositAmount = ethers.parseEther("0"); // Less than minimum

      // Expect the transaction to revert
      const riddleId = 1;
      await expect(vaultis.connect(addr1).enterGame(riddleId)).to.be.revertedWith("Deposit amount must be greater than zero");
    });
  });
});
