#!/bin/bash
#SBATCH --job-name=aero_full_comp
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --gres=gpu:1
#SBATCH --time=00:30:00
#SBATCH --output=full_comparison_%j.out

cd ~/cmaq_aero_gpu_bench
ulimit -s unlimited

echo "CMAQ AERO Full Comparison: Simple vs Complex Kernels"
echo "==================================================="
echo "Date: $(date)"
echo "Node: $(hostname)"
echo ""

# GPU info
echo "GPU Information:"
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
echo ""

# Test parameters
NCELLS=100000
export OMP_NUM_THREADS=16

echo "Test Configuration:"
echo "- Grid cells: $NCELLS"
echo "- CPU threads: $OMP_NUM_THREADS"
echo "- 100 timesteps per test"
echo ""

# Function to extract time
get_time() {
    grep "Time per timestep" $1 2>/dev/null | tail -1 | awk '{print $4}'
}

echo "======================================"
echo "SIMPLE KERNEL TESTS"
echo "======================================"

# Simple CPU
echo ""
echo "Simple CPU (16 threads):"
./benchmark_cpu_fixed > simple_cpu.tmp 2>&1
cat simple_cpu.tmp | grep -E "Time per timestep|Cells processed|Sample results" -A2
simple_cpu_time=$(get_time simple_cpu.tmp)

# Simple GPU  
echo ""
echo "Simple GPU:"
./benchmark_gpu > simple_gpu.tmp 2>&1
cat simple_gpu.tmp | grep -E "Time per timestep|Cells processed|Sample results" -A2
simple_gpu_time=$(get_time simple_gpu.tmp)

# Simple speedup
if [ ! -z "$simple_cpu_time" ] && [ ! -z "$simple_gpu_time" ]; then
    simple_speedup=$(awk -v c=$simple_cpu_time -v g=$simple_gpu_time 'BEGIN {printf "%.2f", c/g}')
    echo ""
    echo "Simple Kernel GPU Speedup: ${simple_speedup}x"
fi

echo ""
echo "======================================"
echo "COMPLEX KERNEL TESTS"
echo "======================================"

# Complex CPU
echo ""
echo "Complex CPU (16 threads):"
./benchmark_cpu_complex $NCELLS > complex_cpu.tmp 2>&1
cat complex_cpu.tmp | grep -E "Time per timestep|Cells/second"
complex_cpu_time=$(get_time complex_cpu.tmp)

# Complex GPU
echo ""
echo "Complex GPU:"
./benchmark_gpu_complex > complex_gpu.tmp 2>&1
grep -A5 "Testing with $NCELLS" complex_gpu.tmp | grep -E "Time per timestep|Cells/second"
complex_gpu_time=$(grep -A5 "Testing with $NCELLS" complex_gpu.tmp | grep "Time per timestep" | awk '{print $4}')

# Complex speedup
if [ ! -z "$complex_cpu_time" ] && [ ! -z "$complex_gpu_time" ]; then
    complex_speedup=$(awk -v c=$complex_cpu_time -v g=$complex_gpu_time 'BEGIN {printf "%.2f", c/g}')
    echo ""
    echo "Complex Kernel GPU Speedup: ${complex_speedup}x"
fi

echo ""
echo "======================================"
echo "PERFORMANCE SUMMARY"
echo "======================================"
echo ""
printf "%-20s %-20s %-20s %-15s\n" "Kernel Type" "CPU Time (s)" "GPU Time (s)" "GPU Speedup"
printf "%-20s %-20s %-20s %-15s\n" "-----------" "------------" "------------" "-----------"

if [ ! -z "$simple_cpu_time" ] && [ ! -z "$simple_gpu_time" ]; then
    printf "%-20s %-20s %-20s %-15s\n" "Simple" "$simple_cpu_time" "$simple_gpu_time" "${simple_speedup}x"
fi

if [ ! -z "$complex_cpu_time" ] && [ ! -z "$complex_gpu_time" ]; then
    printf "%-20s %-20s %-20s %-15s\n" "Complex" "$complex_cpu_time" "$complex_gpu_time" "${complex_speedup}x"
fi

echo ""
echo "======================================"
echo "COMPUTATIONAL INTENSITY ANALYSIS"
echo "======================================"

# Calculate FLOPS estimates
echo ""
echo "Estimated FLOPS per cell per timestep:"
echo "- Simple kernel: ~100 FLOPS (mostly memory ops)"
echo "- Complex kernel: ~10,000 FLOPS (iterative solver, coagulation)"

if [ ! -z "$simple_gpu_time" ] && [ ! -z "$complex_gpu_time" ]; then
    simple_gflops=$(awk -v n=$NCELLS -v t=$simple_gpu_time 'BEGIN {printf "%.2f", (n*100*100)/(t*1e9)}')
    complex_gflops=$(awk -v n=$NCELLS -v t=$complex_gpu_time 'BEGIN {printf "%.2f", (n*10000*100)/(t*1e9)}')
    
    echo ""
    echo "Achieved GPU Performance:"
    echo "- Simple kernel: ${simple_gflops} GFLOPS"
    echo "- Complex kernel: ${complex_gflops} GFLOPS"
fi

echo ""
echo "======================================"
echo "KEY INSIGHTS"
echo "======================================"

if [ ! -z "$simple_speedup" ] && [ ! -z "$complex_speedup" ]; then
    ratio=$(awk -v s=$simple_speedup -v c=$complex_speedup 'BEGIN {printf "%.2f", c/s}')
    echo ""
    echo "- Simple kernel GPU speedup: ${simple_speedup}x"
    echo "- Complex kernel GPU speedup: ${complex_speedup}x"
    echo "- Complex/Simple speedup ratio: ${ratio}"
    echo ""
    
    if (( $(awk -v r=$ratio 'BEGIN {print (r < 0.5)}') )); then
        echo "The complex kernel shows LESS speedup than simple."
        echo "This suggests the problem is compute-bound and the GPU"
        echo "is not being fully utilized due to algorithm structure."
    elif (( $(awk -v r=$ratio 'BEGIN {print (r > 1.5)}') )); then
        echo "The complex kernel shows MORE speedup than simple."
        echo "This is excellent - real chemistry benefits more from GPU!"
    else
        echo "Both kernels show similar speedup."
        echo "The GPU provides consistent acceleration across workloads."
    fi
fi

echo ""
echo "GPU Utilization Check:"
nvidia-smi --query-gpu=utilization.gpu,utilization.memory --format=csv

# Cleanup
rm -f simple_cpu.tmp simple_gpu.tmp complex_cpu.tmp complex_gpu.tmp

echo ""
echo "Test completed at $(date)"