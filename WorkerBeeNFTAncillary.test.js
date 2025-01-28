const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("WorkerBeeNFTAncillary", function () {
  let deployer, user, user2;
  let MockMain, mockMain;
  let MockVRFCoordinator, mockVRF;
  let Ancillary, ancillary;

  const VRF_SUB_ID = 1;
  const VRF_KEY_HASH = ethers.hexlify(ethers.randomBytes(32));
 // Generate a valid random hash
  const VRF_CALLBACK_LIMIT = 2000000;
  const VRF_REQUEST_CONFIRMATIONS = 3;



  beforeEach(async () => {
    // Deploy Mock Main Contract
    const MockMain = await ethers.getContractFactory("MockWorkerBeeNFTMain");
    mockMain = await MockMain.deploy();
    // Ethers v6 => waitForDeployment
    await mockMain.waitForDeployment();
  
    // Deploy Mock VRF
    const MockVRFCoordinator = await ethers.getContractFactory("MockVRFCoordinatorV2");
    mockVRF = await MockVRFCoordinator.deploy();
    await mockVRF.waitForDeployment();
  
    // Deploy the Ancillary Contract
    const Ancillary = await ethers.getContractFactory("WorkerBeeNFTAncillary");
    ancillary = await Ancillary.deploy();
    await ancillary.waitForDeployment();
  
    // Initialize
    await ancillary.initialize(
      await mockVRF.getAddress(),
      VRF_KEY_HASH,
      VRF_SUB_ID,
      VRF_CALLBACK_LIMIT,
      VRF_REQUEST_CONFIRMATIONS
    );
    
  

    // Link the Mock Main Contract
    await ancillary.setMainContract(mockMain.address);

    // Assign token ownership in Mock Main Contract
    await mockMain.setOwnerOf(1, user.address);
    await mockMain.setOwnerOf(2, user.address);
    await mockMain.setOwnerOf(999, user2.address);

    // Initialize token pricing in Ancillary Contract
    await ancillary.initializeTokenPricing();
  });

  describe("Initialization", () => {
    it("initializes the contract with correct values", async () => {
      const vrfCoordinator = await ancillary.vrfCoordinator();
      expect(vrfCoordinator).to.equal(mockVRF.address);

      const paused = await ancillary.paused();
      expect(paused).to.equal(false);
    });

    it("links to the main contract correctly", async () => {
      const mainContract = await ancillary.mainContract();
      expect(mainContract).to.equal(mockMain.address);
    });
  });

  describe("Honey System", () => {
    it("updates honey level correctly", async () => {
      await ancillary.connect(user).updateHoneyLevel(1);
      // Additional checks can be added here based on expected outcomes
    });

    it("requires token ownership for honey update", async () => {
      await expect(
        ancillary.connect(user2).updateHoneyLevel(1)
      ).to.be.revertedWith("Not token owner");
    });
  });

  describe("Token Purchases", () => {
    it("allows users to purchase tokens", async () => {
      const tokenType = 0; // AuraReroll
      await ancillary.connect(user).purchaseTokens(tokenType, 2, {
        value: ethers.parseEther("0.02"),
      });

      const balance = await ancillary.userTokenBalances(user.address, tokenType);
      expect(balance).to.equal(2);
    });

    it("fails if insufficient payment is sent", async () => {
      const tokenType = 0; // AuraReroll
      await expect(
        ancillary.connect(user).purchaseTokens(tokenType, 2, {
          value: ethers.parseEther("0.005"),
        })
      ).to.be.revertedWith("Insufficient payment");
    });
  });

  describe("VRF Functionality", () => {
    it("requests randomness for aura reroll", async () => {
      const tokenType = 0; // AuraReroll
      await ancillary.connect(user).purchaseTokens(tokenType, 1, {
        value: ethers.parseEther("0.01"),
      });

      const tx = await ancillary.connect(user).rerollAura(1);
      const rc = await tx.wait();
      const event = rc.events.find(e => e.event === "TokenUsed");
      expect(event).to.not.equal(undefined);

      const requestId = await mockVRF.lastRequestId();
      expect(requestId).to.not.equal(0);
    });

    it("fulfills randomness and updates aura", async () => {
      const tokenType = 0; // AuraReroll
      await ancillary.connect(user).purchaseTokens(tokenType, 1, {
        value: ethers.parseEther("0.01"),
      });

      const tx = await ancillary.connect(user).rerollAura(1);
      const rc = await tx.wait();
      const requestId = await mockVRF.lastRequestId();

      await mockVRF.fulfillRandomWords(requestId, ancillary.address);

      // We can check logs for "AuraRerolled"
      const finalTx = await mockVRF.fulfillRandomWords(requestId, ancillary.address);
      const finalRc = await finalTx.wait();
      const auraRerolledEvt = finalRc.events.find(e => e.event === "AuraRerolled");
      expect(auraRerolledEvt).to.not.equal(undefined);
    });
  });

  describe("Item Drop (VRF)", () => {
    it("requires user to have ItemDrop tokens", async () => {
      await expect(ancillary.connect(user).useItemDrop(1)).to.be.revertedWith("No item drop tokens");
    });

    it("requests random item drop via VRF", async () => {
      // user buys item drop token
      const tokenType = 1; // ItemDrop
      await ancillary.connect(user).purchaseTokens(tokenType, 1, {
        value: ethers.parseEther("0.015"),
      });

      const tx = await ancillary.connect(user).useItemDrop(1);
      const rc = await tx.wait();
      const event = rc.events.find(e => e.event === "TokenUsed");
      expect(event).to.not.equal(undefined);

      const requestId = await mockVRF.lastRequestId();
      // fulfill
      await mockVRF.fulfillRandomWords(requestId, ancillary.address);

      // check for ItemDropped event
      const finalTx = await mockVRF.fulfillRandomWords(requestId, ancillary.address);
      const finalRc = await finalTx.wait();
      const itemDroppedEvt = finalRc.events.find(e => e.event === "ItemDropped");
      expect(itemDroppedEvt).to.not.equal(undefined);
    });
  });
});
