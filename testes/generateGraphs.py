import pandas as pd
import matplotlib.pyplot as plt
import os
import sys
import glob

# Dictionary to ensure fixed colors for each node.
NODE_COLORS = {
    'node1': '#1f77b4',  # Blue
    'node2': '#ff7f0e',  # Orange
    'node3': '#2ca02c',  # Green
    'node4': '#d62728',  # Red
    'node5': '#9467bd',  # Purple
    'node6': '#8c564b',  # Brown
}

def analyze_jtl(jtl_file):
    """Reads a JTL file and returns a Pandas DataFrame."""
    try:
        df = pd.read_csv(jtl_file)
        # Calculates elapsed time in seconds since the first transaction
        df['elapsed_time'] = (df['timeStamp'] - df['timeStamp'].min()) / 1000
        return df
    except Exception as e:
        print(f"  -> Error reading file {os.path.basename(jtl_file)}: {e}")
        return None

def analyze_docker_stats(stats_file):
    """Reads a Docker log file and returns a Pandas DataFrame."""
    try:
        col_names = ['container', 'cpu', 'mem', 'net_rx', 'net_tx', 'disk_r', 'disk_w']
        df = pd.read_csv(stats_file, names=col_names, header=None)
        df['cpu'] = df['cpu'].str.replace('%', '').astype(float)
        df['mem'] = df['mem'].str.replace('MiB', '').astype(float)
        df['net_rx'] = df['net_rx'].str.replace('KB', '').astype(float)
        df['net_tx'] = df['net_tx'].str.replace('KB', '').astype(float)
        df['disk_r'] = df['disk_r'].str.replace('KB', '').astype(float)
        df['disk_w'] = df['disk_w'].str.replace('KB', '').astype(float)
        # Adds a time column for the line charts
        df['time'] = df.groupby('container').cumcount() + 1
        return df
    except Exception as e:
        print(f"Error reading Docker stats file {stats_file}: {e}")
        return None

def plot_latency_over_time(df, title, output_path):
    """Generates and saves a latency over time graph in seconds."""
    df_copy = df.copy()
    df_copy['elapsed_s'] = df_copy['elapsed'] / 1000  # Converts to seconds

    plt.figure(figsize=(12, 6))
    plt.scatter(df_copy['elapsed_time'], df_copy['elapsed_s'], label='Latency (s)', alpha=0.5, s=10)
    
    df_sorted = df_copy.sort_values(by='elapsed_time')
    # Calculates the rolling average on latency in seconds
    df_sorted['rolling_avg'] = df_sorted['elapsed_s'].rolling(window=200, min_periods=1).mean()
    
    plt.plot(df_sorted['elapsed_time'], df_sorted['rolling_avg'], color='red', linestyle='--', label='Rolling Average (200 samples)')
    plt.title(f'Consolidated Latency Over Time - {title}')
    plt.xlabel('Time (seconds)')
    plt.ylabel('Response Latency (s)')
    plt.grid(True)
    plt.legend()
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_latency_{title.lower()}.png"))
    plt.close()

def plot_throughput_over_time(df, title, output_path):
    """Generates and saves a throughput (TPS) over time graph."""
    tps_df = df[df['success'] == True].copy()
    tps_df['second'] = tps_df['elapsed_time'].astype(int)
    tps_summary = tps_df.groupby('second').size().reset_index(name='tps')
    
    plt.figure(figsize=(12, 6))
    plt.plot(tps_summary['second'], tps_summary['tps'], label='Throughput (TPS)', color='green', marker='o', markersize=4, linestyle='-')
    plt.title(f'Consolidated Throughput Over Time - {title}')
    plt.xlabel('Time (seconds)')
    plt.ylabel('Transactions per Second (TPS)')
    plt.grid(True)
    plt.legend()
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_throughput_{title.lower()}.png"))
    plt.close()

