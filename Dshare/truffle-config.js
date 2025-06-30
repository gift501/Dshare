require('dotenv').config();
const HDWalletProvider = require('@truffle/hdwallet-provider');
const path = require("path");

// Make sure your .env file has PRIVATE_KEY and SEPOLIA_URL defined
const privateKey = process.env.PRIVATE_KEY;
const sepoliaUrl = process.env.SEPOLIA_URL;

module.exports = {
  networks: {
    sepolia: {
      provider: () => {
        // Check if privateKey is defined before creating provider
        if (!privateKey) {
            throw new Error("PRIVATE_KEY not found in .env. Please set it.");
        }
        if (!sepoliaUrl) {
            throw new Error("SEPOLIA_URL not found in .env. Please set it.");
        }
        return new HDWalletProvider({
          privateKeys: [privateKey], // Use 'privateKeys' for a single private key string
          providerOrUrl: sepoliaUrl,
          numberOfAddresses: 1, // Only one address is managed by this private key
          shareNonce: true,
          pollingInterval: 8000 // Standard polling interval
        });
      },
      network_id: 11155111,  // CORRECT network ID for Ethereum Sepolia
      confirmations: 2,
      timeoutBlocks: 200,
      skipDryRun: true,
      gas: 5000000, // or 10000000. This is the gas limit for your transaction.
      gasPrice: 10000000000 // Or adjust based on current network conditions (10 Gwei)
    },
    development: {
      host: "127.0.0.1",
      port: 7545,
      network_id: "*",
    },
  },

  contracts_directory: "./contracts",
  contracts_build_directory: "./build/contracts",

  compilers: {
    solc: {
      version: "0.8.20",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        },
        viaIR: true
      }
    }
  },

  mocha: {
    // timeout: 100000
  }
};