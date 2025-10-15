import subprocess
import re
import os
import json
import yaml # Importar a biblioteca PyYAML

def get_enode(node_number):
    """
    Obtém o enode para um nó Besu específico.
    Adiciona timeout para o curl para evitar esperas infinitas se o nó não responder.
    """
    port = 8545 + node_number - 1
    command = f"curl -X POST --silent --connect-timeout 5 --max-time 10 --data '{{\"jsonrpc\":\"2.0\",\"method\":\"net_enode\",\"params\":[],\"id\":1}}' http://127.0.0.1:{port} | jq -r .result"
    try:
        result = subprocess.run(command, shell=True, check=True, capture_output=True, text=True)
        enode = result.stdout.strip()
        if not enode: # Verifica se o enode está vazio
            print(f"Aviso: Enode vazio para Node-{node_number}. Verifique se o nó está rodando e acessível.")
            return None
        # Modifica o IP no enode para 127.0.0.1 e a porta para 30303 para Node-1 e 30305 para Node-3
        if node_number == 1:
            enode = re.sub(r'@\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+', '@<your IP>:30303', enode)
        elif node_number == 3:
            enode = re.sub(r'@\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+', '@<your IP>:30305', enode)
        return enode
    except subprocess.CalledProcessError as e:
        print(f"Erro ao obter enode para Node-{node_number}: {e}")
        print(f"Stderr: {e.stderr}")
        return None
    except Exception as e:
        print(f"Ocorreu um erro inesperado ao obter enode para Node-{node_number}: {e}")
        return None

def update_docker_compose_with_yq(file_path, enode1, enode3):
    """
    Atualiza o arquivo docker-compose.yaml com os enodes fornecidos usando PyYAML para manipulação
    e regex para a string do comando.
    """
    new_bootnodes_string = f'--bootnodes="{enode1}","{enode3}"'

    try:
        # 1. Ler o arquivo YAML completo usando PyYAML
        with open(file_path, 'r') as f:
            # Usar SafeLoader para segurança ao carregar YAML
            yaml_data = yaml.safe_load(f)

        # Iterar sobre os nós de 2 a 6 para atualizar o comando
        for i in range(2, 7):
            node_name = f'node{i}'
            
            # Acessar o campo 'command' do nó específico
            if node_name in yaml_data['services'] and 'command' in yaml_data['services'][node_name]:
                current_command_content = yaml_data['services'][node_name]['command']

                updated_command_content = ""
                # 2. Modificar a string do comando em Python
                # Verifica se --bootnodes já existe no bloco de comando
                if re.search(r'--bootnodes=', current_command_content):
                    # Substitui a linha --bootnodes existente
                    updated_command_content = re.sub(
                        r'--bootnodes=".*?"', 
                        new_bootnodes_string, 
                        current_command_content, 
                        flags=re.MULTILINE
                    )
                else:
                    # Adiciona --bootnodes após --genesis-file, garantindo a indentação.
                    # Encontrar a linha --genesis-file e inserir após
                    if re.search(r'--genesis-file=', current_command_content):
                        updated_command_content = re.sub(
                            r'(--genesis-file=/\S+)',
                            r'\1\n' + new_bootnodes_string, 
                            current_command_content,
                            flags=re.MULTILINE
                        )
                    else:
                        # Se --genesis-file não for encontrado, adicione no início do bloco de comando
                        updated_command_content = new_bootnodes_string + "\n" + current_command_content
                
                # Atualizar o objeto Python com o comando modificado
                yaml_data['services'][node_name]['command'] = updated_command_content
                print(f"Comando para {node_name} modificado em memória.")
            else:
                print(f"Aviso: O serviço '{node_name}' ou seu campo 'command' não foi encontrado no YAML.")

        # 3. Escrever o objeto Python modificado de volta para o arquivo YAML usando PyYAML
        with open(file_path, 'w') as f:
            # Usar default_flow_style=False para garantir que strings multilinhas sejam formatadas corretamente
            # e sort_keys=False para manter a ordem original das chaves (opcional, mas útil para compose files)
            yaml.dump(yaml_data, f, default_flow_style=False, sort_keys=False)
        
        print(f"Arquivo '{file_path}' atualizado com sucesso usando PyYAML.")

    except yaml.YAMLError as e:
        print(f"Erro ao processar o arquivo YAML: {e}")
    except Exception as e:
        print(f"Ocorreu um erro inesperado: {e}")

if __name__ == "__main__":
    compose_file = 'docker-compose.yaml' # Verifique se este é o caminho correto para o seu arquivo

    print("Verificando a instalação do yq...")
    try:
        # Verifica se yq está no PATH e é executável (ainda útil para depuração inicial)
        subprocess.run("yq --version", shell=True, check=True, capture_output=True, text=True)
        print("yq está instalado.")
    except subprocess.CalledProcessError:
        print("Aviso: yq não está instalado ou não está no PATH. O script usará PyYAML para manipulação de YAML.")
    except FileNotFoundError:
        print("Aviso: yq não foi encontrado. O script usará PyYAML para manipulação de YAML.")

    # Verificar e instalar PyYAML se necessário
    try:
        import yaml
    except ImportError:
        print("Erro: PyYAML não está instalado.")
        print("Por favor, instale PyYAML: pip install PyYAML")
        exit(1)

    print("Obtendo enodes do Node-1 e Node-3...")
    enode_node1 = get_enode(1)
    enode_node3 = get_enode(3)

    if enode_node1 and enode_node3:
        print(f"Enode Node-1: {enode_node1}")
        print(f"Enode Node-3: {enode_node3}")
        print(f"Atualizando o arquivo {compose_file} usando PyYAML...")
        update_docker_compose_with_yq(compose_file, enode_node1, enode_node3)
    else:
        print("Não foi possível obter um ou ambos os enodes necessários. Verifique se os nós estão rodando e acessíveis.")
