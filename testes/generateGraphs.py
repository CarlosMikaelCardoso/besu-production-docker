import pandas as pd
import matplotlib.pyplot as plt
import os
import sys
import glob

# Dicionário para garantir cores fixas para cada nó.
NODE_COLORS = {
    'node1': '#1f77b4',  # Azul
    'node2': '#ff7f0e',  # Laranja
    'node3': '#2ca02c',  # Verde
    'node4': '#d62728',  # Vermelho
    'node5': '#9467bd',  # Roxo
    'node6': '#8c564b',  # Castanho
}

def analyze_jtl(jtl_file):
    """Lê um ficheiro JTL e retorna um DataFrame do Pandas."""
    try:
        df = pd.read_csv(jtl_file)
        # Calcula o tempo decorrido em segundos desde a primeira transação
        df['elapsed_time'] = (df['timeStamp'] - df['timeStamp'].min()) / 1000
        return df
    except Exception as e:
        print(f"  -> Erro ao ler o ficheiro {os.path.basename(jtl_file)}: {e}")
        return None

def analyze_docker_stats(stats_file):
    """Lê um ficheiro de log do Docker e retorna um DataFrame do Pandas."""
    try:
        col_names = ['container', 'cpu', 'mem', 'net_rx', 'net_tx', 'disk_r', 'disk_w']
        df = pd.read_csv(stats_file, names=col_names, header=None)
        df['cpu'] = df['cpu'].str.replace('%', '').astype(float)
        df['mem'] = df['mem'].str.replace('MiB', '').astype(float)
        df['net_rx'] = df['net_rx'].str.replace('KB', '').astype(float)
        df['net_tx'] = df['net_tx'].str.replace('KB', '').astype(float)
        df['disk_r'] = df['disk_r'].str.replace('KB', '').astype(float)
        df['disk_w'] = df['disk_w'].str.replace('KB', '').astype(float)
        # Adiciona uma coluna de tempo para os gráficos de linha
        df['time'] = df.groupby('container').cumcount() + 1
        return df
    except Exception as e:
        print(f"Erro ao ler o ficheiro de estatísticas do Docker {stats_file}: {e}")
        return None

def parse_backend_errors(results_dir):
    """Lê o log de erros do back-end e retorna um dicionário com a contagem de erros por rodada."""
    error_file = os.path.join(results_dir, "backend_errors.log")
    backend_errors = {"Open": 0, "Query": 0, "Transfer": 0}
    if not os.path.exists(error_file):
        return backend_errors

    try:
        with open(error_file, 'r') as f:
            for line in f:
                parts = line.strip().split(',')
                if len(parts) >= 3:
                    round_name = parts[0]
                    error_count = int(parts[2])
                    if round_name in backend_errors:
                        backend_errors[round_name] += error_count
    except Exception as e:
        print(f"  -> Aviso: Não foi possível ler o ficheiro de erros do back-end: {e}")
    
    return backend_errors

def plot_latency_over_time(df, title, output_path):
    """Gera e guarda um gráfico de latência ao longo do tempo em segundos."""
    df_copy = df.copy()
    df_copy['elapsed_s'] = df_copy['elapsed'] / 1000  # Converte para segundos

    plt.figure(figsize=(12, 6))
    plt.scatter(df_copy['elapsed_time'], df_copy['elapsed_s'], label='Latência (s)', alpha=0.5, s=10)
    
    df_sorted = df_copy.sort_values(by='elapsed_time')
    # Calcula a média móvel na latência em segundos
    df_sorted['rolling_avg'] = df_sorted['elapsed_s'].rolling(window=200, min_periods=1).mean()
    
    plt.plot(df_sorted['elapsed_time'], df_sorted['rolling_avg'], color='red', linestyle='--', label='Média Móvel (200 amostras)')
    plt.title(f'Latência Consolidada ao Longo do Tempo - {title}')
    plt.xlabel('Tempo (segundos)')
    plt.ylabel('Latência da Resposta (s)')
    plt.grid(True)
    plt.legend()
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_latency_{title.lower()}.png"))
    plt.close()

def plot_throughput_over_time(df, title, output_path):
    """Gera e guarda um gráfico de throughput (TPS) ao longo do tempo."""
    tps_df = df[df['success'] == True].copy()
    tps_df['second'] = tps_df['elapsed_time'].astype(int)
    tps_summary = tps_df.groupby('second').size().reset_index(name='tps')
    
    plt.figure(figsize=(12, 6))
    plt.plot(tps_summary['second'], tps_summary['tps'], label='Throughput (TPS)', color='green', marker='o', markersize=4, linestyle='-')
    plt.title(f'Throughput Consolidado ao Longo do Tempo - {title}')
    plt.xlabel('Tempo (segundos)')
    plt.ylabel('Transações por Segundo (TPS)')
    plt.grid(True)
    plt.legend()
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_throughput_{title.lower()}.png"))
    plt.close()

