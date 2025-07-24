/*
 * ---------------------------------------------------------------------------
 * GPU aerosol microphysics benchmark driver for CMAQ AERO proof-of-concept
 *
 * This executable measures the runtime of the combined aerosol kernels
 * (thermodynamics, coagulation, nucleation) on varying grid sizes.
 * It reports wall-clock timings, per-timestep durations, and throughput.
 *
 * Author  : mfw
 * Created : 2025.07
 * ---------------------------------------------------------------------------
 */
// benchmark_gpu_complex.cpp
#include <iostream>
#include <chrono>
#include <cmath>
#include <cuda_runtime.h>

#define N_AEROSPC 40
#define N_MODE 3
#define N_SIZE_BINS 40

/**
 * @brief Prototype for the combined GPU kernel launcher.
 *
 * This function wraps the three CUDA kernels:
 *   1. aerosol_thermodynamics_kernel
 *   2. coagulation_sectional_kernel
 *   3. nucleation_kernel
 *
 * It executes these kernels sequentially for each timestep and
 * synchronizes the device to ensure deterministic timing.
 *
 * @param d_temp         Device pointer to temperature array (ncells)
 * @param d_pres         Device pointer to pressure array (ncells)
 * @param d_rh           Device pointer to relative humidity array (ncells)
 * @param d_aerosol_mass Device pointer to dry aerosol mass (ncells × N_MODE)
 * @param d_aerosol_water Device pointer to aerosol water mass output (ncells × N_MODE)
 * @param d_size_dist    Device pointer to size distribution array (ncells × N_SIZE_BINS)
 * @param d_num_conc     Device pointer to number concentration array (ncells × N_MODE)
 * @param d_h2so4        Device pointer to sulphuric acid concentration (ncells)
 * @param d_nh3          Device pointer to ammonia concentration (ncells)
 * @param dt             Timestep size
 * @param ncells         Number of grid cells
 * @param nsteps         Number of timesteps to execute
 */

extern "C" void launch_complex_aerosol_kernels(
    float* d_temp, float* d_pres, float* d_rh,
    float* d_aerosol_mass, float* d_aerosol_water,
    float* d_size_dist, float* d_num_conc,
    float* d_h2so4, float* d_nh3,
    float dt, int ncells, int nsteps);

/**
 * @brief Entry point for the GPU benchmark driver.
 *
 * Iterates over a set of grid cell counts, allocates GPU memory,
 * initializes inputs, performs a warmup, and then measures the execution
 * time of `launch_complex_aerosol_kernels` over a fixed number of timesteps.
 *
 * Outputs:
 *   - Total GPU time (seconds)
 *   - Time per timestep (seconds)
 *   - Cells processed per second
 */
int main() {
    // Define problem sizes: number of grid cells to test
    int sizes[] = {10000, 100000, 500000, 1000000};
    
    for (int s = 0; s < 4; s++) {
        int ncells = sizes[s];
        const int nsteps = 100;
        const float dt = 1.0f;
        
        std::cout << "\nTesting with " << ncells << " cells:" << std::endl;
        std::cout << "------------------------" << std::endl;
        
        // Allocate device memory for inputs and outputs
        float *d_temp, *d_pres, *d_rh;
        float *d_aerosol_mass, *d_aerosol_water;
        float *d_size_dist, *d_num_conc;
        float *d_h2so4, *d_nh3;
        
        cudaMalloc(&d_temp, ncells * sizeof(float));
        cudaMalloc(&d_pres, ncells * sizeof(float));
        cudaMalloc(&d_rh, ncells * sizeof(float));
        cudaMalloc(&d_aerosol_mass, ncells * N_MODE * sizeof(float));
        cudaMalloc(&d_aerosol_water, ncells * N_MODE * sizeof(float));
        cudaMalloc(&d_size_dist, ncells * N_SIZE_BINS * sizeof(float));
        cudaMalloc(&d_num_conc, ncells * N_MODE * sizeof(float));
        cudaMalloc(&d_h2so4, ncells * sizeof(float));
        cudaMalloc(&d_nh3, ncells * sizeof(float));
        
        // Initialize device buffers with representative test values
        // In real case, would copy from host
        cudaMemset(d_aerosol_mass, 1.0f, ncells * N_MODE * sizeof(float));
        cudaMemset(d_h2so4, 1e7f, ncells * sizeof(float));
        
        // Warmup run: execute a small number of timesteps to eliminate startup overhead
        launch_complex_aerosol_kernels(
            d_temp, d_pres, d_rh, d_aerosol_mass, d_aerosol_water,
            d_size_dist, d_num_conc, d_h2so4, d_nh3, dt, ncells, 10);
        
        // Start timed benchmark run
        auto start = std::chrono::high_resolution_clock::now();
        
        launch_complex_aerosol_kernels(
            d_temp, d_pres, d_rh, d_aerosol_mass, d_aerosol_water,
            d_size_dist, d_num_conc, d_h2so4, d_nh3, dt, ncells, nsteps);
        
        cudaDeviceSynchronize();
        auto end = std::chrono::high_resolution_clock::now();
        
        std::chrono::duration<double> diff = end - start;
        double gpu_time = diff.count();
        
        std::cout << "GPU Time: " << gpu_time << " seconds" << std::endl;
        std::cout << "Time per timestep: " << gpu_time / nsteps << " seconds" << std::endl;
        std::cout << "Cells/second: " << ncells * nsteps / gpu_time << std::endl;
        
        // Cleanup: free device memory allocations
        cudaFree(d_temp);
        cudaFree(d_pres);
        cudaFree(d_rh);
        cudaFree(d_aerosol_mass);
        cudaFree(d_aerosol_water);
        cudaFree(d_size_dist);
        cudaFree(d_num_conc);
        cudaFree(d_h2so4);
        cudaFree(d_nh3);
    }
    
    return 0;
}