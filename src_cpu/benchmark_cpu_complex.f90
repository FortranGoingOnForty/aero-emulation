! benchmark_cpu_complex.f90
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
  
  ! Get ncells from command line or use default
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
  
  ! Initialize
  do i = 1, ncells
    temp(i) = 298.15 + 10.0 * sin(real(i)/1000.0)
    pres(i) = 101325.0 * (1.0 - 0.1 * sin(real(i)/2000.0))
    rh(i) = 0.7 + 0.2 * cos(real(i)/1500.0)
    aerosol_mass(:,i) = (/0.1, 1.0, 10.0/)
    size_dist(:,i) = 1.0
  end do
  
  ! Warmup
  do step = 1, 10
    call aerosol_thermodynamics(temp, pres, rh, aerosol_mass, aerosol_water, ncells)
    call coagulation_sectional(size_dist, temp, pres, dt, ncells)
  end do
  
  ! Benchmark
  call cpu_time(t_start)
  
  do step = 1, nsteps
    call aerosol_thermodynamics(temp, pres, rh, aerosol_mass, aerosol_water, ncells)
    call coagulation_sectional(size_dist, temp, pres, dt, ncells)
  end do
  
  call cpu_time(t_end)
  
  print *, "CPU Time:", t_end - t_start, "seconds"
  print *, "Time per timestep:", (t_end - t_start) / real(nsteps), "seconds"
  print *, "Cells/second:", real(ncells * nsteps) / (t_end - t_start)
  
  ! Cleanup
  deallocate(temp, pres, rh, aerosol_mass, aerosol_water, size_dist)
  
end program benchmark_cpu_complex