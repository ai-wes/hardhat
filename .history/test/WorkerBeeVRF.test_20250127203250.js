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

    // 3) Deploy WorkerBeeVRF with the mock VRF coordinator address in the constructor
// 3) Deploy WorkerBeeVRF with the mock VRF coordinator address in the constructor
const WorkerBeeVRF_Factory = await ethers.getContractFactory("WorkerBeeVRF");
workerBeeVRF = await WorkerBeeVRF_Factory.deploy(
    await vrf.getAddress(),
    {
        gasLimit: 30000005 // Add appropriate gas limit
    }
);
await workerBeeVRF.waitForDeployment();

    // 4) Initialize the VRF contract
    //    function initialize(
    //      address _mainContract,
    //      bytes32 _vrfKeyHash,
    //      uint256 _vrfFee,
    //      address vrfCoordinatorAddress,
    //      uint64 subscriptionId
    //    )
    await workerBeeVRF.initialize(
      await main.getAddress(),
      VRF_KEY_HASH,
      VRF_FEE,
      await vrf.getAddress(),
      VRF_SUB_ID
    );
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
      // user calls publicMint
      await workerBeeVRF.connect(user).publicMint("myUri", ethers.ZeroHash, {
        value: ethers.parseEther("0.01"),
      });
      const requestId = await vrf.lastRequestId();

      // 1) Attempt to fulfill random words
      // Depending on the MockVRF implementation, we might call it twice.
      await vrf.fulfillRandomWords(requestId, workerBeeVRF.getAddress());
      await vrf.fulfillRandomWords(requestId, workerBeeVRF.getAddress());

      // 2) Now check that the main contract minted a new token
      const totalMinted = await main.totalMintedOverall();
      expect(totalMinted).to.equal(1n);

      // The newly minted token is tokenId=1, owner = user
      const ownerOf1 = await main.ownerOf(1);
      expect(ownerOf1).to.equal(user.address);
    });

    it("mintDrone requests VRF and finalizes an instant Drone mint upon fulfillment", async () => {
      // 1) user calls mintDrone
      const tx = await workerBeeVRF.connect(user).mintDrone("droneURI", {
        value: ethers.parseEther("0.0264"),
      });
      await tx.wait();

      const requestId = await vrf.lastRequestId();
      expect(requestId).to.not.equal(0n);

      const pm = await workerBeeVRF.pendingInstantMints(requestId);
      expect(pm.minter).to.equal(user.address);
      expect(pm.tier).to.equal(1); // Drone = 1
      expect(pm.designatedURI).to.equal("droneURI");

      // 2) fulfillRandomWords
      await vrf.fulfillRandomWords(requestId, workerBeeVRF.getAddress());
      await vrf.fulfillRandomWords(requestId, workerBeeVRF.getAddress());

      // 3) check minted on main
      const totalMinted = await main.totalMintedOverall();
      expect(totalMinted).to.equal(1n);

      const info = await main.beeInfo(1);
      expect(info.tier).to.equal(1); // Drone
      expect(await main.ownerOf(1)).to.equal(user.address);
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
