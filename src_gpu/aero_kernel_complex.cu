// aero_kernel_complex.cu

#include <cuda_runtime.h>
#include <math.h>
#include <stdio.h>

/*
 * ---------------------------------------------------------------------------
 *  GPU aerosol microphysics proof‑of‑concept for CMAQ
 *
 *  This translation unit contains three CUDA kernels that collectively
 *  emulate the most expensive portions of CMAQ’s AERO module:
 *      • thermodynamic water‑uptake iterations
 *      • sectional Brownian coagulation
 *      • ternary H2SO4–NH3–H2O nucleation
 *
 *  The goal is *performance characterization*—not a production‑ready drop‑in.
 *  All kernels assume:
 *      • one thread = one grid‑cell
 *      • state remains resident on device between timesteps
 *  The public C interface `launch_complex_aerosol_kernels()` wraps these
 *  kernels so that a Fortran driver (or C/​C++) can benchmark them easily.
 *
 *  Author  : mfw
 *  Created : 2025.07
 * ---------------------------------------------------------------------------
 */

#define N_AEROSPC 40
#define N_MODE 3
#define N_SIZE_BINS 40

// CUDA error checking
#define CUDA_CHECK(call) do { \
    cudaError_t error = call; \
    if (error != cudaSuccess) { \
        fprintf(stderr, "CUDA error at %s:%d - %s\n", __FILE__, __LINE__, \
                cudaGetErrorString(error)); \
        exit(1); \
    } \
} while(0)

/**
 * @brief  Per‑cell Köhler/ISORROPIA‑style water‑uptake solver.
 *
 * Computes equilibrium liquid water for each log‑normal aerosol mode via
 * 20 Picard iterations.  For realism it approximates:
 *    • Debye–Hückel activity‑coefficients (ionic‑strength dependent)  
 *    • Zdanovskii–Stokes–Robinson (ZSR) mixing rule
 *
 * @param  temp          [in]  °K array, length = ncells
 * @param  pres          [in]  Pa  array, length = ncells
 * @param  rh            [in]  0–1 relative humidity, length = ncells
 * @param  aerosol_mass  [in]  dry mass  (ncells × N_MODE)
 * @param  aerosol_water [out] updated water mass (ncells × N_MODE)
 * @param  ncells        total number of grid cells
 *
 * Thread‑parallelism: one CUDA thread ↔ one grid‑cell.
 * Arithmetic intensity: ~5 kFLOP per cell → well suited to GPUs.
 */
__global__ void aerosol_thermodynamics_kernel(
    const float* temp, const float* pres, const float* rh,
    float* aerosol_mass, float* aerosol_water,
    const int ncells)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= ncells) return;
    
    float T = temp[idx];
    float P = pres[idx];
    float RH = rh[idx];
    
    // Simplified ISORROPIA-like calculations
    // Water uptake by aerosols (simplified Köhler theory)
    for (int i = 0; i < N_MODE; i++) {
        float dry_mass = aerosol_mass[idx * N_MODE + i];
        
        // Multiple iterations for convergence (like real ISORROPIA)
        float water_content = 0.0f;
        for (int iter = 0; iter < 20; iter++) {
            // Activity coefficient calculation
            float ionic_strength = 0.1f * dry_mass / (water_content + 1.0f);
            float activity_coeff = expf(-0.5f * sqrtf(ionic_strength));
            
            // Water activity
            float aw = RH * activity_coeff;
            
            // ZSR relation for water uptake
            float sum_term = 0.0f;
            for (int j = 0; j < 10; j++) {  // 10 species
                float molality = dry_mass * 0.1f / (water_content + 0.001f);
                sum_term += molality * (1.0f + 0.8f * powf(aw, j));
            }
            
            // Update water content
            float new_water = dry_mass * sum_term * 0.018f;  // MW of water
            
            // Damped update for stability
            water_content = 0.7f * water_content + 0.3f * new_water;
        }
        
        aerosol_water[idx * N_MODE + i] = water_content;
    }
}

/**
 * @brief  Sectional Brownian coagulation over 40 size bins.
 *
 * For each cell the kernel loops over all (i,j) bin pairs, applies the
 * diffusive coagulation coefficient βᵢⱼ, removes number from bins i & j and
 * adds it to a larger recipient bin k.  A local register copy minimises
 * global‑memory traffic.
 *
 * Inputs/Outputs are flattened arrays of length ncells × N_SIZE_BINS that
 * store number concentration [#/cm³].
 *
 * Computational cost: O(N_BIN^2) ≃ 1600 inner‑loop iterations per thread.
 */
