// test/WorkerBeeVRF.test.js

const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("WorkerBeeVRF - Integration with WorkerBeeNFTMain", function () {
  let deployer, user, user2;
  let main, vrf, workerBeeVRF;
  const VRF_SUB_ID = 1;
  // Dummy VRF key hash
  const VRF_KEY_HASH = ethers.keccak256(ethers.toUtf8Bytes("vrf_key_hash"));
  const VRF_FEE = ethers.parseEther("0.0001");

  beforeEach(async () => {
    [deployer, user, user2] = await ethers.getSigners();

    // 1) Deploy a MockVRFCoordinator to simulate VRF calls
    const MockVRFCoordinator = await ethers.getContractFactory("MockVRFCoordinatorV2");
    vrf = await MockVRFCoordinator.deploy();
    await vrf.waitForDeployment();

    // 2) Deploy WorkerBeeNFTMain (upgradeable)
    const WorkerBeeMain = await ethers.getContractFactory("WorkerBeeNFTMain");
    main = await upgrades.deployProxy(
      WorkerBeeMain,
      [
        deployer.address, // kingBee
        user.address,     // queenBeeCouncil
        user2.address,    // oracleTreasury
        user2.address,    // inquisitorTreasury
        deployer.address  // droneTreasury
      ],
      { initializer: "initialize" }
    );
    await main.waitForDeployment();

    // 3) Deploy WorkerBeeVRF with the mock VRF coordinator address
    const WorkerBeeVRF_Factory = await ethers.getContractFactory("WorkerBeeVRF");
    workerBeeVRF = await WorkerBeeVRF_Factory.deploy(
        await vrf.getAddress(),
        {
            gasLimit: 30000005
        }
    );
    await workerBeeVRF.waitForDeployment();

    // 4) Initialize the VRF contract
    await workerBeeVRF.initialize(
      await main.getAddress(),
      VRF_KEY_HASH,
      VRF_FEE,
      await vrf.getAddress(),
      VRF_SUB_ID
    );

    // 5) Grant minting permission to WorkerBeeVRF contract
    // The deployer should have DEFAULT_ADMIN_ROLE and can grant MINTER_ROLE
    const DEFAULT_ADMIN_ROLE = ethers.ZeroHash;
    const MINTER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
    
    // Verify deployer has admin role
    expect(await main.hasRole(DEFAULT_ADMIN_ROLE, deployer.address)).to.be.true;
    
    // Grant MINTER_ROLE to WorkerBeeVRF contract
    await main.connect(deployer).grantRole(MINTER_ROLE, await workerBeeVRF.getAddress());
  });

  describe("Initialization", function () {
    it("sets the mainContract and VRF config correctly", async () => {
      const storedMain = await workerBeeVRF.workerBeeNFTMain();
      expect(storedMain).to.equal(await main.getAddress());

      const storedSubId = await workerBeeVRF.vrfSubscriptionId();
      expect(storedSubId).to.equal(VRF_SUB_ID);
    });
  });

  describe("VRF-Based Minting", function () {
    it("publicMint requests random words and stores pendingMint", async () => {
      // 1) Call publicMint on WorkerBeeVRF
      const tx = await workerBeeVRF.connect(user).publicMint("someUri", ethers.ZeroHash, {
        value: ethers.parseEther("0.01"),
      });
      await tx.wait();

      // 2) Check that the mock VRF coordinator recorded a requestId
      const requestId = await vrf.lastRequestId();
      expect(requestId).to.not.equal(0n);

      // 3) Confirm there's a pendingMint in the VRF contract
      const pm = await workerBeeVRF.pendingMints(requestId);
      expect(pm.recipient).to.equal(user.address);
      expect(pm.uri).to.equal("someUri");
      expect(pm.decreeId).to.equal(ethers.ZeroHash);
      expect(pm.paid).to.equal(ethers.parseEther("0.01"));
    });

    
    it("fulfillRandomWords finalizes a standard publicMint with Worker or Drone tier", async () => {
        // Initial check
        expect(await main.totalMintedOverall()).to.equal(0n);

        const tx = await workerBeeVRF.connect(user).publicMint("myUri", ethers.ZeroHash, {
            value: ethers.parseEther("0.01"),
        });
        await tx.wait();
        
        const requestId = await vrf.lastRequestId();
        const randomWords = [ethers.toBigInt("123456789")];
        
        // Fulfill the VRF request
        await vrf.fulfillRandomWords(requestId, randomWords);
        
        // Verify minting occurred
        expect(await main.totalMintedOverall()).to.equal(1n);
        
        // Verify token ownership
        const tokenId = 1n;
        expect(await main.ownerOf(tokenId)).to.equal(user.address);
    });

    it("mintDrone requests VRF and finalizes an instant Drone mint upon fulfillment", async () => {
        // Initial check
        expect(await main.totalMintedOverall()).to.equal(0n);

        const tx = await workerBeeVRF.connect(user).mintDrone("droneURI", {
            value: ethers.parseEther("0.0264"),
        });
        await tx.wait();

        const requestId = await vrf.lastRequestId();
        const randomWords = [ethers.toBigInt("123456789")];
        
        // Fulfill the VRF request
        await vrf.fulfillRandomWords(requestId, randomWords);
        
        // Verify minting occurred
        expect(await main.totalMintedOverall()).to.equal(1n);
        
        // Verify token ownership and tier
        const tokenId = 1n;
        expect(await main.ownerOf(tokenId)).to.equal(user.address);
        expect(await main.beeInfo(tokenId)).to.equal(1n); // Tier.Drone = 1
    });
  });

  describe("Pause / Unpause", () => {
    it("pauses and reverts publicMint", async () => {
      await workerBeeVRF.pause();
      expect(await workerBeeVRF.paused()).to.equal(true);

      await expect(
        workerBeeVRF.connect(user).publicMint("xxx", ethers.ZeroHash, {
          value: ethers.parseEther("0.01"),
        })
      ).to.be.revertedWith("Pausable: paused");

      await workerBeeVRF.unpause();
      expect(await workerBeeVRF.paused()).to.equal(false);
    });
  });
});
