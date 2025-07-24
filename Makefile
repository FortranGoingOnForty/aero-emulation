# Makefile for CMAQ GPU Benchmarks
# Author: mfw
# Date: July 2025

# Compilers
FC = gfortran
NVCC = nvcc

# Flags
FFLAGS = -O3 -fopenmp
NVCCFLAGS = -O3 -arch=sm_86 -std=c++11

# Directories
SRC_CPU = src_cpu
SRC_GPU = src_gpu

# Default target
all: cpu gpu

# CPU target
cpu: benchmark_cpu_complex

benchmark_cpu_complex: $(SRC_CPU)/aero_kernel_complex.f90 $(SRC_CPU)/benchmark_cpu_complex.f90
	$(FC) $(FFLAGS) -o $@ $^

# GPU target
gpu: benchmark_gpu_complex

benchmark_gpu_complex: aero_kernel_complex.o $(SRC_GPU)/benchmark_gpu_complex.cpp
	$(NVCC) $(NVCCFLAGS) -o $@ $^

aero_kernel_complex.o: $(SRC_GPU)/aero_kernel_complex.cu
	$(NVCC) $(NVCCFLAGS) -c -o $@ $<

# Clean
clean:
	rm -f benchmark_cpu_complex benchmark_gpu_complex
	rm -f *.o *.mod

.PHONY: all cpu gpu clean