def plot_summary_table_from_dict(summary_data, title, output_path):
    """Gera e guarda uma tabela com métricas de resumo consolidadas a partir de um dicionário."""
    summary = {
        'Métricas': [
            'Total de Amostras', 'Sucesso', 'Falha', 
            'Latência Média (s)', 'Latência Mínima (s)', 'Latência Máxima (s)', 
            'Throughput Médio (TPS)'
        ],
        'Valor': [
            f"{summary_data['Total de Amostras']:.0f}",
            f"{summary_data['Sucesso']:.0f}",
            f"{summary_data['Falha']:.0f}",
            f"{summary_data['Latência Média (ms)'] / 1000:.2f}",
            f"{summary_data['Latência Mínima (ms)'] / 1000:.2f}",
            f"{summary_data['Latência Máxima (ms)'] / 1000:.2f}",
            f"{summary_data['Throughput Médio (TPS)']:.2f}"
        ]
    }

    summary_df = pd.DataFrame(summary)
    
    fig, ax = plt.subplots(figsize=(6, 4))
    ax.axis('tight')
    ax.axis('off')
    table = ax.table(cellText=summary_df.values, colLabels=summary_df.columns, loc='center', cellLoc='center')
    table.auto_set_font_size(False)
    table.set_fontsize(14)
    table.scale(1.2, 1.5)
    plt.title(f'Resumo Consolidado - {title}', fontsize=18, y=0.95)

    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_summary_table_{title.lower()}.png"), bbox_inches='tight', pad_inches=0.1)
    plt.close()
    
def plot_resource_bar_charts(df, title, resource_name, unit, output_path):
    """Gera gráficos de barras para o uso médio e máximo de um recurso."""
    summary = df.groupby('container')[resource_name].agg(['mean', 'max']).reset_index()
    summary = summary.sort_values(by='container').set_index('container')
    colors = [NODE_COLORS.get(node, '#7f7f7f') for node in summary.index]

    plt.figure(figsize=(10, 6))
    bars = plt.bar(summary.index, summary['mean'], color=colors)
    plt.title(f'Uso Médio de {resource_name.upper()} por Nó - {title}')
    plt.ylabel(f'Uso Médio ({unit})')
    plt.xlabel('Nó')
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.bar_label(bars, fmt='%.2f')
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_avg_{resource_name}_usage_{title.lower()}.png"))
    plt.close()

    plt.figure(figsize=(10, 6))
    bars = plt.bar(summary.index, summary['max'], color=colors)
    plt.title(f'Uso Máximo de {resource_name.upper()} por Nó - {title}')
    plt.ylabel(f'Uso Máximo ({unit})')
    plt.xlabel('Nó')
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.bar_label(bars, fmt='%.2f')
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_max_{resource_name}_usage_{title.lower()}.png"))
    plt.close()

def plot_resource_line_chart(df, title, column, y_label, output_path):
    """Função para gerar gráficos de linha para Rede e Disco."""
    plt.figure(figsize=(15, 7))
    sorted_containers = sorted(df['container'].unique())
    for container in sorted_containers:
        container_df = df[df['container'] == container]
        color = NODE_COLORS.get(container, '#7f7f7f')
        plt.plot(container_df['time'], container_df[column], label=container, color=color, alpha=0.8, marker='.', linestyle='-')
    plt.title(f'{y_label} ao Longo do Tempo - {title}')
    plt.xlabel('Tempo (segundos)')
    plt.ylabel(y_label)
    plt.grid(True)
    handles, labels = plt.gca().get_legend_handles_labels()
    order = [labels.index(s) for s in sorted_containers]
    plt.legend([handles[idx] for idx in order],[labels[idx] for idx in order])
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_{column}_usage_{title.lower()}.png"))
    plt.close()

