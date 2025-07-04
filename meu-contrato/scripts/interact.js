const { ethers } = require("hardhat");

// Cole aqui o endereço do seu contrato implantado
const CONTRACT_ADDRESS = "0xa50a51c09a5c451C52BB714527E1974b686D8e77"; 

async function main() {
  console.log("A conectar-se ao contrato no endereço:", CONTRACT_ADDRESS);

  const SimpleStorage = await ethers.getContractFactory("SimpleStorage");
  const contract = SimpleStorage.attach(CONTRACT_ADDRESS);

  // 1. Ler o valor inicial
  let currentValue = await contract.retrieve();
  console.log(`O valor armazenado atual é: ${currentValue}`);

  // 2. Escrever um novo valor
  console.log("A enviar uma transação para armazenar o valor 100...");
  const tx = await contract.store(100);
  await tx.wait(); // Aguardar a mineração da transação
  console.log("Transação confirmada!");

  // 3. Ler o novo valor para confirmar
  currentValue = await contract.retrieve();
  console.log(`O novo valor armazenado é: ${currentValue}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});