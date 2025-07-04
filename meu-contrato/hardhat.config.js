require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",
  networks: {
    besu: {
      url: "http://127.0.0.1:8545", // URL RPC do seu node1
      accounts: ['8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63'] // Chave privada da conta com fundos
    }
  }
};