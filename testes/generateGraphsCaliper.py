import pandas as pd
import matplotlib.pyplot as plt
import os
import sys
import glob
import re

# Dicionário para garantir cores fixas para cada nó.
NODE_COLORS = {
    'node1': '#1f77b4',  # Azul
    'node2': '#ff7f0e',  # Laranja
    'node3': '#2ca02c',  # Verde
    'node4': '#d62728',  # Vermelho
    'node5': '#9467bd',  # Roxo
    'node6': '#8c564b',  # Castanho
}

def parse_caliper_log(log_file):
    """Lê um ficheiro de log do Caliper e extrai as tabelas de performance e recursos."""
    try:
        with open(log_file, 'r') as f:
            content = f.read()
    except Exception as e:
        print(f"Erro ao ler o ficheiro de log {log_file}: {e}")
        return None, None

    performance_data = []
    resource_data = []
    round_sections = re.split(r'Started round \d+ \((\w+)\)', content)

    for i in range(1, len(round_sections), 2):
        round_name = round_sections[i]
        round_content = round_sections[i+1]
        
        perf_match = re.search(r'### Test result ###\s*.*?Name\s*\| Succ.*?\n(.*?)\n\+--[+\-]*--', round_content, re.S)
        if perf_match:
            perf_table_str = perf_match.group(1)
            perf_lines = [line.strip() for line in perf_table_str.strip().split('\n') if '|' in line and '------' not in line]
            for line in perf_lines:
                parts = [p.strip() for p in line.split('|') if p.strip()]
                if len(parts) == 8: performance_data.append([round_name] + parts)

        res_match = re.search(r'### docker resource stats ###\s*.*?Name\s*\| CPU%\(max\).*?\n(.*?)\n\+--[+\-]*--', round_content, re.S)
        if res_match:
            res_table_str = res_match.group(1)
            res_lines = [line.strip() for line in res_table_str.strip().split('\n') if '|' in line and '------' not in line]
            for line in res_lines:
                parts = [p.strip().replace('/', '') for p in line.split('|') if p.strip()]
                if len(parts) == 9:
                    parts[7] = f"{parts[7]} KB" if 'KB' not in parts[7] else parts[7]
                    resource_data.append([round_name] + parts)

    if not performance_data:
        print(f"Aviso: Nenhuma tabela de performance encontrada no ficheiro {os.path.basename(log_file)}")
        return None, None
        
    perf_df = pd.DataFrame(performance_data, columns=['Round', 'Name', 'Succ', 'Fail', 'Send Rate (TPS)', 'Max Latency (s)', 'Min Latency (s)', 'Avg Latency (s)', 'Throughput (TPS)'])
    res_df = None
    if resource_data:
        res_df = pd.DataFrame(resource_data, columns=['Round', 'Name', 'CPU%(max)', 'CPU%(avg)', 'Memory(max) [MB]', 'Memory(avg) [MB]', 'Traffic In [B]', 'Traffic Out [B]', 'Disc Write', 'Disc Read [B]'])
        res_df.rename(columns={'Disc Write': 'Disc Write [KB]'}, inplace=True)

    for col in perf_df.columns[2:]: perf_df[col] = pd.to_numeric(perf_df[col], errors='coerce')
    if res_df is not None:
        for col in res_df.columns[2:]:
             if isinstance(res_df[col].iloc[0], str):
                res_df[col] = pd.to_numeric(res_df[col].str.extract(r'(\d+\.?\d*)')[0], errors='coerce')
             else:
                res_df[col] = pd.to_numeric(res_df[col], errors='coerce')

    return perf_df, res_df

