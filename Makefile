# Makefile for emulated CMAQ GPU Benchmarks
# Author: mfw
# Date: July 2025

# Compilers
FC = gfortran
CXX = g++
NVCC = nvcc

# Compiler flags
FFLAGS = -O3 -fopenmp -fcheck=bounds
FFLAGS_DEBUG = -O0 -g -fopenmp -fcheck=bounds -Wall -fbacktrace
CXXFLAGS = -O3 -std=c++11
NVCCFLAGS = -O3 -arch=sm_86 -std=c++11
LDFLAGS = -fopenmp

# CUDA architecture (A2 GPU is sm_86)
# Change to sm_80 or sm_75 if sm_86 doesn't work
GPU_ARCH = sm_86

# Directories
SRC_CPU = src_cpu
SRC_GPU = src_gpu
OBJ_DIR = obj
BIN_DIR = .

# Create object directory
$(shell mkdir -p $(OBJ_DIR))

# CPU Fortran sources
CPU_SIMPLE_SRCS = $(SRC_CPU)/aero_kernel_extracted.f90 \
                  $(SRC_CPU)/benchmark_cpu.f90

CPU_COMPLEX_SRCS = $(SRC_CPU)/aero_kernel_complex.f90 \
                   $(SRC_CPU)/benchmark_cpu_complex.f90

# GPU sources
# Note: Simple GPU sources are missing, only complex exists
GPU_COMPLEX_SRCS = $(SRC_GPU)/aero_kernel_complex.cu \
                   $(SRC_GPU)/benchmark_gpu_complex.cpp

# Targets
CPU_TARGETS = benchmark_cpu benchmark_cpu_fixed benchmark_cpu_complex benchmark_cpu_complex_debug
GPU_TARGETS = benchmark_gpu_complex  # benchmark_gpu sources missing
ALL_TARGETS = $(CPU_TARGETS) $(GPU_TARGETS)

# Default target
all: $(ALL_TARGETS)

# CPU Benchmarks
benchmark_cpu: $(CPU_SIMPLE_SRCS)
	$(FC) $(FFLAGS) -o $@ $^ $(LDFLAGS)

benchmark_cpu_fixed: $(CPU_SIMPLE_SRCS)
	$(FC) $(FFLAGS) -o $@ $^ $(LDFLAGS)

benchmark_cpu_complex: $(CPU_COMPLEX_SRCS)
	$(FC) $(FFLAGS) -o $@ $^ $(LDFLAGS)

benchmark_cpu_complex_debug: $(CPU_COMPLEX_SRCS)
	$(FC) $(FFLAGS_DEBUG) -o $@ $^ $(LDFLAGS)

# GPU Benchmarks
benchmark_gpu: $(OBJ_DIR)/aero_kernel.o $(SRC_GPU)/benchmark_gpu.cpp
	$(NVCC) $(NVCCFLAGS) -o $@ $^

benchmark_gpu_complex: $(OBJ_DIR)/aero_kernel_complex.o $(SRC_GPU)/benchmark_gpu_complex.cpp
	$(NVCC) $(NVCCFLAGS) -o $@ $^

# GPU object files
$(OBJ_DIR)/aero_kernel.o: $(SRC_GPU)/aero_kernel.cu
	$(NVCC) $(NVCCFLAGS) -c -o $@ $<

$(OBJ_DIR)/aero_kernel_complex.o: $(SRC_GPU)/aero_kernel_complex.cu
	$(NVCC) $(NVCCFLAGS) -c -o $@ $<

# Phony targets
.PHONY: all clean cpu gpu test help

# Build only CPU targets
cpu: $(CPU_TARGETS)

# Build only GPU targets  
gpu: $(GPU_TARGETS)

# Run quick tests
test: all
	@echo "=== Running Quick Tests ==="
	@echo "Testing CPU simple (1 thread)..."
	@OMP_NUM_THREADS=1 ./benchmark_cpu_fixed | grep "Time per timestep" || echo "benchmark_cpu_fixed not found"
	@echo ""
	@echo "Testing CPU complex (16 threads)..."
	@OMP_NUM_THREADS=16 ./benchmark_cpu_complex 10000 | grep "Time per timestep"
	@echo ""
	@echo "Testing GPU complex (10k cells)..."
	@./benchmark_gpu_complex | grep -A1 "Testing with 10000" | grep "Time per timestep"

# Run full comparison
comparison: all
	@echo "Submitting full comparison job..."
	sbatch run_full_comparison_fixed.sh

# Clean build artifacts
clean:
	rm -f $(ALL_TARGETS)
	rm -f $(OBJ_DIR)/*.o
	rm -f *.mod
	rm -f *.tmp
	rm -rf $(OBJ_DIR)

# Clean everything including outputs
cleanall: clean
	rm -f *.out
	rm -f cpu_*.txt gpu_*.txt
	rm -f slurm-*.out
	rm -rf out/

# Help message
help:
	@echo "CMAQ AERO GPU Benchmark Makefile"
	@echo "================================"
	@echo ""
	@echo "Targets:"
	@echo "  all       - Build all CPU and GPU benchmarks (default)"
	@echo "  cpu       - Build only CPU benchmarks"
	@echo "  gpu       - Build only GPU benchmarks"
	@echo "  test      - Run quick validation tests"
	@echo "  comparison - Submit full comparison job to SLURM"
	@echo "  clean     - Remove executables and object files"
	@echo "  cleanall  - Remove all generated files including outputs"
	@echo "  help      - Show this message"
	@echo ""
	  @echo "Individual targets:"
	@echo "  benchmark_cpu         - Simple CPU benchmark" 
	@echo "  benchmark_cpu_fixed   - Simple CPU benchmark (fixed arrays)"
	@echo "  benchmark_cpu_complex - Complex CPU benchmark"
	@echo "  benchmark_cpu_complex_debug - Complex CPU benchmark (debug)"
	@echo "  benchmark_gpu_complex - Complex GPU benchmark"
	@echo ""
	@echo "Note: benchmark_gpu target is missing source files (aero_kernel.cu)"
	@echo ""
	@echo "Examples:"
	@echo "  make              # Build everything"
	@echo "  make cpu          # Build only CPU versions"
	@echo "  make gpu          # Build only GPU versions"
	@echo "  make test         # Run quick tests"
	@echo "  make clean        # Clean build files"
	@echo ""
	@echo "To change GPU architecture (default: sm_86 for A2):"
	@echo "  make GPU_ARCH=sm_80 gpu"
	@echo ""
	@echo "To use different compilers:"
	@echo "  make FC=ifort CXX=icpc cpu"

# Print configuration
info:
	@echo "Build Configuration:"
	@echo "===================="
	@echo "Fortran compiler: $(FC)"
	@echo "C++ compiler: $(CXX)"
	@echo "CUDA compiler: $(NVCC)"
	@echo "GPU architecture: $(GPU_ARCH)"
	@echo "Fortran flags: $(FFLAGS)"
	@echo "CUDA flags: $(NVCCFLAGS)"
	@echo ""
	@echo "Source directories:"
	@echo "  CPU: $(SRC_CPU)"
	@echo "  GPU: $(SRC_GPU)"

# Dependencies
benchmark_cpu benchmark_cpu_fixed: $(SRC_CPU)/aero_kernel_extracted.f90
benchmark_cpu_complex benchmark_cpu_complex_debug: $(SRC_CPU)/aero_kernel_complex.f90