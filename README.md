# Hyperledger Besu - Rede QBFT Permissional

Bem-vindo ao projeto **Besu Production Docker**! Este repositório foi desenvolvido para facilitar a criação e o gerenciamento de uma rede blockchain permissionada com **Hyperledger Besu**, utilizando o mecanismo de consenso **QBFT**, ideal para ambientes de produção.

## Funcionalidades

- **Setup Automatizado:** Scripts que automatizam a geração de chaves, arquivos de configuração e a estrutura de diretórios da rede.
- **Orquestração com Docker:** Uso de Docker e Docker-Compose para subir e gerenciar os nós da rede de forma isolada e consistente.
- **Rede Permissionada:** Configuração de uma rede privada onde apenas nós e contas autorizadas podem participar.
- **Automação de Contratos:** Inclui scripts para compilar, implantar e testar smart contracts na rede.

## Requisitos

Os requisitos são instalados automaticamente pelo script `setup_besu_networks.sh`, mas é importante garantir que você tenha os seguintes pré-requisitos (cURL, wget, tar):

- **Java JDK 17+**
- **Besu v24.7.0+**
- **Docker & Docker-Compose**
- **cURL, wget, tar**

## Instalação e Configuração

Siga os passos abaixo para configurar o projeto em sua máquina:

1. Clone este repositório:
   ```bash
   git clone https://github.com/CarlosMikaelCardoso/besu-production-docker.git
   ```
2. Execute o script de configuração da rede. Ele irá preparar todos os arquivos necessários para os nós.
   ```bash
   chmod +x setup_besu_networks.sh
   ./setup_besu_networks.sh
   ```

## Deploy e Teste de Contratos

Com a rede em execução, utilize o script `besu_smart_contracts` para automatizar o deploy e a interação com seus contratos.

1. Dê permissão de execução ao script:
   ```bash
   chmod +x besu_smart_contracts.sh
   ```
2. Execute o script para implantar e testar os contratos:
   ```bash
   ./besu_smart_contracts.sh
   ```

## Contribuição

Contribuições são bem-vindas! Siga os passos abaixo para contribuir:

1. Faça um fork do repositório.
2. Crie uma branch para sua feature/bugfix:
   ```bash
   git checkout -b minha-feature
   ```
3. Faça commit das suas alterações:
   ```bash
   git commit -m "feat: Minha nova feature"
   ```
4. Envie para o repositório:
   ```bash
   git push origin minha-feature
   ```
5. Abra um Pull Request.

## Contato

Se tiver dúvidas ou sugestões, entre em contato:

- **Desenvolvedor:** Carlos Mikael Cardoso
- **Email:** mikael.cardoso.costa13@gmail.com

## Licença

Este projeto está licenciado sob a [Licença MIT](LICENSE).

---

Obrigado por usar este projeto!
