// benchmark_gpu_complex.cpp
#include <iostream>
#include <chrono>
#include <cmath>
#include <cuda_runtime.h>

#define N_AEROSPC 40
#define N_MODE 3
#define N_SIZE_BINS 40

extern "C" void launch_complex_aerosol_kernels(
    float* d_temp, float* d_pres, float* d_rh,
    float* d_aerosol_mass, float* d_aerosol_water,
    float* d_size_dist, float* d_num_conc,
    float* d_h2so4, float* d_nh3,
    float dt, int ncells, int nsteps);

int main() {
    // Test different problem sizes
    int sizes[] = {10000, 100000, 500000, 1000000};
    
    for (int s = 0; s < 4; s++) {
        int ncells = sizes[s];
        const int nsteps = 100;
        const float dt = 1.0f;
        
        std::cout << "\nTesting with " << ncells << " cells:" << std::endl;
        std::cout << "------------------------" << std::endl;
        
        // Allocate device memory
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
        
        // Initialize with realistic values (simplified)
        // In real case, would copy from host
        cudaMemset(d_aerosol_mass, 1.0f, ncells * N_MODE * sizeof(float));
        cudaMemset(d_h2so4, 1e7f, ncells * sizeof(float));
        
        // Warmup
        launch_complex_aerosol_kernels(
            d_temp, d_pres, d_rh, d_aerosol_mass, d_aerosol_water,
            d_size_dist, d_num_conc, d_h2so4, d_nh3, dt, ncells, 10);
        
        // Benchmark
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
        
        // Cleanup
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