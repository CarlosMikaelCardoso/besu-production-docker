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
        df['time'] = df.groupby('container').cumcount() + 1
        return df
    except Exception as e:
        print(f"Erro ao ler o ficheiro de estatísticas do Docker {stats_file}: {e}")
        return None

def plot_latency_over_time(df, title, output_path):
    """Gera e salva um gráfico de latência ao longo do tempo."""
    plt.figure(figsize=(12, 6))
    plt.scatter(df['elapsed_time'], df['elapsed'], label='Latência (ms)', alpha=0.5, s=10)
    df_sorted = df.sort_values(by='elapsed_time')
    df_sorted['rolling_avg'] = df_sorted['elapsed'].rolling(window=200, min_periods=1).mean()
    plt.plot(df_sorted['elapsed_time'], df_sorted['rolling_avg'], color='red', linestyle='--', label='Média Móvel (200 amostras)')
    plt.title(f'Latência Consolidada ao Longo do Tempo - {title}')
    plt.xlabel('Tempo (segundos)')
    plt.ylabel('Latência da Resposta (ms)')
    plt.grid(True)
    plt.legend()
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_latency_{title.lower()}.png"))
    plt.close()

def plot_throughput_over_time(df, title, output_path):
    """Gera e salva um gráfico de throughput (TPS) ao longo do tempo."""
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

def plot_summary_table(df, title, output_path):
    """Gera e salva uma tabela com as métricas de resumo consolidadas."""
    total_duration = df['elapsed_time'].max()
    successful_tx = df['success'].sum()
    throughput = successful_tx / total_duration if total_duration > 0 else 0
    summary = {
        'Métricas': [
            'Total de Amostras', 'Sucesso', 'Falha', 
            'Latência Média (ms)', 'Latência Mínima (ms)', 'Latência Máxima (ms)', 
            'Latência 90% (ms)', 'Latência 95% (ms)', 'Latência 99% (ms)',
            'Throughput Médio (TPS)'
        ],
        'Valor': [
            len(df), successful_tx, len(df) - successful_tx,
            f"{df['elapsed'].mean():.2f}", df['elapsed'].min(), df['elapsed'].max(),
            f"{df['elapsed'].quantile(0.90):.2f}", f"{df['elapsed'].quantile(0.95):.2f}", f"{df['elapsed'].quantile(0.99):.2f}",
            f"{throughput:.2f}"
        ]
    }
    summary_df = pd.DataFrame(summary)
    fig, ax = plt.subplots(figsize=(8, 5))
    ax.axis('tight')
    ax.axis('off')
    table = ax.table(cellText=summary_df.values, colLabels=summary_df.columns, loc='center', cellLoc='center')
    table.auto_set_font_size(False)
    table.set_fontsize(12)
    table.scale(1.2, 1.2)
    plt.title(f'Resumo Consolidado - {title}', fontsize=16, y=0.9)
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_summary_table_{title.lower()}.png"), bbox_inches='tight', pad_inches=0.1)
    plt.close()

# MODIFICAÇÃO: Esta nova função cria os gráficos de barras para CPU e Memória.
def plot_resource_bar_charts(df, title, resource_name, unit, output_path):
    """Gera gráficos de barras para a utilização média e máxima de um recurso."""
    # Agrupa por container e calcula a média e o máximo
    summary = df.groupby('container')[resource_name].agg(['mean', 'max']).reset_index()
    summary = summary.sort_values(by='container').set_index('container')

    # Garante que as cores correspondem à ordem dos nós
    colors = [NODE_COLORS.get(node, '#7f7f7f') for node in summary.index]

    # Gráfico para a Média
    plt.figure(figsize=(10, 6))
    bars = plt.bar(summary.index, summary['mean'], color=colors)
    plt.title(f'Uso Médio de {resource_name.upper()} por Nó - {title}')
    plt.ylabel(f'Uso Médio ({unit})')
    plt.xlabel('Nó')
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.bar_label(bars, fmt='%.2f')
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_avg_{resource_name}_usage_{title.lower()}.png"))
    plt.close()

    # Gráfico para o Máximo (Pico)
    plt.figure(figsize=(10, 6))
    bars = plt.bar(summary.index, summary['max'], color=colors)
    plt.title(f'Uso Máximo de {resource_name.upper()} por Nó - {title}')
    plt.ylabel(f'Uso Máximo ({unit})')
    plt.xlabel('Nó')
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.bar_label(bars, fmt='%.2f')
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_max_{resource_name}_usage_{title.lower()}.png"))
    plt.close()

# MODIFICAÇÃO: Esta função agora só é usada para Rede e Disco.
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
        print("Uso: python generate_graphs.py <diretorio_dos_resultados>")
        sys.exit(1)

    results_dir = sys.argv[1]
    rounds = ["Open", "Query", "Transfer"]

    print(f"\n--- A gerar gráficos consolidados para os resultados em: {results_dir} ---")

    for round_name in rounds:
        print(f"\n--- Processando Ronda Consolidada: {round_name} ---")

        # Processamento de performance (JTL)
        jtl_files = glob.glob(os.path.join(results_dir, f"results_{round_name.lower()}_run_*.jtl"))
        if not jtl_files:
            print(f"Aviso: Nenhum ficheiro JTL encontrado para a ronda '{round_name}'.")
        else:
            print(f"Ficheiros JTL encontrados: {len(jtl_files)}")
            all_jtl_dfs = [analyze_jtl(f) for f in jtl_files]
            consolidated_jtl_df = pd.concat([df for df in all_jtl_dfs if df is not None], ignore_index=True)
            if not consolidated_jtl_df.empty:
                plot_latency_over_time(consolidated_jtl_df, round_name, results_dir)
                plot_throughput_over_time(consolidated_jtl_df, round_name, results_dir)
                plot_summary_table(consolidated_jtl_df, round_name, results_dir)
                print(f"Gráficos de performance consolidados para '{round_name}' gerados.")

        # Processamento de recursos (Docker)
        stats_files = glob.glob(os.path.join(results_dir, f"docker_stats_{round_name.lower()}_run_*.log"))
        if not stats_files:
            print(f"Aviso: Nenhum ficheiro de estatísticas do Docker encontrado para '{round_name}'.")
        else:
            print(f"Ficheiros de log do Docker encontrados: {len(stats_files)}")
            all_docker_dfs = [analyze_docker_stats(f) for f in stats_files]
            consolidated_docker_df = pd.concat([df for df in all_docker_dfs if df is not None], ignore_index=True)
            if not consolidated_docker_df.empty:
                # MODIFICAÇÃO: Chama a nova função para gráficos de barras de CPU e Memória
                plot_resource_bar_charts(consolidated_docker_df, round_name, 'cpu', '%', results_dir)
                plot_resource_bar_charts(consolidated_docker_df, round_name, 'mem', 'MB', results_dir)
                
                # Mantém os gráficos de linha para Rede e Disco
                consolidated_docker_df['net_io'] = consolidated_docker_df['net_rx'] + consolidated_docker_df['net_tx']
                plot_resource_line_chart(consolidated_docker_df, round_name, 'net_io', 'I/O de Rede Consolidado (KB/s)', results_dir)
                consolidated_docker_df['disk_io'] = consolidated_docker_df['disk_r'] + consolidated_docker_df['disk_w']
                plot_resource_line_chart(consolidated_docker_df, round_name, 'disk_io', 'I/O de Disco Consolidado (KB/s)', results_dir)
                print(f"Gráficos de recursos consolidados para '{round_name}' gerados.")

    print("\nProcesso de geração de gráficos concluído!")

if __name__ == "__main__":
    main()