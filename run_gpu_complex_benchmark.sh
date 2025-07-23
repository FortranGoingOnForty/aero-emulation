#!/bin/bash
#SBATCH --job-name=aero_gpu_complex
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --time=00:15:00
#SBATCH --output=gpu_complex_benchmark_%j.out

module load cuda/11.8

cd ~/cmaq_aero_gpu_bench

echo "Running Complex AERO GPU Benchmark"
echo "=================================="
nvidia-smi --query-gpu=name,memory.total --format=csv
echo ""

./benchmark_gpu_complex

echo ""
echo "GPU Utilization:"
nvidia-smi
