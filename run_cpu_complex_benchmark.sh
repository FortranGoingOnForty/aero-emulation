#!/bin/bash
#SBATCH --job-name=aero_cpu_bench
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=00:10:00
#SBATCH --output=cpu_benchmark_%j.out

# Don't load MPI module - not needed for OpenMP
# module load mpi  # REMOVE THIS

# Increase stack size for OpenMP
ulimit -s unlimited

cd ~/cmaq_aero_gpu_bench

echo "Running AERO CPU Benchmark"
echo "========================="
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo ""

# Check stack size
echo "Stack size: $(ulimit -s)"
echo ""

# Run CPU benchmark with different thread counts
for threads in 1 2 4 8 16; do
    echo "Testing with $threads threads..."
    export OMP_NUM_THREADS=$threads
    ./benchmark_cpu_fixed
    echo "-------------------"
done