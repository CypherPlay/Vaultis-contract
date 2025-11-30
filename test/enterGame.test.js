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
  });

  describe("enterGame", function () {
    it("Should allow a user to enter the game with a minimum deposit", async function () {
      const depositAmount = ethers.parseEther("10");

      // Mint tokens to addr1
      await mockERC20.mint(addr1.address, depositAmount);

      // Approve the Vaultis contract to spend tokens on behalf of addr1
      await mockERC20.connect(addr1).approve(vaultis.target, depositAmount);

      // addr1 enters the game
      await expect(vaultis.connect(addr1).enterGame(depositAmount))
        .to.emit(vaultis, "GameEntered")
        .withArgs(addr1.address, depositAmount);

      // Assertions
      expect(await mockERC20.balanceOf(vaultis.target)).to.equal(depositAmount);
      expect(await vaultis.isParticipating(addr1.address)).to.be.true;
    });

    it("Should revert if the deposit amount is less than the minimum", async function () {
      const depositAmount = ethers.parseEther("0"); // Less than minimum

      // Expect the transaction to revert
      await expect(vaultis.connect(addr1).enterGame(depositAmount)).to.be.revertedWith("Deposit amount must be greater than zero");
    });
  });
});
