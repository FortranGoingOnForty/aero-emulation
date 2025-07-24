! Benchmarking program for aerosol thermodynamics and coagulation sectional kernels on CPU.
! 
! This program tests the performance of aerosol thermodynamics and coagulation sectional kernels
! using synthetic input data. The number of computational cells can be specified as a command-line
! argument; otherwise, a default value is used.
!
! Inputs:
!   - Number of cells (optional command-line argument)
!
! Outputs:
!   - Timing information for kernel execution over multiple timesteps
!
! Workflow:
!   1. Parse command-line argument for number of cells.
!   2. Allocate and initialize arrays with synthetic data.
!   3. Perform warmup iterations to prime caches and JIT.
!   4. Measure execution time of kernels over specified timesteps.
!   5. Output timing results and clean up allocated memory.
! 
! Author: mfw
! Date: 2025.07
!
program benchmark_cpu_complex
  use aero_kernel_complex_cpu
  implicit none
  
  integer :: ncells, nsteps = 100
  real :: dt = 1.0
  real, allocatable :: temp(:), pres(:), rh(:)
  real, allocatable :: aerosol_mass(:,:), aerosol_water(:,:)
  real, allocatable :: size_dist(:,:)
  real :: t_start, t_end
  integer :: i, step, arg_count
  character(len=32) :: arg_str
  
  ! 
  ! Parse command-line arguments for number of cells.
  ! If no argument is provided, use default value.
  !
  arg_count = command_argument_count()
  if (arg_count >= 1) then
    call get_command_argument(1, arg_str)
    read(arg_str, *) ncells
  else
    ncells = 100000
  end if
  
  print *, "Testing with", ncells, "cells:"
  print *, "------------------------"
  
  ! Allocate arrays
  allocate(temp(ncells), pres(ncells), rh(ncells))
  allocate(aerosol_mass(n_mode, ncells))
  allocate(aerosol_water(n_mode, ncells))
  allocate(size_dist(n_size_bins, ncells))
  
  ! 
  ! Initialize synthetic initial conditions for temperature, pressure, relative humidity,
  ! aerosol mass, and size distribution arrays.
  !
  do i = 1, ncells
    temp(i) = 298.15 + 10.0 * sin(real(i)/1000.0)
    pres(i) = 101325.0 * (1.0 - 0.1 * sin(real(i)/2000.0))
    rh(i) = 0.7 + 0.2 * cos(real(i)/1500.0)
    aerosol_mass(:,i) = (/0.1, 1.0, 10.0/)
    size_dist(:,i) = 1.0
  end do
  
  ! 
  ! Warmup iterations to prime caches and JIT compilation if applicable.
  !
  do step = 1, 10
    call aerosol_thermodynamics(temp, pres, rh, aerosol_mass, aerosol_water, ncells)
    call coagulation_sectional(size_dist, temp, pres, dt, ncells)
  end do
  
  ! 
  ! Benchmark timing block: measure execution time over nsteps timesteps.
  !
  call cpu_time(t_start)
  
  do step = 1, nsteps
    call aerosol_thermodynamics(temp, pres, rh, aerosol_mass, aerosol_water, ncells)
    call coagulation_sectional(size_dist, temp, pres, dt, ncells)
  end do
  
  call cpu_time(t_end)
  
  print *, "CPU Time:", t_end - t_start, "seconds"
  print *, "Time per timestep:", (t_end - t_start) / real(nsteps), "seconds"
  print *, "Cells/second:", real(ncells * nsteps) / (t_end - t_start)
  
  ! 
  ! Cleanup allocated arrays to free memory.
  !
  deallocate(temp, pres, rh, aerosol_mass, aerosol_water, size_dist)
  
end program benchmark_cpu_complex