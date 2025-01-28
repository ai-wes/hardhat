const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("WorkerBeeVRF - Integration with WorkerBeeNFTMain", function () {
  let deployer, user, user2;
  let main, vrf, workerBeeVRF;
  const VRF_SUB_ID = 1;
  const VRF_KEY_HASH = ethers.keccak256(ethers.toUtf8Bytes("vrf_key_hash"));
  const VRF_FEE = ethers.parseEther("0.0001");

  beforeEach(async () => {
    [deployer, user, user2] = await ethers.getSigners();

    // 1) Deploy MockVRFCoordinator with the updated code above
    const MockVRFCoordinator = await ethers.getContractFactory("MockVRFCoordinatorV2");
    vrf = await MockVRFCoordinator.deploy();
    await vrf.waitForDeployment();

    // 2) Deploy WorkerBeeNFTMain
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

    // 3) Deploy WorkerBeeVRF
    const WorkerBeeVRF_Factory = await ethers.getContractFactory("WorkerBeeVRF");
    workerBeeVRF = await WorkerBeeVRF_Factory.deploy(await vrf.getAddress());
    await workerBeeVRF.waitForDeployment();

    // 4) Initialize the VRF contract
    await workerBeeVRF.initialize(
      await main.getAddress(),
      VRF_KEY_HASH,
      VRF_FEE,
      await vrf.getAddress(),
      VRF_SUB_ID
    );
  });

  describe("VRF-Based Minting", function () {
    it("publicMint requests random words and finalizes with fulfillRandomWords", async () => {
      // BEFORE: totalMintedOverall should be 0
      expect(await main.totalMintedOverall()).to.equal(0);

      // 1) user calls publicMint
      const pubMintTx = await workerBeeVRF.connect(user).publicMint("myUri", ethers.ZeroHash, {
        value: ethers.parseEther("0.01"),
      });
      await pubMintTx.wait();

      // 2) Check the mock VRF for the new requestId
      const requestId = await vrf.lastRequestId();
      expect(requestId).to.not.equal(0n);

      // 3) Fulfill with the same requestId
      await vrf.fulfillRandomWords(requestId, [1234, 5678]); // randomWords array

      // AFTER: totalMintedOverall should now be 1
      expect(await main.totalMintedOverall()).to.equal(1);
    });

    it("mintDrone requests VRF and finalizes an instant Drone mint upon fulfillment", async () => {
      expect(await main.totalMintedOverall()).to.equal(0);

      // 1) user calls mintDrone
      const tx = await workerBeeVRF.connect(user).mintDrone("droneURI", {
        value: ethers.parseEther("0.0264"),
      });
      await tx.wait();

      // 2) Get the matching requestId from the mock
      const requestId = await vrf.lastRequestId();
      expect(requestId).to.not.equal(0n);

      // 3) Fulfill the VRF request 
      //    This triggers _finalizeInstantMint inside WorkerBeeVRF
      await vrf.fulfillRandomWords(requestId, [987654321]);

      // Should be minted now
      expect(await main.totalMintedOverall()).to.equal(1n);

      // Check token ownership & tier
      const tokenId = 1n;
      expect(await main.ownerOf(tokenId)).to.equal(user.address);
      const beeData = await main.beeInfo(tokenId);
      // Tier(1) => Drone
      expect(beeData).to.equal(1n); 
    });
  });
});
