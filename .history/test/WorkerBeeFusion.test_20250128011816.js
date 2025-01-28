// test/WorkerBeeFusion.test.js

const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("WorkerBeeFusion - Test Suite", function () {
  let deployer, user, user2;
  let main, fusion;

  // Adjust these if your WorkerBeeNFTMain constructor / initializer is different
  async function deployWorkerBeeMain() {
    const WorkerBeeMain = await ethers.getContractFactory("WorkerBeeNFTMain");
    // Example arguments for your main contract's initialize(...) 
    // (kingBee, queenBeeCouncil, oracleTreasury, inquisitorTreasury, droneTreasury)
    const mainProxy = await upgrades.deployProxy(
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
    await mainProxy.waitForDeployment();
    return mainProxy;
  }

  async function deployWorkerBeeFusion(beeMainAddress) {
    const Fusion = await ethers.getContractFactory("WorkerBeeFusion");
    // We'll deploy it as a UUPS Proxy 
    // (if you want a direct deploy, remove upgrades.deployProxy(...) usage)
    const fusionProxy = await upgrades.deployProxy(
      Fusion,
      [beeMainAddress],
      { initializer: "initialize" }
    );
    await fusionProxy.waitForDeployment();
    return fusionProxy;
  }

  beforeEach(async () => {
    [deployer, user, user2] = await ethers.getSigners();

    // 1) Deploy main (upgradeable)
    main = await deployWorkerBeeMain();

    // 2) Deploy fusion (upgradeable)
    fusion = await deployWorkerBeeFusion(await main.getAddress());
  });

  describe("Initialization checks", function () {
    it("sets the correct main contract reference", async () => {
      // beeMain is public in the fusion contract
      const storedMainAddr = await fusion.beeMain();
      expect(storedMainAddr).to.equal(await main.getAddress());
    });
  });

  describe("fuseBees(...) logic", function () {
    it("reverts if fewer than 2 parents", async () => {
      await expect(
        fusion.connect(user).fuseBees([1], "fused-uri")
      ).to.be.revertedWith("Need >=2 bees");
    });

    it("reverts if caller doesn't own all parents", async () => {
      // user mints 2 Worker bees
      await main.connect(user).publicMint("worker-uri1", ethers.ZeroHash, {
        value: ethers.parseEther("0.01"),
      });
      // user2 mints one
      await main.connect(user2).publicMint("worker-uri2", ethers.ZeroHash, {
        value: ethers.parseEther("0.01"),
      });

      // user tries to fuse tokens (1,2) but user2 owns #2
      await expect(
        fusion.connect(user).fuseBees([1, 2], "fused-uri")
      ).to.be.revertedWith("Not owner");
    });

    it("successfully creates a pending fusion request and returns fusionId", async () => {
      // user mints tokens #1,2,3
      for (let i = 0; i < 3; i++) {
        await main.connect(user).publicMint(`uri-${i}`, ethers.ZeroHash, {
          value: ethers.parseEther("0.01"),
        });
      }
      // fuse tokens [1, 2]
      const tx = await fusion.connect(user).fuseBees([1, 2], "fused-parent-1-2");
      const rc = await tx.wait();

      // check event
      const ev = rc.logs.map(log => {
        try {
          return fusion.interface.parseLog(log);
        } catch {
          return null;
        }
      }).filter(Boolean).find(e => e.name === "FusionRequested");
      expect(ev).to.exist;
      expect(ev.args.user).to.equal(user.address);
      expect(ev.args.parentIds.map(id => id.toNumber())).to.eql([1, 2]);

      // The function returns the fusionId (fusionCounter)
      const fusionId = await tx.getReturnValue(); // Hardhat >= 6
      // Alternatively, parse from the transaction's custom event or read fusion.fusionCounter()

      expect(fusionId).to.equal(1n);
      const pf = await fusion.pendingFusions(fusionId);
      expect(pf.user).to.equal(user.address);
      expect(pf.parentIds.length).to.equal(2);
    });

    it("fails when paused", async () => {
      await fusion.pause();
      expect(await fusion.paused()).to.equal(true);
      await expect(
        fusion.connect(user).fuseBees([1, 2], "someURI")
      ).to.be.revertedWith("Pausable: paused");
    });
  });

  describe("finalizeFusion(...) logic", function () {
    beforeEach(async () => {
      // Mint 2 bees to user
      await main.connect(user).publicMint("bee1", ethers.ZeroHash, {
        value: ethers.parseEther("0.01"),
      });
      await main.connect(user).publicMint("bee2", ethers.ZeroHash, {
        value: ethers.parseEther("0.01"),
      });
      // user calls fuseBees
      await fusion.connect(user).fuseBees([1, 2], "fused-1-2");
    });

    it("reverts if not called by owner", async () => {
      await expect(
        fusion.connect(user).finalizeFusion(1)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("reverts for invalid fusionId", async () => {
      // even as owner
      await expect(
        fusion.finalizeFusion(999)
      ).to.be.revertedWith("Invalid fusion request");
    });

    it("burns parents, mints new, and emits BeeFused", async () => {
      // BEFORE finalize
      expect(await main.ownerOf(1)).to.equal(user.address);
      expect(await main.ownerOf(2)).to.equal(user.address);
      expect(await main.totalMintedOverall()).to.equal(2);

      // finalize as contract owner
      const tx = await fusion.finalizeFusion(1);
      const rc = await tx.wait();

      // AFTER finalize: parents #1, #2 are burned
      await expect(main.ownerOf(1)).to.be.revertedWith("ERC721: invalid token ID");
      await expect(main.ownerOf(2)).to.be.revertedWith("ERC721: invalid token ID");

      // new minted token => totalMintedOverall = 3
      expect(await main.totalMintedOverall()).to.equal(3);

      // check event BeeFused
      const ev = rc.logs.map(log => {
        try {
          return fusion.interface.parseLog(log);
        } catch {
          return null;
        }
      }).filter(Boolean).find(e => e.name === "BeeFused");

      expect(ev).to.exist;
      const parentIds = ev.args.parentIds.map(x => x.toNumber());
      const newTokenId = ev.args.newTokenId;
      const newTier = ev.args.newTier;

      expect(parentIds).to.eql([1, 2]);
      expect(newTokenId).to.equal(3n);
      // newTier is derived from `_calculateTierByAncestry(ancestry)`
      // for 2 Worker bees => ancestry=1+1=2 => returns 0 => Tier.Worker
      expect(newTier).to.equal(0);

      // the new token #3 should be owned by user
      expect(await main.ownerOf(3)).to.equal(user.address);
    });
  });
});
