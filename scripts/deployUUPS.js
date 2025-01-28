const { ethers, upgrades } = require("hardhat");

async function main() {
  // Suppose you already deployed WorkerBeeNFTMain (proxy).
  // Deploy a mock VRF or real VRF coordinator, then do:
  const WorkerBeeVRF = await ethers.getContractFactory("WorkerBeeVRF");

  // Example arguments for `initialize(...)`
  const mainContractAddr = "0xYOUR_MAIN_CONTRACT_ADDRESS";
  const VRF_KEY_HASH = ethers.keccak256(ethers.toUtf8Bytes("test_key_hash"));
  const VRF_FEE = ethers.parseEther("0.0001");
  const VRF_COORDINATOR_ADDR = "0xMOCK_OR_REAL_VRF_ADDRESS";
  const VRF_SUB_ID = 1;

  const workerBeeVRF = await upgrades.deployProxy(
    WorkerBeeVRF,
    [mainContractAddr, VRF_KEY_HASH, VRF_FEE, VRF_COORDINATOR_ADDR, VRF_SUB_ID],
    {
      kind: "uups",
      initializer: "initialize"
    }
  );

  await workerBeeVRF.waitForDeployment();
  console.log("WorkerBeeVRF Proxy deployed to:", await workerBeeVRF.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