def plot_summary_table_from_dict(summary_data, title, output_path):
    """Generates and saves a table with consolidated summary metrics from a dictionary."""
    summary = {
        'Metrics': [
            'Total Samples', 'Success', 'Failure', 
            'Average Latency (s)', 'Minimum Latency (s)', 'Maximum Latency (s)', 
            'Average Throughput (TPS)'
        ],
        'Value': [
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
    
    # --- MODIFICATION: Adjusting style parameters to match Caliper ---
    fig, ax = plt.subplots(figsize=(6, 4)) # Reduced figure size
    ax.axis('tight')
    ax.axis('off')
    table = ax.table(cellText=summary_df.values, colLabels=summary_df.columns, loc='center', cellLoc='center')
    table.auto_set_font_size(False)
    table.set_fontsize(14) # Increased font size
    table.scale(1.2, 1.5) # Adjusted scale (especially height)
    plt.title(f'Consolidated Summary - {title}', fontsize=18, y=0.95) # Adjusted title font and position
    # --- END OF MODIFICATION ---

    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_summary_table_{title.lower()}.png"), bbox_inches='tight', pad_inches=0.1)
    plt.close()
    
def plot_resource_bar_charts(df, title, resource_name, unit, output_path):
    """Generates bar charts for a resource's average and maximum usage."""
    summary = df.groupby('container')[resource_name].agg(['mean', 'max']).reset_index()
    summary = summary.sort_values(by='container').set_index('container')
    colors = [NODE_COLORS.get(node, '#7f7f7f') for node in summary.index]

    plt.figure(figsize=(10, 6))
    bars = plt.bar(summary.index, summary['mean'], color=colors)
    plt.title(f'Average {resource_name.upper()} Usage per Node - {title}')
    plt.ylabel(f'Average Usage ({unit})')
    plt.xlabel('Node')
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.bar_label(bars, fmt='%.2f')
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_avg_{resource_name}_usage_{title.lower()}.png"))
    plt.close()

    plt.figure(figsize=(10, 6))
    bars = plt.bar(summary.index, summary['max'], color=colors)
    plt.title(f'Maximum {resource_name.upper()} Usage per Node - {title}')
    plt.ylabel(f'Maximum Usage ({unit})')
    plt.xlabel('Node')
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.bar_label(bars, fmt='%.2f')
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_max_{resource_name}_usage_{title.lower()}.png"))
    plt.close()

def plot_resource_line_chart(df, title, column, y_label, output_path):
    """Function to generate line charts for Network and Disk."""
    plt.figure(figsize=(15, 7))
    sorted_containers = sorted(df['container'].unique())
    for container in sorted_containers:
        container_df = df[df['container'] == container]
        color = NODE_COLORS.get(container, '#7f7f7f')
        plt.plot(container_df['time'], container_df[column], label=container, color=color, alpha=0.8, marker='.', linestyle='-')
    plt.title(f'{y_label} Over Time - {title}')
    plt.xlabel('Time (seconds)')
    plt.ylabel(y_label)
    plt.grid(True)
    handles, labels = plt.gca().get_legend_handles_labels()
    order = [labels.index(s) for s in sorted_containers]
    plt.legend([handles[idx] for idx in order],[labels[idx] for idx in order])
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_{column}_usage_{title.lower()}.png"))
    plt.close()

def main():
    if len(sys.argv) < 2:
        print("Usage: python generate_graphs.py <results_directory>")
        sys.exit(1)

    results_dir = sys.argv[1]
    rounds = ["Open", "Query", "Transfer"]

    print(f"\n--- Generating consolidated graphs for the results in: {results_dir} ---")

    for round_name in rounds:
        print(f"\n--- Processing Consolidated Round: {round_name} ---")

        jtl_files = glob.glob(os.path.join(results_dir, f"results_{round_name.lower()}_run_*.jtl"))
        stats_files = glob.glob(os.path.join(results_dir, f"docker_stats_{round_name.lower()}_run_*.log"))

        # 1. Process each individual JTL run and calculate its metrics.
        run_summaries = []
        if not jtl_files:
            print(f"Warning: No JTL files found for round '{round_name}'.")
        else:
            print(f"JTL files found: {len(jtl_files)}")
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
            
            # 2. Consolidate the metrics by calculating the AVERAGE (for rates and latencies) and SUM (for counts).
            if run_summaries:
                summary_df = pd.DataFrame(run_summaries)
                final_summary_data = {
                    'Total de Amostras': summary_df['Total de Amostras'].sum(),
                    'Sucesso': summary_df['Sucesso'].sum(),
                    'Falha': summary_df['Falha'].sum(),
                    'Latência Média (ms)': summary_df['Latência Média (ms)'].mean(),
                    'Latência Mínima (ms)': summary_df['Latência Mínima (ms)'].mean(),
                    'Latência Máxima (ms)': summary_df['Latência Máxima (ms)'].mean(),
                    'Throughput Médio (TPS)': summary_df['Throughput Médio (TPS)'].mean()
                }
                
                plot_summary_table_from_dict(final_summary_data, round_name, results_dir)

                # For over-time graphs, we use concatenated data from all runs
                all_jtl_dfs = [analyze_jtl(f) for f in jtl_files]
                consolidated_jtl_df = pd.concat([df for df in all_jtl_dfs if df is not None], ignore_index=True)
                if not consolidated_jtl_df.empty:
                    plot_latency_over_time(consolidated_jtl_df, round_name, results_dir)
                    plot_throughput_over_time(consolidated_jtl_df, round_name, results_dir)
                print(f"Consolidated performance graphs for '{round_name}' generated.")

        # The processing of Docker logs remains the same.
        if not stats_files:
            print(f"Warning: No Docker stats files found for '{round_name}'.")
        else:
            print(f"Docker log files found: {len(stats_files)}")
            all_docker_dfs = [analyze_docker_stats(f) for f in stats_files]
            consolidated_docker_df = pd.concat([df for df in all_docker_dfs if df is not None], ignore_index=True)
            if not consolidated_docker_df.empty:
                plot_resource_bar_charts(consolidated_docker_df, round_name, 'cpu', '%', results_dir)
                plot_resource_bar_charts(consolidated_docker_df, round_name, 'mem', 'MB', results_dir)
                consolidated_docker_df['net_io'] = consolidated_docker_df['net_rx'] + consolidated_docker_df['net_tx']
                plot_resource_line_chart(consolidated_docker_df, round_name, 'net_io', 'Consolidated Network I/O (KB/s)', results_dir)
                consolidated_docker_df['disk_io'] = consolidated_docker_df['disk_r'] + consolidated_docker_df['disk_w']
                plot_resource_line_chart(consolidated_docker_df, round_name, 'disk_io', 'Consolidated Disk I/O (KB/s)', results_dir)
                print(f"Consolidated resource graphs for '{round_name}' generated.")

    print("\nGraph generation process completed!")

if __name__ == "__main__":
    main()