def main():
    if len(sys.argv) < 2:
        print("Uso: python generateGraphs.py <diretório_de_resultados>")
        sys.exit(1)

    results_dir = sys.argv[1]
    rounds = ["Open", "Query", "Transfer"]

    print("\n--- Analisando erros de processamento assíncrono (back-end)... ---")
    backend_errors = parse_backend_errors(results_dir)
    for round_name, count in backend_errors.items():
        if count > 0:
            print(f"  -> Rodada '{round_name}': {count} falhas assíncronas encontradas.")

    print(f"\n--- Gerando gráficos consolidados para os resultados em: {results_dir} ---")

    for round_name in rounds:
        print(f"\n--- Processando Rodada Consolidada: {round_name} ---")

        jtl_files = glob.glob(os.path.join(results_dir, f"results_{round_name.lower()}_run_*.jtl"))
        stats_files = glob.glob(os.path.join(results_dir, f"docker_stats_{round_name.lower()}_run_*.log"))

        run_summaries = []
        if not jtl_files:
            print(f"Aviso: Nenhum ficheiro JTL encontrado para a rodada '{round_name}'.")
        else:
            print(f"Ficheiros JTL encontrados: {len(jtl_files)}")
            for jtl_file in jtl_files:
                df = analyze_jtl(jtl_file)
                if df is not None and not df.empty:
                    total_duration = df['elapsed_time'].max()
                    successful_tx = df['success'].sum()
                    throughput = successful_tx / total_duration if total_duration > 0 else 0
                    
                    run_summary = {
                        'Total de Amostras': len(df),
                        'Sucesso': successful_tx,
                        'Falha': len(df) - successful_tx,
                        'Latência Média (ms)': df['elapsed'].mean(),
                        'Latência Mínima (ms)': df['elapsed'].min(),
                        'Latência Máxima (ms)': df['elapsed'].max(),
                        'Throughput Médio (TPS)': throughput
                    }
                    run_summaries.append(run_summary)
            
            if run_summaries:
                summary_df = pd.DataFrame(run_summaries)
                
                jmeter_failures = summary_df['Falha'].sum()
                backend_failures = backend_errors.get(round_name, 0)
                total_failures = jmeter_failures + backend_failures
                
                # --- MODIFICAÇÃO INICIA AQUI ---
                # O número total de amostras é a soma de todas as tentativas.
                total_amostras = summary_df['Total de Amostras'].sum()
                
                # O número correto de sucessos é o total de amostras MENOS o total de falhas de TODAS as fontes.
                sucesso_corrigido = total_amostras - total_failures
                
                final_summary_data = {
                    'Total de Amostras': total_amostras,
                    'Sucesso': sucesso_corrigido, # <- Alterado de summary_df['Sucesso'].sum() para o valor corrigido
                    'Falha': total_failures,
                    'Latência Média (ms)': summary_df['Latência Média (ms)'].mean(),
                    'Latência Mínima (ms)': summary_df['Latência Mínima (ms)'].mean(),
                    'Latência Máxima (ms)': summary_df['Latência Máxima (ms)'].mean(),
                    'Throughput Médio (TPS)': summary_df['Throughput Médio (TPS)'].mean()
                }
                # --- MODIFICAÇÃO TERMINA AQUI ---

                print(f"  -> Resumo da rodada '{round_name}': {final_summary_data['Sucesso']:.0f} Sucessos, {jmeter_failures:.0f} Falhas (JMeter), {backend_failures} Falhas (API)")
                
                plot_summary_table_from_dict(final_summary_data, round_name, results_dir)

                all_jtl_dfs = [analyze_jtl(f) for f in jtl_files]
                consolidated_jtl_df = pd.concat([df for df in all_jtl_dfs if df is not None], ignore_index=True)
                if not consolidated_jtl_df.empty:
                    plot_latency_over_time(consolidated_jtl_df, round_name, results_dir)
                    plot_throughput_over_time(consolidated_jtl_df, round_name, results_dir)
                print(f"Gráficos de performance consolidados para '{round_name}' gerados.")

        if not stats_files:
            print(f"Aviso: Nenhum ficheiro de estatísticas do Docker encontrado para '{round_name}'.")
        else:
            print(f"Ficheiros de log do Docker encontrados: {len(stats_files)}")
            all_docker_dfs = [analyze_docker_stats(f) for f in stats_files]
            consolidated_docker_df = pd.concat([df for df in all_docker_dfs if df is not None], ignore_index=True)
            if not consolidated_docker_df.empty:
                plot_resource_bar_charts(consolidated_docker_df, round_name, 'cpu', '%', results_dir)
                plot_resource_bar_charts(consolidated_docker_df, round_name, 'mem', 'MB', results_dir)
                consolidated_docker_df['net_io'] = consolidated_docker_df['net_rx'] + consolidated_docker_df['net_tx']
                plot_resource_line_chart(consolidated_docker_df, round_name, 'net_io', 'I/O de Rede Consolidado (KB/s)', results_dir)
                consolidated_docker_df['disk_io'] = consolidated_docker_df['disk_r'] + consolidated_docker_df['disk_w']
                plot_resource_line_chart(consolidated_docker_df, round_name, 'disk_io', 'I/O de Disco Consolidado (KB/s)', results_dir)
                print(f"Gráficos de recursos consolidados para '{round_name}' gerados.")

    print("\nProcesso de geração de gráficos concluído!")

if __name__ == "__main__":
    main()