const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("WorkBeeVRF - Integration with WorkerBeeNFTMain", function () {
  let deployer, user, user2;
  let main, vrf, workBeeVRF;
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

    // 3) Deploy WorkBeeVRF (with the VRFConsumerBase constructor arg)
    const WorkBeeVRF = await ethers.getContractFactory("WorkBeeVRF");
    // The constructor for WorkBeeVRF is: constructor(address vrfCoordinator)
    // We'll pass the mock VRF coordinator address
    workBeeVRF = await WorkBeeVRF.deploy(await vrf.getAddress());
    await workBeeVRF.waitForDeployment();

    // 4) Initialize the VRF contract
    //    function initialize(
    //      address _mainContract,
    //      bytes32 _vrfKeyHash,
    //      uint256 _vrfFee,
    //      address vrfCoordinatorAddress,
    //      uint64 subscriptionId
    //    )
    await workBeeVRF.initialize(
      await main.getAddress(),
      VRF_KEY_HASH,
      VRF_FEE,
      await vrf.getAddress(),
      VRF_SUB_ID
    );
  });

  describe("Initialization", function () {
    it("sets the mainContract and VRF config correctly", async () => {
      const storedMain = await workBeeVRF.workerBeeNFTMain();
      expect(storedMain).to.equal(await main.getAddress());

      const storedSubId = await workBeeVRF.vrfSubscriptionId();
      expect(storedSubId).to.equal(VRF_SUB_ID);
    });
  });

  describe("VRF-Based Minting", function () {
    it("publicMint requests random words and stores pendingMint", async () => {
      // 1) Call publicMint on WorkBeeVRF
      const tx = await workBeeVRF.connect(user).publicMint("someUri", ethers.ZeroHash, {
        value: ethers.parseEther("0.01"),
      });
      await tx.wait();

      // 2) Check that the mock VRF coordinator recorded a requestId
      const requestId = await vrf.lastRequestId();
      expect(requestId).to.not.equal(0n);

      // 3) Confirm there's a pendingMint in the VRF contract
      const pm = await workBeeVRF.pendingMints(requestId);
      expect(pm.recipient).to.equal(user.address);
      expect(pm.uri).to.equal("someUri");
      expect(pm.decreeId).to.equal(ethers.ZeroHash);
      expect(pm.paid).to.equal(ethers.parseEther("0.01"));
    });

    it("fulfillRandomWords finalizes a standard publicMint with Worker or Drone tier", async () => {
      // user calls publicMint
      await workBeeVRF.connect(user).publicMint("myUri", ethers.ZeroHash, {
        value: ethers.parseEther("0.01"),
      });
      const requestId = await vrf.lastRequestId();

      // 1) Attempt to fulfill random words
      // The first fulfill might only store the data (depending on your mock),
      // So we call fulfillRandomWords twice if needed
      await vrf.fulfillRandomWords(requestId, workBeeVRF.getAddress());
      // In your mock VRF, you might call it once or twice. Adjust as needed:
      await vrf.fulfillRandomWords(requestId, workBeeVRF.getAddress());

      // 2) Now check that the main contract minted a new token
      const totalMinted = await main.totalMintedOverall();
      expect(totalMinted).to.equal(1);

      // The newly minted token is tokenId=1, owner = user
      const ownerOf1 = await main.ownerOf(1);
      expect(ownerOf1).to.equal(user.address);
    });

    it("mintDrone requests VRF and finalizes an instant Drone mint upon fulfillment", async () => {
      // 1) user calls mintDrone
      const tx = await workBeeVRF.connect(user).mintDrone("droneURI", {
        value: ethers.parseEther("0.0264"),
      });
      await tx.wait();

      const requestId = await vrf.lastRequestId();
      expect(requestId).to.not.equal(0n);

      const pm = await workBeeVRF.pendingInstantMints(requestId);
      expect(pm.minter).to.equal(user.address);
      expect(pm.tier).to.equal(1); // Drone = 1
      expect(pm.designatedURI).to.equal("droneURI");

      // 2) fulfillRandomWords
      await vrf.fulfillRandomWords(requestId, workBeeVRF.getAddress());
      await vrf.fulfillRandomWords(requestId, workBeeVRF.getAddress());

      // 3) check minted on main
      const totalMinted = await main.totalMintedOverall();
      expect(totalMinted).to.equal(1);

      const info = await main.beeInfo(1);
      expect(info.tier).to.equal(1); // Drone
      expect(await main.ownerOf(1)).to.equal(user.address);
    });
  });

  describe("Pause / Unpause", () => {
    it("pauses and reverts publicMint", async () => {
      await workBeeVRF.pause();
      expect(await workBeeVRF.paused()).to.equal(true);

      await expect(
        workBeeVRF.connect(user).publicMint("xxx", ethers.ZeroHash, {
          value: ethers.parseEther("0.01"),
        })
      ).to.be.revertedWith("Pausable: paused");

      await workBeeVRF.unpause();
      expect(await workBeeVRF.paused()).to.equal(false);
    });
  });
});
