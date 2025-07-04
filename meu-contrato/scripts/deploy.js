async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Implantando contrato com a conta:", deployer.address);

  const simpleStorage = await hre.ethers.deployContract("SimpleStorage");

  await simpleStorage.waitForDeployment();

  console.log(
    `Contrato SimpleStorage implantado no endereço: ${simpleStorage.target}`
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});