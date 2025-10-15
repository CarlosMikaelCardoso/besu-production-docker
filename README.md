# Hyperledger Besu - Permissioned QBFT Network

Welcome to the **Besu Production Docker** project! This repository is designed to facilitate the creation and management of a permissioned blockchain network with **Hyperledger Besu**, using the **QBFT** consensus mechanism, ideal for production environments.

## Features

- **Automated Setup:** Scripts that automate the generation of keys, configuration files, and the network's directory structure.
- **Orchestration with Docker:** Use of Docker and Docker-Compose to launch and manage the network nodes in an isolated and consistent manner.
- **Permissioned Network:** Configuration of a private network where only authorized nodes and accounts can participate.
- **Contract Automation:** Includes scripts to compile, deploy, and test smart contracts on the network.

## Requirements

The requirements are installed automatically by the `setup_besu_networks.sh` script, but it is important to ensure you have the following prerequisites (cURL, wget, tar):

- **Java JDK 17+**
- **Besu v24.7.0+**
- **Docker & Docker-Compose**
- **cURL, wget, tar**

## Installation and Setup

Follow the steps below to set up the project on your machine:

1. Clone these repositories:
   ```bash
   git clone https://github.com/CarlosMikaelCardoso/Jmeter_VS_Caliper.git
   git clone https://github.com/hyperledger-caliper/caliper-benchmarks.git
   cd caliper-benchmarks
   git checkout v0.6.0
   ```
   1.2 Configuration of nodes:
      ```bash
      Go to ./Jmeter_VS_Caliper/update-docker-compose.py and change the 22 and 24 (<your IP>) by your IP address
      ```
2. Execute the network setup script. It will prepare all the necessary files for the nodes.
   ```bash
   chmod +x setup_besu_networks.sh
   ./setup_besu_networks.sh
   ```

## Testing with Caliper and JMeter

### If you want to compare the performance of the two, it's recommended to run Caliper first, as it deploys the contract that JMeter will use for its tests.
In the `testes` folder, edit the "url" in `networkconfig.json` and set the machine's IP address.

# Caliper
```bash
cd testes
./run_caliper.sh <number of users> <number of repetitions>
```
By default, Caliper runs the test once with 5 Workers.

# JMeter
For JMeter, we need to run the API so it can perform the operations.

```bash
cd api-besu
npm install # Installs the API dependencies
# Export the necessary environment variables for the Besu configuration.
export DEPLOYER_PRIVATE_KEY="0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63"
export CONTRACT_ADDRESS="<contract_address>" # This address is located in /testes/contract_address.txt
node api_load_balancer
```
In another terminal:

```bash
cd Jmeter_VS_Caliper/testes
./run_jmeter_api.sh <number of users> <number of repetitions>
```
By default, JMeter runs the test once with 5 Threads.

At the end of each `.sh` script execution, a folder is generated containing log files and test results.
You can modify the Caliper configuration file - `5_Users/caliper/simple/config.yaml` - to define the number of Workers and the number of transactions to be performed. Similarly, for JMeter, you can modify the JMX files - `5_users/jmeter/*.jmx` - which are split into three separate files for each operation (Open, Query, and Transfer).

## Contribution

Contributions are welcome! Follow the steps below to contribute:

1. Fork the repository.
2. Create a branch for your feature/bugfix:
   ```bash
   git checkout -b my-feature
   ```
3. Commit your changes:
   ```bash
   git commit -m "feat: My new feature"
   ```
4. Push to the branch:
   ```bash
   git push origin my-feature
   ```
5. Open a Pull Request.

## Contact

If you have questions or suggestions, get in touch:

- **Developer:** Carlos Mikael Cardoso Da Costa
- **Email:** mikael.cardoso.costa13@gmail.com

## License

This project is licensed under the [MIT License](LICENSE).

---

Thank you for using this project!
