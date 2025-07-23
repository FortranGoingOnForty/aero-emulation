program aero_benchmark_cpu
  use aero_kernel_cpu
  implicit none
  
  integer, parameter :: ncells = 100000
  integer, parameter :: nsteps = 100
  
  ! Change to allocatable arrays to use heap instead of stack
  real, allocatable :: temp(:), pres(:), rh(:)
  real, allocatable :: aerosol_conc(:,:)
  real, allocatable :: aerosol_mass(:,:)
  real, allocatable :: num_conc(:,:)
  real, allocatable :: diam(:,:)
  
  real :: dt = 1.0  ! 1 second timestep
  real :: t_start, t_end
  integer :: i, step
  
  ! Allocate arrays
  print *, "Allocating arrays for ", ncells, " grid cells..."
  allocate(temp(ncells), pres(ncells), rh(ncells))
  allocate(aerosol_conc(n_aerospc, ncells))
  allocate(aerosol_mass(n_mode, ncells))
  allocate(num_conc(n_mode, ncells))
  allocate(diam(n_mode, ncells))
  
  ! Initialize with realistic values
  print *, "Initializing data..."
  
  do i = 1, ncells
    temp(i) = 298.15 + 10.0 * sin(real(i)/1000.0)
    pres(i) = 101325.0 * (1.0 - 0.1 * sin(real(i)/2000.0))
    rh(i) = 0.7 + 0.2 * cos(real(i)/1500.0)
    
    aerosol_conc(:,i) = 1.0
    aerosol_mass(:,i) = (/0.1, 1.0, 10.0/)
    num_conc(:,i) = (/1.0e6, 1.0e3, 1.0/)
    diam(:,i) = (/0.01, 0.1, 2.5/)
  end do
  
  print *, "Starting CPU benchmark..."
  call cpu_time(t_start)
  
  do step = 1, nsteps
    !$omp parallel do private(i) schedule(static)
    do i = 1, ncells
      call aerosol_mass_update(temp(i), pres(i), rh(i), dt, &
                               aerosol_conc(:,i), aerosol_mass(:,i))
      
      call coagulation_kernel(num_conc(:,i), diam(:,i), &
                              temp(i), pres(i), dt)
    end do
    !$omp end parallel do
  end do
  
  call cpu_time(t_end)
  
  print *, "CPU Time: ", t_end - t_start, " seconds"
  print *, "Time per timestep: ", (t_end - t_start) / nsteps, " seconds"
  print *, "Cells processed per second: ", real(ncells * nsteps) / (t_end - t_start)
  
  ! Output sample results
  print *, "Sample results (cell 1):"
  print *, "  Aerosol mass: ", aerosol_mass(:,1)
  print *, "  Number conc: ", num_conc(:,1)
  
  ! Deallocate
  deallocate(temp, pres, rh)
  deallocate(aerosol_conc, aerosol_mass, num_conc, diam)
  
end program aero_benchmark_cpu