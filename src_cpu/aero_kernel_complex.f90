! -----------------------------------------------------------------------------
!  Complex CPU aerosol microphysics proof‑of‑concept for CMAQ
!
!  This module mirrors the GPU implementation in aero_kernel_complex.cu.
!  Provides two routines:
!      * aerosol_thermodynamics: per‑cell Köhler/ISORROPIA‑style water uptake solver
!      * coagulation_sectional: sectional Brownian coagulation over size bins
!
!  Author  : mfw
!  Created : 2025.07
!  Purpose : Performance characterization of aerosol microphysics kernels.
! -----------------------------------------------------------------------------
! aero_kernel_complex.f90 - Complex CPU version to match GPU
module aero_kernel_complex_cpu
  implicit none
  
  integer, parameter :: n_aerospc = 40
  integer, parameter :: n_mode = 3
  integer, parameter :: n_size_bins = 40
  
contains

  !> @brief Per‑cell Köhler/ISORROPIA‑style water‑uptake solver.
  !>
  !> Implements a Picard iteration of 20 steps per mode to compute equilibrium
  !> liquid water content. Approximates:
  !>   • Debye–Hückel activity‑coefficients (ionic-strength dependent)
  !>   • Zdanovskii–Stokes–Robinson (ZSR) mixing rule
  !>
  !> @param temp          (in)  Temperature [K], dimension = ncells
  !> @param pres          (in)  Pressure [Pa],    dimension = ncells
  !> @param rh            (in)  Relative humidity (0–1), dimension = ncells
  !> @param aerosol_mass  (in)  Dry aerosol mass, shape = (n_mode, ncells)
  !> @param aerosol_water (out) Water mass per mode, shape = (n_mode, ncells)
  !> @param ncells        (in)  Total number of grid cells
  !>
  !> Complexity: ~5 kFLOP per cell
  !> Parallel: OpenMP, one thread per grid cell
  subroutine aerosol_thermodynamics(temp, pres, rh, aerosol_mass, aerosol_water, ncells)
    integer, intent(in) :: ncells
    real, intent(in) :: temp(ncells), pres(ncells), rh(ncells)
    real, intent(in) :: aerosol_mass(n_mode, ncells)
    real, intent(out) :: aerosol_water(n_mode, ncells)
    
    integer :: i, j, iter, mode
    real :: water_content, ionic_strength, activity_coeff, aw
    real :: sum_term, molality, new_water
    
    !$omp parallel do private(i,mode,water_content,iter,ionic_strength,activity_coeff,aw,sum_term,j,molality,new_water)
    do i = 1, ncells
      do mode = 1, n_mode
        water_content = 0.0
        
        ! Iterative water uptake calculation (like ISORROPIA)
        do iter = 1, 20
          ionic_strength = 0.1 * aerosol_mass(mode,i) / (water_content + 1.0)
          activity_coeff = exp(-0.5 * sqrt(ionic_strength))
          aw = rh(i) * activity_coeff
          
          sum_term = 0.0
          do j = 1, 10
            molality = aerosol_mass(mode,i) * 0.1 / (water_content + 0.001)
            sum_term = sum_term + molality * (1.0 + 0.8 * aw**j)
          end do
          
          new_water = aerosol_mass(mode,i) * sum_term * 0.018
          water_content = 0.7 * water_content + 0.3 * new_water
        end do
        
        aerosol_water(mode,i) = water_content
      end do
    end do
    !$omp end parallel do
  end subroutine

  !> @brief Sectional Brownian coagulation over size bins.
  !>
  !> For each grid cell, loops over all bin pairs (i,j), computes
  !> diffusive coagulation coefficients βᵢⱼ, and updates a local
  !> size distribution. Uses a register-local copy to minimize
  !> global-memory traffic.
  !>
  !> @param size_dist (inout) Particle number distribution, shape = (n_size_bins, ncells)
  !> @param temp      (in)    Temperature [K],    dimension = ncells
  !> @param pres      (in)    Pressure [Pa],       dimension = ncells
  !> @param dt        (in)    Timestep length [s]
  !> @param ncells    (in)    Total number of grid cells
  !>
  !> Complexity: O(n_size_bins^2) per cell (~1600 inner iterations)
  !> Parallel: OpenMP, one thread per grid cell
  subroutine coagulation_sectional(size_dist, temp, pres, dt, ncells)
    integer, intent(in) :: ncells
    real, intent(inout) :: size_dist(n_size_bins, ncells)
    real, intent(in) :: temp(ncells), pres(ncells), dt
    
    integer :: i, j, k, cell
    real :: dp_i, dp_j, Cc_i, Cc_j, D_i, D_j, beta_ij
    real :: kb = 1.38e-23, mu = 1.8e-5
    real :: new_dist(n_size_bins)
    
    !$omp parallel do private(cell,i,j,dp_i,dp_j,Cc_i,Cc_j,D_i,D_j,beta_ij,k,new_dist)
    do cell = 1, ncells
      new_dist = 0.0
      
      do i = 1, n_size_bins
        do j = 1, n_size_bins
          ! Particle diameters
          dp_i = 0.001 * exp(real(i-1) * 0.2)
          dp_j = 0.001 * exp(real(j-1) * 0.2)
          
          ! Cunningham correction
          Cc_i = 1.0 + 2.0 * 0.066 / dp_i * (1.257 + 0.4 * exp(-1.1 * dp_i / 0.066))
          Cc_j = 1.0 + 2.0 * 0.066 / dp_j * (1.257 + 0.4 * exp(-1.1 * dp_j / 0.066))
          
          ! Diffusion coefficients
          D_i = kb * temp(cell) * Cc_i / (3.0 * 3.14159 * mu * dp_i * 1e-6)
          D_j = kb * temp(cell) * Cc_j / (3.0 * 3.14159 * mu * dp_j * 1e-6)
          
          ! Coagulation coefficient
          beta_ij = 4.0 * 3.14159 * (D_i + D_j) * (dp_i + dp_j) * 1e-6
          
          ! Update distribution
          new_dist(i) = new_dist(i) - beta_ij * size_dist(i,cell) * size_dist(j,cell) * dt
          
          k = min(i + j/2, n_size_bins)
          new_dist(k) = new_dist(k) + 0.5 * beta_ij * size_dist(i,cell) * size_dist(j,cell) * dt
        end do
      end do
      
      ! Update size distribution
      do i = 1, n_size_bins
        size_dist(i,cell) = max(0.0, size_dist(i,cell) + new_dist(i))
      end do
    end do
    !$omp end parallel do
  end subroutine

end module aero_kernel_complex_cpu