__global__ void coagulation_sectional_kernel(
    float* size_distribution, const float* temp, const float* pres,
    const float dt, const int ncells)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= ncells) return;
    
    float T = temp[idx];
    float P = pres[idx];
    
    // Local copy of size distribution
    float local_dist[N_SIZE_BINS];
    for (int i = 0; i < N_SIZE_BINS; i++) {
        local_dist[i] = size_distribution[idx * N_SIZE_BINS + i];
    }
    
    // Brownian coagulation kernel (more realistic)
    float new_dist[N_SIZE_BINS] = {0.0f};
    
    for (int i = 0; i < N_SIZE_BINS; i++) {
        for (int j = 0; j < N_SIZE_BINS; j++) {
            // Particle diameters (log-spaced)
            float dp_i = 0.001f * expf(i * 0.2f);  // microns
            float dp_j = 0.001f * expf(j * 0.2f);
            
            // Cunningham slip correction
            float Cc_i = 1.0f + 2.0f * 0.066f / dp_i * 
                         (1.257f + 0.4f * expf(-1.1f * dp_i / 0.066f));
            float Cc_j = 1.0f + 2.0f * 0.066f / dp_j * 
                         (1.257f + 0.4f * expf(-1.1f * dp_j / 0.066f));
            
            // Diffusion coefficients
            float kb = 1.38e-23f;
            float mu = 1.8e-5f;
            float D_i = kb * T * Cc_i / (3.0f * 3.14159f * mu * dp_i * 1e-6f);
            float D_j = kb * T * Cc_j / (3.0f * 3.14159f * mu * dp_j * 1e-6f);
            
            // Coagulation coefficient
            float beta_ij = 4.0f * 3.14159f * (D_i + D_j) * (dp_i + dp_j) * 1e-6f;
            
            // Loss from bins i and j
            new_dist[i] -= beta_ij * local_dist[i] * local_dist[j] * dt;
            
            // Production in larger bins
            int k = min(i + j/2, N_SIZE_BINS - 1);
            new_dist[k] += 0.5f * beta_ij * local_dist[i] * local_dist[j] * dt;
        }
    }
    
    // Update distribution
    for (int i = 0; i < N_SIZE_BINS; i++) {
        size_distribution[idx * N_SIZE_BINS + i] = 
            fmaxf(0.0f, local_dist[i] + new_dist[i]);
    }
}

/**
 * @brief  Ternary H2SO4–NH3–H2O nucleation parameterisation.
 *
 * Adds freshly nucleated particles to the smallest modal bin when sulphuric
 * acid exceeds 10^6 molec cm^-3 and RH > 30 %.
 *
 * Updates `num_conc[idx * N_MODE]` in‑place.
 *
 * Lightweight & branch‑light; mainly memory bound.
 */
__global__ void nucleation_kernel(
    float* num_conc, const float* h2so4_conc, const float* nh3_conc,
    const float* temp, const float* rh, const float dt, const int ncells)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= ncells) return;
    
    float T = temp[idx];
    float RH = rh[idx];
    float H2SO4 = h2so4_conc[idx];
    float NH3 = nh3_conc[idx];
    
    // Simplified ternary nucleation (H2SO4-NH3-H2O)
    if (H2SO4 > 1e6f && RH > 0.3f) {
        // Nucleation rate (molecules/cm3/s)
        float a1 = -20.0f + 0.3f * T;
        float a2 = 1e-20f * expf(25.0f * (RH - 0.5f));
        float a3 = 1.0f + 0.1f * logf(NH3 / 1e10f);
        
        float J_nuc = a2 * powf(H2SO4 / 1e6f, 2.0f) * a3 * expf(a1 / T);
        
        // Add new particles to smallest size bin
        num_conc[idx * N_MODE] += J_nuc * dt;
    }
}

/**
 * @brief  Host‑side driver that launches all three GPU kernels for `nsteps`.
 *
 * The caller supplies **device pointers**; no allocations or H–D copies are
 * performed inside.  The sequence per timestep is:
 *    (1) aerosol_thermodynamics_kernel
 *    (2) coagulation_sectional_kernel
 *    (3) nucleation_kernel
 * followed by a `cudaDeviceSynchronize()` to keep behaviour deterministic.
 *
 * This wrapper deliberately uses a single stream—future work could overlap
 * kernels and data transfers via multiple streams or CUDA graphs.
 */
// Combined kernel launcher
extern "C" {
    void launch_complex_aerosol_kernels(
        float* d_temp, float* d_pres, float* d_rh,
        float* d_aerosol_mass, float* d_aerosol_water,
        float* d_size_dist, float* d_num_conc,
        float* d_h2so4, float* d_nh3,
        float dt, int ncells, int nsteps)
    {
        int threads = 256;
        int blocks = (ncells + threads - 1) / threads;
        
        for (int step = 0; step < nsteps; step++) {
            // Thermodynamics
            aerosol_thermodynamics_kernel<<<blocks, threads>>>(
                d_temp, d_pres, d_rh, d_aerosol_mass, d_aerosol_water, ncells);
            
            // Coagulation
            coagulation_sectional_kernel<<<blocks, threads>>>(
                d_size_dist, d_temp, d_pres, dt, ncells);
            
            // Nucleation
            nucleation_kernel<<<blocks, threads>>>(
                d_num_conc, d_h2so4, d_nh3, d_temp, d_rh, dt, ncells);
            
            CUDA_CHECK(cudaDeviceSynchronize());
        }
    }
}