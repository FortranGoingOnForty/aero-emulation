! aero_kernel_extracted.f90
! Simplified AERO kernel for GPU benchmarking

module aero_kernel_cpu
  implicit none
  
  ! Simplified parameters from AERO_DATA
  integer, parameter :: n_aerospc = 40    ! Number of aerosol species
  integer, parameter :: n_mode = 3        ! Aitken, accumulation, coarse
  real, parameter :: min_sigma_g = 1.05
  real, parameter :: max_sigma_g = 2.50
  
contains

  subroutine aerosol_mass_update(temp, pres, rh, dt, &
                                  aerosol_conc, aerosol_mass)
    real, intent(in) :: temp, pres, rh, dt
    real, intent(in) :: aerosol_conc(n_aerospc)
    real, intent(inout) :: aerosol_mass(n_mode)
    
    integer :: i, j
    real :: growth_rate, settling_vel
    
    ! Simplified aerosol growth calculation
    do i = 1, n_mode
      growth_rate = 1.0e-6 * temp / pres * rh
      
      do j = 1, n_aerospc/n_mode
        aerosol_mass(i) = aerosol_mass(i) + &
          aerosol_conc(j + (i-1)*n_aerospc/n_mode) * growth_rate * dt
      end do
      
      ! Simple gravitational settling
      settling_vel = 0.001 * aerosol_mass(i) / (temp * pres)
      aerosol_mass(i) = aerosol_mass(i) * (1.0 - settling_vel * dt)
    end do
    
  end subroutine aerosol_mass_update

  subroutine coagulation_kernel(num_conc, diam, temp, pres, dt)
    real, intent(inout) :: num_conc(n_mode)
    real, intent(in) :: diam(n_mode)
    real, intent(in) :: temp, pres, dt
    
    real :: coag_coeff
    integer :: i, j
    
    ! Simplified Brownian coagulation
    do i = 1, n_mode
      do j = i, n_mode
        coag_coeff = 1.0e-15 * sqrt(temp) / pres * &
                     (diam(i) + diam(j))**2
        
        num_conc(i) = num_conc(i) - coag_coeff * num_conc(i) * num_conc(j) * dt
        
        if (j < n_mode) then
          num_conc(j+1) = num_conc(j+1) + 0.5 * coag_coeff * num_conc(i) * num_conc(j) * dt
        end if
      end do
    end do
    
  end subroutine coagulation_kernel

end module aero_kernel_cpu
