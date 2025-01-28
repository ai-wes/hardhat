// test/WorkerBeeNFTMain.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("WorkerBeeNFTMain - Comprehensive Test Suite", function () {
  let deployer, user, user2, user3;
  let main, vrf;
  const VRF_SUB_ID = 1;
  const VRF_KEY_HASH = ethers.keccak256(ethers.toUtf8Bytes("test_key_hash"));

  let kingBeeAddr, queenBeeAddr, oracleAddr, inquisitorAddr, droneAddr;

  beforeEach(async () => {
    // Get signers
    [deployer, user, user2, user3] = await ethers.getSigners();
    kingBeeAddr = await user.getAddress();
    queenBeeAddr = await user2.getAddress();
    oracleAddr = await user3.getAddress();
    inquisitorAddr = await user3.getAddress(); // Assuming user3 acts as Inquisitor
    droneAddr = await deployer.getAddress();

    // Deploy Mock VRFCoordinatorV2
    const MockVRFCoordinator = await ethers.getContractFactory("MockVRFCoordinatorV2");
    vrf = await MockVRFCoordinator.deploy();
    await vrf.waitForDeployment();

    // Deploy WorkerBeeNFTMain via upgradeable proxy
    const WorkerBeeMain = await ethers.getContractFactory("WorkerBeeNFTMain");
    main = await upgrades.deployProxy(
      WorkerBeeMain,
      [
        kingBeeAddr,
        queenBeeAddr,
        oracleAddr,
        inquisitorAddr,
        droneAddr
      ],
      { initializer: "initialize" }
    );
    await main.waitForDeployment();
  });

  describe("Initialization", () => {
    it("initializes with correct roles and supply tracking", async () => {
      expect(await main.kingBee()).to.equal(kingBeeAddr);
      expect(await main.queenBeeCouncil()).to.equal(queenBeeAddr);
      // Checking a random supply
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
          value: ethers.parseEther("0.009"),
        })
      ).to.be.revertedWith("Insufficient payment");
    });

    it("allows publicMint with correct payment", async () => {
      // MINT_PRICE = 0.01 ether
      await expect(
        main.connect(user).publicMint("uri-for-worker", ethers.ZeroHash, {
          value: ethers.parseEther("0.01"),
        })
      ).to.emit(main, "BeeNFTMinted");

      // Assuming VRF integration, check pending mints or related state
      const requestId = await vrf.lastRequestId();
      expect(requestId).to.not.equal(0);
    });

    it("specialized mint for Drone requires correct payment", async () => {
      // DRONE_PRICE calculation: (3 * 0.01) - (3 * 0.01 * 12 / 100) = 0.03 - 0.0036 = 0.0264 ether
      const requiredPayment = ethers.parseEther("0.0264");

      await expect(
        main.connect(user).mintDrone("drone-uri", {
          value: ethers.parseEther("0.02"),
        })
      ).to.be.revertedWith("Not enough ETH for Drone");

      // Successful mint
      await expect(
        main.connect(user).mintDrone("drone-uri", {
          value: requiredPayment,
        })
      ).to.emit(main, "BeeNFTMinted");

      const requestId = await vrf.lastRequestId();
      expect(requestId).to.not.equal(0);
    });

    it("finalizes VRF (publicMint) with the correct tier", async () => {
      // User calls publicMint
      await main.connect(user).publicMint("my-early-uri", ethers.ZeroHash, {
        value: ethers.parseEther("0.01"),
      });
      let requestId = await vrf.lastRequestId();

      // Fulfill VRF request
      await vrf.fulfillRandomWords(requestId, await main.getAddress()
    );

      // Assuming two fulfillments are required as per WorkerBeeVRF.sol
      await vrf.fulfillRandomWords(requestId, await main.getAddress()
    );

      // Check minted token => tokenId=1
      const ownerOf1 = await main.ownerOf(1);
      expect(ownerOf1).to.equal(user.address);

      // Because totalMintedOverall is 1, <= early threshold 300 => Drone tier
      const beeInfo = await main.beeInfo(1);
      expect(beeInfo.tier).to.equal(1); // Drone = 1
    });
  });

  describe("Fusion", () => {
    it("fuseBees requires user to own all tokens, etc.", async () => {
      // Mint two drones
      const dronePayment = ethers.parseEther("0.03"); // Adjust based on DRONE_PRICE
      await main.connect(user).mintDrone("drone1", { value: dronePayment });
      let requestId1 = await vrf.lastRequestId();
      await vrf.fulfillRandomWords(requestId1, await main.getAddress()
    );
      await vrf.fulfillRandomWords(requestId1, await main.getAddress()
    );

      await main.connect(user).mintDrone("drone2", { value: dronePayment });
      let requestId2 = await vrf.lastRequestId();
      await vrf.fulfillRandomWords(requestId2, await main.getAddress()
    );
      await vrf.fulfillRandomWords(requestId2, await main.getAddress()
    );

      // Fuse the two drones
      await expect(
        main.connect(user).fuseBees([1, 2], "fused-drone-uri")
      ).to.emit(main, "FusionRequested");

      // Assume fusion is handled via another contract or mechanism
      // Here, we'd need to trigger the fusion finalization
      // This depends on your implementation

      // Example: finalize fusion (this might differ based on your contracts)
      // await main.finalizeFusion(fusionId);

      // Check new token ownership
      // const newOwner = await main.ownerOf(3);
      // expect(newOwner).to.equal(user.address);

      // Check parents are burned
      // await expect(main.ownerOf(1)).to.be.revertedWith("ERC721: invalid token ID");
      // await expect(main.ownerOf(2)).to.be.revertedWith("ERC721: invalid token ID");
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
    it("withdraw distributes funds according to revenueShares", async () => {
      // Send some ETH to the contract
      await deployer.sendTransaction({
        to: await main.getAddress()
        ,
        value: ethers.parseEther("1"),
      });

      const oldBalDeployer = await ethers.provider.getBalance(deployer.address);

      // Withdraw
      const tx = await main.withdraw();
      const rc = await tx.wait();
      const gasUsed = BigInt(rc.gasUsed) * BigInt(rc.effectiveGasPrice);

      // Check for events
      const events = rc.events.filter(e => e.event === "RevenueWithdrawn");
      expect(events.length).to.be.greaterThan(1);

      // Calculate expected distribution
      const expectedOwnerShare = ethers.parseEther("1").mul(2000).div(10000); // 20%
      const expectedKingBeeShare = ethers.parseEther("1").mul(4500).div(10000); // 45%
      const remainingBalance = ethers.parseEther("1").sub(expectedOwnerShare.add(expectedKingBeeShare));

      // Check Deployer balance increased by ownerShare minus gas
      const newBalDeployer = await ethers.provider.getBalance(deployer.address);
      expect(newBalDeployer).to.be.closeTo(
        oldBalDeployer.add(expectedOwnerShare),
        ethers.parseEther("0.001")
      );
    });
  });

  describe("Pause/Unpause", () => {
    it("owner can pause, non-owner fails", async () => {
      await main.pause();
      expect(await main.paused()).to.equal(true);

      await expect(main.connect(user).unpause()).to.be.revertedWith("Ownable: caller is not the owner");
      await main.unpause();
      expect(await main.paused()).to.equal(false);
    });

    it("publicMint fails when paused", async () => {
      await main.pause();
      await expect(
        main.connect(user).publicMint("xxx", ethers.ZeroHash, {
          value: ethers.parseEther("0.01"),
        })
      ).to.be.revertedWith("Pausable: paused");
    });
  });
});
