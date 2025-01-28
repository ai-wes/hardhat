require("@nomicfoundation/hardhat-ethers");
require("@nomicfoundation/hardhat-toolbox");
require("@openzeppelin/hardhat-upgrades");

// Fix: Define the amount directly without parseEther
module.exports = {
  solidity: {
    compilers: [
      {
        version: '0.8.28',
        settings: {
          optimizer: {
            enabled: true,
            runs: 50
          },
          viaIR: false,
        }
      }
    ]
  },
    //defaultNetwork: "polygon_amoy",
    networks: {
      hardhat: {
        blockGasLimit: 30000005,
        accounts: {
          count: 20, // Keep plenty of test accounts
          accountsBalance: "10000000000000000000000" // 10000 ETH in wei
        }
      },
      polygon_amoy: {
        url: "https://rpc-amoy.polygon.technology",
        accounts: ["94d5ccd3a0f75d9bfc415c9a82522887d495dc9dbb5c83920fe4199616aa7cb9"],
        chainId: 80002
      }
    },
    etherscan: {
      apiKey: {polygonAmoy: ["W7XQV27VUDXTC51RZBT8R27QE2YKJ11NNX"]},
    },
  
};