def plot_summary_table_per_round(df_round, num_repetitions, output_path):
    """Gera uma tabela de resumo de performance para uma única ronda."""
    if df_round.empty: return
    
    round_name = df_round['Name'].iloc[0]
    base_tx_counts = {'open': 1000, 'query': 1000, 'transfer': 50}
    
    successful_tx = df_round['Succ'].iloc[0]
    failed_tx = df_round['Fail'].iloc[0]
    total_samples = successful_tx + failed_tx # O total é a soma do que foi executado
    
    summary_data = {
        'Métricas': [
            'Total de Amostras', 'Sucesso', 'Falha', 
            'Latência Média (s)', 'Latência Mínima (s)', 'Latência Máxima (s)', 
            'Throughput Médio (TPS)'
        ],
        'Valor': [
            f"{total_samples:.0f}",
            f"{successful_tx:.0f}",
            f"{failed_tx:.0f}",
            f"{df_round['Avg Latency (s)'].iloc[0]:.2f}",
            f"{df_round['Min Latency (s)'].iloc[0]:.2f}",
            f"{df_round['Max Latency (s)'].iloc[0]:.2f}",
            f"{df_round['Throughput (TPS)'].iloc[0]:.2f}"
        ]
    }
    summary_df = pd.DataFrame(summary_data)

    fig, ax = plt.subplots(figsize=(6, 4))
    ax.axis('tight')
    ax.axis('off')
    table = ax.table(cellText=summary_df.values, colLabels=summary_df.columns, loc='center', cellLoc='center')
    table.auto_set_font_size(False)
    table.set_fontsize(14)
    table.scale(1.2, 1.5)
    plt.title(f'Resumo Consolidado - {round_name.capitalize()}', fontsize=18, y=0.95)
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_caliper_summary_{round_name}.png"), bbox_inches='tight', pad_inches=0.1)
    plt.close()

def plot_resource_bar_chart_per_round(df_round, metric, unit, round_name, output_path):
    """Gera um gráfico de barras de recursos para uma única ronda."""
    if df_round.empty: return

    summary = df_round.sort_values(by='Name').set_index('Name')
    colors = [NODE_COLORS.get(node, '#7f7f7f') for node in summary.index]

    plt.figure(figsize=(10, 6))
    bars = plt.bar(summary.index, summary[metric], color=colors)
    metric_name = metric.replace('(avg)', 'Médio').replace('[MB]', '').replace('%', '')
    plt.title(f'Uso {metric_name} por Nó - {round_name.capitalize()}')
    plt.ylabel(f'Uso ({unit})')
    plt.xlabel('Nó')
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.bar_label(bars, fmt='%.2f')
    plt.tight_layout()
    safe_metric_name = re.sub(r'[^a-zA-Z0-9]', '_', metric)
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_caliper_resource_{safe_metric_name}_{round_name}.png"))
    plt.close()

def main():
    if len(sys.argv) < 3:
        print("Uso: python generate_caliper_graphs.py <diretorio_dos_resultados> <numero_de_repeticoes>")
        sys.exit(1)

    results_dir = sys.argv[1]
    num_repetitions = int(sys.argv[2])
    
    log_files = glob.glob(os.path.join(results_dir, "caliper_log_run_*.txt"))
    if not log_files:
        print(f"Aviso: Nenhum ficheiro de log do Caliper encontrado em {results_dir}")
        return

    print(f"\n--- A gerar gráficos consolidados para {len(log_files)} execução(ões) do Caliper ---")
    
    all_perf_dfs = []
    all_res_dfs = []

    for log_file in log_files:
        perf_df, res_df = parse_caliper_log(log_file)
        if perf_df is not None: all_perf_dfs.append(perf_df)
        if res_df is not None: all_res_dfs.append(res_df)

    if all_perf_dfs:
        full_perf_df = pd.concat(all_perf_dfs, ignore_index=True)
        agg_rules = {
            'Succ': 'sum', 'Fail': 'sum', 'Send Rate (TPS)': 'mean',
            'Max Latency (s)': 'mean', 'Min Latency (s)': 'mean',
            'Avg Latency (s)': 'mean', 'Throughput (TPS)': 'mean'
        }
        consolidated_perf_df = full_perf_df.groupby('Name').agg(agg_rules).reset_index()

        for round_name in consolidated_perf_df['Name'].unique():
            round_df = consolidated_perf_df[consolidated_perf_df['Name'] == round_name]
            plot_summary_table_per_round(round_df, num_repetitions, results_dir)
        print("Tabelas de performance do Caliper geradas.")

    if all_res_dfs:
        consolidated_res_df = pd.concat(all_res_dfs).groupby(['Round', 'Name']).mean(numeric_only=True).reset_index()
        for round_name in consolidated_res_df['Round'].unique():
            round_df = consolidated_res_df[consolidated_res_df['Round'] == round_name]
            plot_resource_bar_chart_per_round(round_df, 'CPU%(avg)', '%', round_name, results_dir)
            plot_resource_bar_chart_per_round(round_df, 'Memory(avg) [MB]', 'MB', round_name, results_dir)
        print("Gráficos de barras de recursos do Caliper gerados.")

    print("\nProcesso de geração de gráficos do Caliper concluído!")

if __name__ == "__main__":
    main()