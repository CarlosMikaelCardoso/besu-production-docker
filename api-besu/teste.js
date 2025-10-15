const { ethers } = require("ethers");

async function main() {
  const provider = new ethers.JsonRpcProvider("http://localhost:8545"); // ou porta certa
  const contractAddress = process.env.CONTRACT_ADDRESS;

  const code = await provider.getCode(contractAddress);
  console.log("Bytecode:", code);
}

main().catch(console.error);
