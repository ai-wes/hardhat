// test/WorkerBeeNFTMain.test.js
const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("WorkerBeeNFTMain - Comprehensive Test Suite", function () {
  let deployer, user, user2, user3;
  let main, vrf;
  const VRF_SUB_ID = 1;
  // v6: ethers.solidityPacked / ethers.hashData or just mock
  const VRF_KEY_HASH = ethers.keccak256(ethers.toUtf8Bytes("test_key_hash"));

  let kingBeeAddr, queenBeeAddr, oracleAddr, inquisitorAddr, droneAddr;

  beforeEach(async () => {
    [deployer, user, user2, user3] = await ethers.getSigners();
    kingBeeAddr = await user.getAddress();
    queenBeeAddr = await user2.getAddress();
    oracleAddr = await user3.getAddress();
    inquisitorAddr = await user3.getAddress();
    droneAddr = await deployer.getAddress();

    // Deploy a Mock VRFCoordinatorV2 for demonstration
    const MockVRFCoordinator = await ethers.getContractFactory("MockVRFCoordinatorV2");
    vrf = await MockVRFCoordinator.deploy();
    await vrf.waitForDeployment();

    // Deploy WorkerBeeNFTMain via upgradeable proxy
    const WorkerBeeMain = await ethers.getContractFactory("WorkerBeeNFTMain");
    main = await upgrades.deployProxy(
      WorkerBeeMain,
      [kingBeeAddr, queenBeeAddr, oracleAddr, inquisitorAddr, droneAddr],
      { initializer: "initialize" }
    );
    await main.waitForDeployment();
  });

  describe("Initialization", () => {
    it("initializes with correct roles and supply tracking", async () => {
      expect(await main.kingBee()).to.equal(kingBeeAddr);
      expect(await main.queenBeeCouncil()).to.equal(queenBeeAddr);

      const maxWorkerBee = await main.MAX_SUPPLY_WorkerBee();
      expect(maxWorkerBee).to.equal(2200);
    });

    it("contract is unpaused by default", async () => {
      expect(await main.paused()).to.equal(false);
    });
  });

  describe("Minting", () => {
    it("allows publicMint with insufficient payment", async () => {
      await expect(
        main.connect(user).publicMint("uri-for-worker", ethers.ZeroHash, {
          value: ethers.parseEther("0.009")
        })
      ).to.be.revertedWith("Insufficient payment");
    });

    it("allows publicMint with correct payment", async () => {
      await expect(
        main.connect(user).publicMint("uri-for-worker", ethers.ZeroHash, {
          value: ethers.parseEther("0.01")
        })
      ).to.emit(main, "BeeNFTMinted");
    });

    it("specialized mint for Drone requires correct payment", async () => {
      // DRONE_PRICE = 0.03 - (0.03 * 12/100) => 0.0264
      const requiredPayment = ethers.parseEther("0.0264");

      await expect(
        main.connect(user).mintDrone("drone-uri", {
          value: ethers.parseEther("0.02")
        })
      ).to.be.revertedWith("Not enough ETH for Drone");

      // Should succeed
      await expect(
        main.connect(user).mintDrone("drone-uri", {
          value: requiredPayment
        })
      ).to.emit(main, "BeeNFTMinted");
    });

    it("finalizes VRF (publicMint) with the correct tier (simulated)", async () => {
      // This test tries to replicate old logic: if totalMintedOverall < 300 => minted as Drone
      await main.connect(user).publicMint("my-early-uri", ethers.ZeroHash, {
        value: ethers.parseEther("0.01")
      });

      // We won't do real VRF calls here; just verify the minted tier is Drone:
      const mintedTier = await main.beeInfo(1); 
      expect(mintedTier).to.equal(1);
        });
  });

  describe("Fusion", () => {
    it("fuseBees requires user to own all tokens, etc.", async () => {
      // Mint two drones
      const dronePayment = ethers.parseEther("0.0264");
      await main.connect(user).mintDrone("drone1", { value: dronePayment });
      await main.connect(user).mintDrone("drone2", { value: dronePayment });

      // Fuse them
      await expect(
        main.connect(user).fuseBees([1, 2], "fused-drone-uri")
      ).to.emit(main, "FusionRequested");

      // Check new token (tokenId=3) is minted and owned by user
      const ownerOf3 = await main.ownerOf(3);
      expect(ownerOf3).to.equal(await user.getAddress());

      // The tokens 1 and 2 are burned, so ownerOf should revert
      await expect(main.ownerOf(1)).to.be.revertedWith("ERC721: invalid token ID");
      await expect(main.ownerOf(2)).to.be.revertedWith("ERC721: invalid token ID");
    });
  });

  describe("Decrees (Discount System)", () => {
    it("issueKingsDecree sets discount, usage limit, expiry, etc.", async () => {
      const decId = ethers.encodeBytes32String("TEST");
      await expect(
        main.issueKingsDecree(decId, 500, 10, 2)
      ).to.emit(main, "DecreeIssued");

      const isValid = await main.isDecreeValid(decId);
      expect(isValid).to.equal(true);

      // 500 bips => 5% discount
      const discPrice = await main.getDecreePrice(decId, ethers.parseEther("1"));
      expect(discPrice).to.equal(ethers.parseEther("0.95"));
    });

    it("revokes decree", async () => {
      const decId = ethers.encodeBytes32String("TEST");
      await main.issueKingsDecree(decId, 500, 10, 2);

      await expect(
        main.revokeKingsDecree(decId)
      ).to.emit(main, "DecreeRevoked");

      const isValid = await main.isDecreeValid(decId);
      expect(isValid).to.equal(false);
    });
  });

  describe("Revenue Sharing", () => {
    it("withdraw distributes funds when same account does deposit", async () => {
      const oneEther = ethers.parseEther("1");
      
      // Deposit 1 ETH to contract
      await deployer.sendTransaction({
        to: await main.getAddress(),
        value: oneEther
      });
      
      // Withdraw funds
      const withdrawTx = await main.withdraw();
      const withdrawRc = await withdrawTx.wait();
      
      // Parse withdraw event logs
      const parsedLogs = withdrawRc.logs
        .map(log => {
          try { return main.interface.parseLog(log); }
          catch { return null; }
        })
        .filter(Boolean);
      
      // Get owner's withdrawn amount from event
      const eventOwner = parsedLogs.find(e => 
        e.name === "RevenueWithdrawn" && 
        e.args.recipient === deployer.address
      );
      
      // Expected: 3% of 1 ETH = 0.03 ETH (30000000000000000 wei)
      const expectedShare = (oneEther * BigInt(300)) / BigInt(10000); // 3% = 300 basis points
      expect(eventOwner.args.amount).to.equal(expectedShare);
    });
  });
  
  
  describe("Pause/Unpause", () => {
    it("owner can pause, non-owner fails", async () => {
      await main.pause();
      expect(await main.paused()).to.equal(true);

      await expect(main.connect(user).unpause()).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
      await main.unpause();
      expect(await main.paused()).to.equal(false);
    });

    it("publicMint fails when paused", async () => {
      await main.pause();
      await expect(
        main.connect(user).publicMint("xxx", ethers.ZeroHash, {
          value: ethers.parseEther("0.01")
        })
      ).to.be.revertedWith("Pausable: paused");
    });
  });
});
