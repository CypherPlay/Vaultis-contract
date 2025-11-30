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
    mockERC20 = await MockERC20.deploy("MockToken", "MTK");
    await mockERC20.waitForDeployment();

    Vaultis = await ethers.getContractFactory("Vaultis");
    vaultis = await Vaultis.deploy(owner.address, mockERC20.target);
    await vaultis.waitForDeployment();

    // Set a riddle to allow entering the game
    const riddleId = 1;
    const answerHash = ethers.keccak256(ethers.toUtf8Bytes("test_answer")); // Example hash
    const prizeAmount = ethers.parseEther("100");
    const entryFeeAmount = ethers.parseEther("1"); // This should match Vaultis.ENTRY_FEE

    await vaultis.setRiddle(riddleId, answerHash, 0, ethers.ZeroAddress, prizeAmount, mockERC20.target);
  });

  describe("enterGame", function () {
    let depositAmount;
    const riddleId = 1;

    beforeEach(async function () {
      depositAmount = await vaultis.ENTRY_FEE();

      // Mint and approve tokens for addr1 for each test
      await mockERC20.mint(addr1.address, depositAmount);
      await mockERC20.connect(addr1).approve(vaultis.target, depositAmount);
    });

    it("Should allow a user to enter the game with a minimum deposit", async function () {
      await expect(vaultis.connect(addr1).enterGame(riddleId))
        .to.emit(vaultis, "PlayerEntered")
        .withArgs(addr1.address, riddleId);

      // Assertions
      expect(await mockERC20.balanceOf(vaultis.target)).to.equal(depositAmount);
      expect(await vaultis.hasPlayerEntered(addr1.address)).to.be.true;
    });

    it("Should revert if the user has insufficient allowance", async function () {
      // Approve less than the required depositAmount
      await mockERC20.connect(addr1).approve(vaultis.target, depositAmount - ethers.parseEther("0.1")); 

      await expect(vaultis.connect(addr1).enterGame(riddleId))
        .to.be.revertedWith("ERC20: transfer amount exceeds allowance");

      // Verify no state change
      expect(await mockERC20.balanceOf(vaultis.target)).to.equal(0);
      expect(await vaultis.hasPlayerEntered(addr1.address)).to.be.false;
    });

    it("Should revert if the user has insufficient balance", async function () {
      // Burn tokens to ensure insufficient balance (already minted in beforeEach)
      await mockERC20.connect(addr1).transfer(addr2.address, depositAmount); // Transfer all to addr2
      await mockERC20.mint(addr1.address, depositAmount - ethers.parseEther("0.1")); // Now addr1 has insufficient balance

      // Approve enough (allowance is reset in beforeEach, so we need to set it again after burning)
      await mockERC20.connect(addr1).approve(vaultis.target, depositAmount);

      await expect(vaultis.connect(addr1).enterGame(riddleId))
        .to.be.revertedWith("ERC20: transfer amount exceeds balance");

      // Verify no state change
      expect(await mockERC20.balanceOf(vaultis.target)).to.equal(0);
      expect(await vaultis.hasPlayerEntered(addr1.address)).to.be.false;
    });
  });
  });
});
