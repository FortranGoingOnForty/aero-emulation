#!/bin/csh -f
# ==================================================================
# CMAQ v5.5 Optimized Run Script - 30-Rank Configuration
# ==================================================================
# This script incorporates all tested configurations and optimizations
# discovered during extensive benchmarking on 1 GbE fabric.
# 
# Key finding: 30 MPI ranks avoids the power-of-2 I/O synchronization
# bug that causes BEIS_SOILOUT failures at 23:55:00 simulation time.
# ==================================================================

#SBATCH --job-name=cctm_30r6            # Job identifier
#SBATCH --nodes=2                       # Node count                (tested: 1,2,4)
#SBATCH --ntasks=32                     # Total MPI ranks           (tested: 16,28,30,32,64)
#SBATCH --ntasks-per-node=16            # Ranks per node            (tested: 8,14,15,16,32)
#SBATCH --cpus-per-task=1               # CPUs per rank             (tested: 1,2,4,8 for hybrid)
#SBATCH --hint=nomultithread            # Disable hyperthreading
#SBATCH --distribution=block:cyclic     # MPI distribution          (tested: block:block, block:cyclic, cyclic:cyclic)
#SBATCH --output=cmaq-%j.out            # Standard output file
#SBATCH --error=cmaq-%j.err             # Standard error file
#SBATCH --time=01:00:00                 # Wall time limit
#SBATCH --exclusive                     # Exclusive node access
#SBATCH --mem=0                         # Use all available memory
#SBATCH --export=ALL                    # Export environment to compute nodes

# ==================================================================
# OpenMP Configuration (for hybrid MPI+OpenMP tests)
# ==================================================================
setenv OMP_NUM_THREADS 1                # Pure MPI                  (tested: 1,2,4,8)
#setenv OMP_PLACES cores                # Thread placement          (tested: cores,sockets,threads)
#setenv OMP_PROC_BIND close             # Thread binding            (tested: close,spread,master)
#setenv OMP_STACKSIZE 256M              # Thread stack size for hybrid runs

echo "=== CMAQ Run Started at `date` ==="
echo "=== Configuration: 30 ranks (5×6), 2 nodes, pure MPI ==="

# ==================================================================
# Library Path Configuration
# ==================================================================
setenv CMAQ_LIB   /nfs/home/wolffemf/cmaq_build/libs
setenv HDF5_DIR   /nfs/home/wolffemf/cmaq_build/libs/hdf5

# Fix library paths for NetCDF-Fortran and HDF5
setenv LD_LIBRARY_PATH ${CMAQ_LIB}/netcdff/lib:${LD_LIBRARY_PATH}
setenv LD_LIBRARY_PATH ${HDF5_DIR}/lib:${LD_LIBRARY_PATH}

# Additional library paths for alternative configurations
#setenv LD_LIBRARY_PATH ${CMAQ_LIB}/netcdf/lib:${LD_LIBRARY_PATH}
#setenv LD_LIBRARY_PATH ${CMAQ_LIB}/pnetcdf/lib:${LD_LIBRARY_PATH}

echo "CMAQ_LIB: $CMAQ_LIB"
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"

# ==================================================================
# CMAQ Environment Setup
# ==================================================================
echo 'Start Model Run At ' `date`

setenv CTM_DIAG_LVL 0                  # Diagnostic level (0=minimal, 1=verbose)

if ( ! $?compiler ) then
  setenv compiler gcc
endif
if ( ! $?compilerVrsn ) then
  setenv compilerVrsn Empty
endif

# Source the config_cmaq file
cd ../..
source ./config_cmaq.csh $compiler $compilerVrsn
setenv compilerString gcc
cd CCTM/scripts

# Re-export critical environment variables
setenv TMPDIR      /scratch/wolffemf/cmaq_data/tmp
setenv CMAQ_HOME   /nfs/home/wolffemf/cmaq_build/CMAQ_Project
setenv CMAQ_DATA   /scratch/wolffemf/cmaq_data
setenv CMAQ_LIB    /nfs/home/wolffemf/cmaq_build/libs
setenv compiler    gcc
setenv compilerVrsn 8.5.0

mkdir -p $TMPDIR

# ==================================================================
# Model Configuration
# ==================================================================
set VRSN      = v55                   # Code Version
set PROC      = mpi                   # Parallelization (serial or mpi)
set MECH      = cb6r5_ae7_aq          # Chemical mechanism
set DEP       = m3dry                 # Deposition scheme (m3dry or stage)
set APPL      = Bench_2018_12NE3_${MECH}_${DEP}

setenv RUNID  ${VRSN}_${compilerString}_${APPL}

# Set build and executable paths
set BLD       = ${CMAQ_HOME}/CCTM/scripts/BLD_CCTM_${VRSN}_${compilerString}_${MECH}_${DEP}
set EXEC      = CCTM_${VRSN}.exe

# Working directories
setenv WORKDIR ${CMAQ_HOME}/CCTM/scripts
setenv OUTDIR  ${CMAQ_DATA}/output_CCTM_${RUNID}
setenv INPDIR  /scratch/wolffemf/cmaq_data/CMAQv5.4_2018_12NE3_Benchmark_2Day_Input/2018_12NE3
setenv LOGDIR  ${OUTDIR}/LOGS
setenv NMLpath ${BLD}

echo ""
echo "Working Directory: $WORKDIR"
echo "Build Directory:   $BLD"
echo "Output Directory:  $OUTDIR"
echo "Log Directory:     $LOGDIR"
echo "Executable:        $EXEC"

# Verify executable dependencies
echo "Checking library dependencies:"
ldd $BLD/$EXEC | grep -E "(netcdff|hdf5)" || echo "WARNING: Missing libraries"

# ==================================================================
# Simulation Time Configuration
# ==================================================================
setenv NEW_START TRUE                  # FALSE for restart runs
set START_DATE = "2018-07-01"          # Start date
set END_DATE   = "2018-07-02"          # End date (2-day benchmark)

set STTIME     = 000000                # Start time HHMMSS
set NSTEPS     = 240000                # Duration HHMMSS (24 hours)
set TSTEP      = 010000                # Output timestep HHMMSS (5 minute)

# ==================================================================
# Domain Decomposition Configuration
# ==================================================================
# OPTIMAL: 30 ranks (5×6) - avoids power-of-2 synchronization bug
# @ NPCOL = 5; @ NPROW = 6               # 30 ranks total

# Alternative decompositions tested:
#@ NPCOL = 3; @ NPROW = 10             # 30 ranks (3×10) - also works
#@ NPCOL = 7; @ NPROW = 4              # 28 ranks - FAILS with BEIS_SOILOUT
@ NPCOL = 8; @ NPROW = 4              # 32 ranks - FAILS with BEIS_SOILOUT
#@ NPCOL = 4; @ NPROW = 8              # 32 ranks - FAILS (tall domains slower)
#@ NPCOL = 16; @ NPROW = 2             # 32 ranks - FAILS (extreme aspect ratio)
#@ NPCOL = 2; @ NPROW = 16             # 32 ranks - FAILS (extreme aspect ratio)
#@ NPCOL = 8; @ NPROW = 8              # 64 ranks - FAILS at 0:55 (network bound)
#@ NPCOL = 16; @ NPROW = 4             # 64 ranks - FAILS at 0:55 (CLDPROC crash)

@ NPROCS = $NPCOL * $NPROW
setenv NPCOL_NPROW "$NPCOL $NPROW"

# ==================================================================
# MPI Transport and Collective Algorithm Configuration
# ==================================================================

# Force ob1 transport and pipeline broadcast; disable UCX entirely
setenv OMPI_MCA_pml ob1                     # use ob1 PML
setenv OMPI_MCA_btl ^ucx                    # disable UCX BTL
setenv OMPI_MCA_btl_tcp_if_exclude "lo,docker0"  # Exclude problematic interfaces
# setenv OMPI_MCA_osc ^ucx                    # disable UCX osc
# setenv OMPI_MCA_mtl ^ucx                    # disable UCX MTL
setenv OMPI_MCA_coll_hcoll_enable 0         # disable HCOLL collectives
setenv OMPI_MCA_mpi_yield_when_idle 1       # yield CPU when idle
setenv OMPI_MCA_coll_tuned_bcast_algorithm 6 # pipeline broadcast

# Harden PMIx/server perms for stability
setenv PMIX_MCA_gds hash                     # use hash gds
setenv OMPI_MCA_pmix_server_tmpdir_base /scratch/${USER}/pmix_tmp
if ( ! -d /scratch/${USER}/pmix_tmp ) mkdir -p /scratch/${USER}/pmix_tmp

# Alternative transport configurations tested:
#
# Explicit BTL selection (can fail if components not available):
#setenv OMPI_MCA_btl "tcp,self,vader"             # OpenMPI 3.x+ (vader replaces sm)
#setenv OMPI_MCA_btl "tcp,self,sm"                # OpenMPI 2.x
#
# For OpenMPI 2.x (uses 'sm' for shared memory):
#setenv OMPI_MCA_btl "tcp,self,sm"
#
# UCX Transport (slower on 1GbE):
#setenv OMPI_MCA_pml ucx
#setenv OMPI_MCA_osc ucx
#setenv UCX_TLS "tcp,self,sm"                     # Minimal UCX
#setenv UCX_NET_DEVICES "all"
#setenv UCX_ZCOPY_THRESH 0                        # Disable zero-copy
#setenv UCX_RNDV_THRESH 0                         # Disable rendezvous
#
# UCX with tuning (still slower):
#setenv UCX_TLS "rc,ud,tcp,self,sm"
#setenv UCX_RC_VERBS_TX_QUEUE_LEN 128
#setenv UCX_UD_VERBS_TX_QUEUE_LEN 128
#setenv UCX_TCP_NODELAY 1
#setenv UCX_TCP_SNDBUF 2097152                    # 2MB send buffer
#setenv UCX_TCP_RCVBUF 2097152                    # 2MB receive buffer

# TCP Buffer tuning (minimal impact):
#setenv OMPI_MCA_btl_tcp_eager_limit 131072       # 128KB eager limit
#setenv OMPI_MCA_btl_tcp_sndbuf 2097152           # 2MB send buffer
#setenv OMPI_MCA_btl_tcp_rcvbuf 2097152           # 2MB receive buffer
#setenv OMPI_MCA_btl_tcp_rdma_pipeline_send_length 131072

# Alternative collective algorithms tested:
#setenv OMPI_MCA_coll_tuned_bcast_algorithm 4     # Split binary - FAILS
#setenv OMPI_MCA_coll_tuned_bcast_algorithm 5     # Binary tree - CRASHES at 0:55
#setenv OMPI_MCA_coll_tuned_bcast_algorithm 6     # Basic linear (default)
#setenv OMPI_MCA_coll_tuned_bcast_algorithm 7     # Knomial - FAILS

# Additional MPI tuning parameters:
#setenv OMPI_MCA_mpool_sm_min_size 134217728      # 128MB shared memory pool
#setenv OMPI_MCA_btl_sm_free_list_max 1024
#setenv OMPI_MCA_btl_sm_max_send_size 262144      # 256KB max message

# ==================================================================
# Hybrid MPI+OpenMP Configurations (all slower than pure MPI)
# ==================================================================
# Configuration A: 8 MPI × 4 OpenMP threads (best hybrid, still 2.8× slower)
#@ NPCOL = 4; @ NPROW = 2; @ NPROCS = 8
#setenv OMP_NUM_THREADS 4
#setenv OMP_PLACES sockets
#setenv OMP_PROC_BIND close
#
# Configuration B: 16 MPI × 2 OpenMP threads (4× slower)
#@ NPCOL = 4; @ NPROW = 4; @ NPROCS = 16
#setenv OMP_NUM_THREADS 2
#setenv OMP_PLACES cores
#setenv OMP_PROC_BIND spread
#
# Configuration C: 32 MPI × 2 OpenMP threads (failed to complete)
#@ NPCOL = 8; @ NPROW = 4; @ NPROCS = 32
#setenv OMP_NUM_THREADS 2
#
# Configuration D: Over-subscribed 64 MPI × 8 OpenMP (5.4× slower)
#@ NPCOL = 8; @ NPROW = 8; @ NPROCS = 64
#setenv OMP_NUM_THREADS 8

# ==================================================================
# Build Identification
# ==================================================================
if ( ! -e ${BLD}/CCTM_${VRSN}.cfg ) then
   set SHAID = ""
else
   set SHAID = `grep "sha_ID" ${BLD}/CCTM_${VRSN}.cfg | cut -c 13-22`
   if ( $SHAID == not_a_repo ) then
     set SHAID = ""
   else
     set SHAID = "_sha="$SHAID
   endif
endif
setenv EXECUTION_ID "CMAQ_CCTM${VRSN}${SHAID}_`id -u -n`_`date -u +%Y%m%d_%H%M%S_%N`"
echo ""
echo "---CMAQ EXECUTION ID: $EXECUTION_ID ---"

# ==================================================================
# Output Control
# ==================================================================
set CLOBBER_DATA = TRUE                # Delete existing output files

if (! -e $LOGDIR ) then
  mkdir -p $LOGDIR
endif

setenv PRINT_PROC_TIME Y               # Print subprocess timing
setenv STDOUT T                        # Redirect stdout properly

# ==================================================================
# Grid Configuration
# ==================================================================
setenv GRID_NAME 2018_12NE3
setenv GRIDDESC $INPDIR/GRIDDESC

# Extract grid dimensions
set NZ = 35
set NX = `grep -A 1 ${GRID_NAME} ${GRIDDESC} | tail -1 | sed 's/  */ /g' | cut -d' ' -f6`
set NY = `grep -A 1 ${GRID_NAME} ${GRIDDESC} | tail -1 | sed 's/  */ /g' | cut -d' ' -f7`
set NCELLS = `echo "${NX} * ${NY} * ${NZ}" | bc -l`

# ==================================================================
# Output Species Configuration
# ==================================================================
setenv AVG_CONC_SPCS "ALL"             # Write all species to ACONC
setenv ACONC_BLEV_ELEV " 1 1"          # Surface layer only for ACONC
setenv AVG_FILE_ENDTIME N              # Use default timestamps

# ==================================================================
# Numerical Solver Configuration
# ==================================================================
setenv CTM_MAXSYNC 300                 # Max sync timestep (seconds)
setenv CTM_MINSYNC 60                  # Min sync timestep (seconds)
setenv SIGMA_SYNC_TOP 0.7              # Sigma level for sync determination
setenv CTM_ADV_CFL 0.95                # Maximum CFL number

# Alternative sync parameters tested:
#setenv CTM_MAXSYNC 600                # Doubled - no improvement
#setenv ADV_HDIV_LIM 0.95              # Horizontal divergence limit
#setenv RB_ATOL 1.0E-09                # Solver tolerance

# ==================================================================
# Science Options
# ==================================================================
setenv CTM_OCEAN_CHEM Y                # Ocean chemistry
setenv CTM_WB_DUST N                   # Windblown dust
setenv CTM_LTNG_NO N                   # Lightning NOx
setenv KZMIN Y                         # Minimum Kz
setenv PX_VERSION Y                    # WRF PX LSM
setenv CLM_VERSION N                   # WRF CLM LSM
setenv NOAH_VERSION N                  # WRF NOAH LSM
setenv CTM_ABFLUX Y                    # Bidirectional NH3
setenv CTM_BIDI_FERT_NH3 T             # Fertilizer NH3 adjustment
setenv CTM_HGBIDI N                    # Mercury bidi
setenv CTM_SFC_HONO Y                  # Surface HONO
setenv CTM_GRAV_SETL Y                 # Gravitational settling
setenv CTM_PVO3 N                      # Potential vorticity O3

setenv CTM_BIOGEMIS_BE Y               # BEIS biogenic emissions
setenv CTM_BIOGEMIS_MG N               # MEGAN biogenic emissions
setenv BDSNP_MEGAN N                   # BDSNP soil NO

# Testing configurations:
#setenv CTM_BIOGEMIS_BE N              # Disable BEIS (bypasses SOILOUT bug)

setenv AEROSOL_OPTICS 3                # Aerosol optics method
setenv CTM_MOSAIC N                    # Landuse-specific deposition
setenv CTM_STAGE_P22 N                 # Pleim 2022 deposition
setenv CTM_STAGE_E20 Y                 # Emerson 2020 deposition
setenv CTM_STAGE_S22 N                 # Shu 2022 deposition

setenv IC_AERO_M2WET F                 # Dry aerosol ICs
setenv BC_AERO_M2WET F                 # Dry aerosol BCs
setenv IC_AERO_M2USE F                 # Don't use IC aerosol surface area
setenv BC_AERO_M2USE F                 # Don't use BC aerosol surface area

# ==================================================================
# Vertical Extraction
# ==================================================================
setenv VERTEXT N
setenv VERTEXT_COORD_PATH ${WORKDIR}/lonlat.csv

# ==================================================================
# I/O Controls
# ==================================================================
setenv IOAPI_LOG_WRITE F               # Minimal I/O API logging
setenv FL_ERR_STOP N                   # Continue on file inconsistencies
setenv PROMPTFLAG F                    # No interactive prompts
setenv IOAPI_OFFSET_64 YES             # Support large files
setenv IOAPI_CHECK_HEADERS N           # Skip header checks
setenv CTM_EMISCHK N                   # Don't abort on missing surrogates

# ==================================================================
# Diagnostic Output Flags
# ==================================================================
setenv CTM_CKSUM Y                     # Checksum report
setenv CLD_DIAG N                      # Cloud diagnostics
setenv CTM_PHOTDIAG N                  # Photolysis diagnostics
setenv NLAYS_PHOTDIAG "1"              # Photolysis layers
setenv CTM_SSEMDIAG N                  # Sea spray diagnostics
setenv CTM_DUSTEM_DIAG N               # Dust emission diagnostics
setenv CTM_DEPV_FILE N                 # Deposition velocity file
setenv VDIFF_DIAG_FILE N               # Vertical diffusion diagnostics
setenv LTNGDIAG N                      # Lightning diagnostics
setenv B3GTS_DIAG N                    # BEIS diagnostics
setenv CTM_WVEL Y                      # Save vertical velocity

# ==================================================================
# Input Directories and Filenames
# ==================================================================
set ICpath    = $INPDIR/icbc
set BCpath    = $INPDIR/icbc
set EMISpath  = $INPDIR/emis
set IN_PTpath = $INPDIR/emis
set IN_LTpath = $INPDIR/lightning
set METpath   = $INPDIR/met/mcipv5.4
set OMIpath   = $BLD
set EPICpath  = $INPDIR/epic
set SZpath    = $INPDIR/surface

# ==================================================================
# Begin Loop Through Simulation Days
# ==================================================================
set rtarray = ""

set TODAYG = ${START_DATE}
set TODAYJ = `date -ud "${START_DATE}" +%Y%j`
set START_DAY = ${TODAYJ} 
set STOP_DAY = `date -ud "${END_DATE}" +%Y%j`
set NDAYS = 0

while ($TODAYJ <= $STOP_DAY )
  
  set NDAYS = `echo "${NDAYS} + 1" | bc -l`

  # Retrieve Calendar day Information
  set YYYYMMDD = `date -ud "${TODAYG}" +%Y%m%d`
  set YYYYMM = `date -ud "${TODAYG}" +%Y%m`
  set YYMMDD = `date -ud "${TODAYG}" +%y%m%d`
  set MM = `date -ud "${TODAYG}" +%m`
  set YYYYJJJ = $TODAYJ

  # Calculate Yesterday's Date
  set YESTERDAY = `date -ud "${TODAYG}-1days" +%Y%m%d`

  # =====================================================================
  # Set Output String and Propagate Model Configuration Documentation
  # =====================================================================
  echo ""
  echo "Set up input and output files for Day ${TODAYG}."

  # set output file name extensions
  setenv CTM_APPL ${RUNID}_${YYYYMMDD} 
  
  # Copy Model Configuration To Output Folder
  if ( ! -d "$OUTDIR" ) mkdir -p $OUTDIR
  cp ${BLD}/CCTM_${VRSN}.cfg $OUTDIR/CCTM_${CTM_APPL}.cfg

  # =====================================================================
  # Input Files (Some are Day-Dependent)
  # =====================================================================

  # Initial conditions
  if ($NEW_START == true || $NEW_START == TRUE ) then
     setenv ICFILE CCTM_ICON_v54_${MECH}_12NE3_20180701.nc
     setenv INIT_MEDC_1 notused
  else
     set ICpath = $OUTDIR
     setenv ICFILE CCTM_CGRID_${RUNID}_${YESTERDAY}.nc
     setenv INIT_MEDC_1 $ICpath/CCTM_MEDIA_CONC_${RUNID}_${YESTERDAY}.nc
  endif

  # Boundary conditions
  set BCFILE = CCTM_BCON_v54_${MECH}_12NE3_${YYYYMMDD}.nc

  # Ozone column data
  set OMIfile   = OMI_1979_to_2019.dat

  # Optics file
  set OPTfile = PHOT_OPTICS.dat

  # MCIP meteorology files 
  setenv GRID_BDY_2D $METpath/GRIDBDY2D_12NE3_${YYYYMMDD}.nc
  setenv GRID_CRO_2D $METpath/GRIDCRO2D_12NE3_${YYYYMMDD}.nc
  setenv GRID_CRO_3D $METpath/GRIDCRO3D_12NE3_${YYYYMMDD}.nc
  setenv GRID_DOT_2D $METpath/GRIDDOT2D_12NE3_${YYYYMMDD}.nc
  setenv MET_CRO_2D $METpath/METCRO2D_12NE3_${YYYYMMDD}.nc
  setenv MET_CRO_3D $METpath/METCRO3D_12NE3_${YYYYMMDD}.nc
  setenv MET_DOT_3D $METpath/METDOT3D_12NE3_${YYYYMMDD}.nc
  setenv MET_BDY_3D $METpath/METBDY3D_12NE3_${YYYYMMDD}.nc
  setenv LUFRAC_CRO $METpath/LUFRAC_CRO_12NE3_${YYYYMMDD}.nc

  # Control Files
  setenv DESID_CTRL_NML ${BLD}/CMAQ_Control_DESID.nml
  setenv DESID_CHEM_CTRL_NML ${BLD}/CMAQ_Control_DESID_${MECH}.nml
  setenv MISC_CTRL_NML ${BLD}/CMAQ_Control_Misc.nml
  setenv STAGECTRL_NML ${BLD}/CMAQ_Control_STAGE.nml
 
  # Spatial Masks For Emissions Scaling
  setenv CMAQ_MASKS $INPDIR/GRIDMASK_STATES_12NE3.nc

  # Gridded Emissions Files 
  setenv N_EMIS_GR 2
  set EMISfile  = emis_mole_all_${YYYYMMDD}_12NE3_nobeis_norwc_2018gc_cb6_18j.ncf
  setenv GR_EMIS_001 ${EMISpath}/merged_nobeis_norwc/${EMISfile}
  setenv GR_EMIS_LAB_001 GRIDDED_EMIS
  setenv GR_EM_SYM_DATE_001 F

  set EMISfile  = emis_mole_rwc_${YYYYMMDD}_12NE3_cmaq_cb6ae7_2018gc_cb6_18j.ncf
  setenv GR_EMIS_002 ${EMISpath}/rwc/${EMISfile}
  setenv GR_EMIS_LAB_002 GR_RES_FIRES
  setenv GR_EM_SYM_DATE_002 F

  # In-line point emissions configuration
  setenv N_EMIS_PT 10

  set STKCASEG = 12US1_2018gc_cb6_18j
  set STKCASEE = 12US1_cmaq_cb6ae7_2018gc_cb6_18j

  # Time-Independent Stack Parameters for Inline Point Sources
  setenv STK_GRPS_001 $IN_PTpath/ptnonipm/stack_groups_ptnonipm_${STKCASEG}.ncf
  setenv STK_GRPS_002 $IN_PTpath/ptegu/stack_groups_ptegu_${STKCASEG}.ncf
  setenv STK_GRPS_003 $IN_PTpath/othpt/stack_groups_othpt_${STKCASEG}.ncf
  setenv STK_GRPS_004 $IN_PTpath/ptagfire/stack_groups_ptagfire_${YYYYMMDD}_${STKCASEG}.ncf
  setenv STK_GRPS_005 $IN_PTpath/ptfire-rx/stack_groups_ptfire-rx_${YYYYMMDD}_${STKCASEG}.ncf
  setenv STK_GRPS_006 $IN_PTpath/ptfire-wild/stack_groups_ptfire-wild_${YYYYMMDD}_${STKCASEG}.ncf
  setenv STK_GRPS_007 $IN_PTpath/ptfire_othna/stack_groups_ptfire_othna_${YYYYMMDD}_${STKCASEG}.ncf
  setenv STK_GRPS_008 $IN_PTpath/pt_oilgas/stack_groups_pt_oilgas_${STKCASEG}.ncf
  setenv STK_GRPS_009 $IN_PTpath/cmv_c3_12/stack_groups_cmv_c3_12_${STKCASEG}.ncf
  setenv STK_GRPS_010 $IN_PTpath/cmv_c1c2_12/stack_groups_cmv_c1c2_12_${STKCASEG}.ncf

  # Emission Rates for Inline Point Sources
  setenv STK_EMIS_001 $IN_PTpath/ptnonipm/inln_mole_ptnonipm_${YYYYMMDD}_${STKCASEE}.ncf
  setenv STK_EMIS_002 $IN_PTpath/ptegu/inln_mole_ptegu_${YYYYMMDD}_${STKCASEE}.ncf
  setenv STK_EMIS_003 $IN_PTpath/othpt/inln_mole_othpt_${YYYYMMDD}_${STKCASEE}.ncf
  setenv STK_EMIS_004 $IN_PTpath/ptagfire/inln_mole_ptagfire_${YYYYMMDD}_${STKCASEE}.ncf
  setenv STK_EMIS_005 $IN_PTpath/ptfire-rx/inln_mole_ptfire-rx_${YYYYMMDD}_${STKCASEE}.ncf
  setenv STK_EMIS_006 $IN_PTpath/ptfire-wild/inln_mole_ptfire-wild_${YYYYMMDD}_${STKCASEE}.ncf
  setenv STK_EMIS_007 $IN_PTpath/ptfire_othna/inln_mole_ptfire_othna_${YYYYMMDD}_${STKCASEE}.ncf
  setenv STK_EMIS_008 $IN_PTpath/pt_oilgas/inln_mole_pt_oilgas_${YYYYMMDD}_${STKCASEE}.ncf
  setenv STK_EMIS_009 $IN_PTpath/cmv_c3_12/inln_mole_cmv_c3_12_${YYYYMMDD}_${STKCASEE}.ncf
  setenv STK_EMIS_010 $IN_PTpath/cmv_c1c2_12/inln_mole_cmv_c1c2_12_${YYYYMMDD}_${STKCASEE}.ncf

  # Label Each Emissions Stream
  setenv STK_EMIS_LAB_001 PT_NONEGU
  setenv STK_EMIS_LAB_002 PT_EGU
  setenv STK_EMIS_LAB_003 PT_OTHER
  setenv STK_EMIS_LAB_004 PT_AGFIRES
  setenv STK_EMIS_LAB_005 PT_RXFIRES
  setenv STK_EMIS_LAB_006 PT_WILDFIRES
  setenv STK_EMIS_LAB_007 PT_OTHFIRES
  setenv STK_EMIS_LAB_008 PT_OILGAS
  setenv STK_EMIS_LAB_009 PT_CMV_C3
  setenv STK_EMIS_LAB_010 PT_CMV_C1C2

  # Allow CMAQ to Use Point Source files with dates that do not match
  setenv STK_EM_SYM_DATE_001 F
  setenv STK_EM_SYM_DATE_002 F
  setenv STK_EM_SYM_DATE_003 F
  setenv STK_EM_SYM_DATE_004 F
  setenv STK_EM_SYM_DATE_005 F
  setenv STK_EM_SYM_DATE_006 F
  setenv STK_EM_SYM_DATE_007 F
  setenv STK_EM_SYM_DATE_008 F

  # Lightning NOx configuration
  if ( $CTM_LTNG_NO == 'Y' ) then
     setenv LTNGNO "InLine"
     setenv USE_NLDN  Y
     if ( $USE_NLDN == Y ) then
        setenv NLDN_STRIKES ${IN_LTpath}/NLDN_12km_60min_${YYYYMMDD}.ioapi
     endif
     setenv LTNGPARMS_FILE ${IN_LTpath}/LTNG_AllParms_12NE3.nc
  endif

  # In-line biogenic emissions configuration
  if ( $CTM_BIOGEMIS_BE == 'Y' ) then
     set IN_BEISpath = ${INPDIR}/surface
     setenv GSPRO          $BLD/gspro_biogenics.txt
     setenv BEIS_NORM_EMIS $IN_BEISpath/beis4_beld6_norm_emis.12NE3.nc
     setenv BEIS_SOILINP        $OUTDIR/CCTM_BSOILOUT_${RUNID}_${YESTERDAY}.nc
  endif
  if ( $CTM_BIOGEMIS_MG == 'Y' ) then
    setenv MEGAN_SOILINP    $OUTDIR/CCTM_MSOILOUT_${RUNID}_${YESTERDAY}.nc
    setenv MEGAN_CTS $SZpath/megan3.2/CT3_CONUS.ncf
    setenv MEGAN_EFS $SZpath/megan3.2/EFMAPS_CONUS.ncf
    setenv MEGAN_LDF $SZpath/megan3.2/LDF_CONUS.ncf
    if ($BDSNP_MEGAN == 'Y') then
       setenv BDSNPINP    $OUTDIR/CCTM_BDSNPOUT_${RUNID}_${YESTERDAY}.nc
       setenv BDSNP_FFILE $SZpath/megan3.2/FERT_tceq_12km.ncf
       setenv BDSNP_NFILE $SZpath/megan3.2/NDEP_tceq_12km.ncf
       setenv BDSNP_LFILE $SZpath/megan3.2/LANDTYPE_tceq_12km.ncf
       setenv BDSNP_AFILE $SZpath/megan3.2/ARID_tceq_12km.ncf
       setenv BDSNP_NAFILE $SZpath/megan3.2/NONARID_tceq_12km.ncf
    endif
  endif

  # In-line sea spray emissions configuration
  setenv OCEAN_1 $SZpath/OCEAN_${MM}_L3m_MC_CHL_chlor_a_12NE3.nc

  # Bidirectional ammonia configuration
  if ( $CTM_ABFLUX == 'Y' ) then
     setenv E2C_SOIL ${EPICpath}/2018r1_EPIC0509_12NE3_soil.nc
     setenv E2C_CHEM ${EPICpath}/2018r1_EPIC0509_12NE3_time${YYYYMMDD}.nc
     setenv E2C_CHEM_YEST ${EPICpath}/2018r1_EPIC0509_12NE3_time${YESTERDAY}.nc
     setenv E2C_LU ${EPICpath}/beld4_12NE3_2011.nc
  endif

  # Inline Process Analysis 
  setenv CTM_PROCAN N
  if ( $?CTM_PROCAN ) then
     if ( $CTM_PROCAN == 'Y' || $CTM_PROCAN == 'T' ) then
        setenv PACM_INFILE ${NMLpath}/pa_${MECH}.ctl
        setenv PACM_REPORT $OUTDIR/"PA_REPORT".${YYYYMMDD}
     endif
  endif

  # Integrated Source Apportionment Method (ISAM) Options
  setenv CTM_ISAM N
  if ( $?CTM_ISAM ) then
     if ( $CTM_ISAM == 'Y' || $CTM_ISAM == 'T' ) then
        setenv SA_IOLIST ${WORKDIR}/isam_control.2018_12NE3.txt
        setenv ISAM_BLEV_ELEV " 1 1"
        setenv AISAM_BLEV_ELEV " 1 1"

        if ($NEW_START == true || $NEW_START == TRUE ) then
           setenv ISAM_NEW_START Y
           setenv ISAM_PREVDAY
        else
           setenv ISAM_NEW_START N
           setenv ISAM_PREVDAY "$OUTDIR/CCTM_SA_CGRID_${RUNID}_${YESTERDAY}.nc"
        endif

        setenv SA_ACONC_1      "$OUTDIR/CCTM_SA_ACONC_${CTM_APPL}.nc -v"
        setenv SA_CONC_1       "$OUTDIR/CCTM_SA_CONC_${CTM_APPL}.nc -v"
        setenv SA_DD_1         "$OUTDIR/CCTM_SA_DRYDEP_${CTM_APPL}.nc -v"
        setenv SA_WD_1         "$OUTDIR/CCTM_SA_WETDEP_${CTM_APPL}.nc -v"
        setenv SA_CGRID_1      "$OUTDIR/CCTM_SA_CGRID_${CTM_APPL}.nc -v"

        setenv ISAM_REGIONS $INPDIR/GRIDMASK_STATES_12NE3.nc

        setenv ISAM_O3_WEIGHTS 5
        setenv ISAM_NOX_CASE  2
        setenv ISAM_VOC_CASE  4
        setenv VOC_NOX_TRANS  0.35
     endif
  endif

  # Sulfur Tracking Model (STM)
  setenv STM_SO4TRACK N
  if ( $?STM_SO4TRACK ) then
     if ( $STM_SO4TRACK == 'Y' || $STM_SO4TRACK == 'T' ) then
        setenv STM_ADJSO4 Y
     endif
  endif

  # Decoupled Direct Method in 3D (DDM-3D) Options
  setenv CTM_DDM3D N

  set NPMAX    = 1
  setenv SEN_INPUT ${WORKDIR}/sensinput.2018_12NE3.dat

  setenv DDM3D_HIGH N

  if ($NEW_START == true || $NEW_START == TRUE ) then
     setenv DDM3D_RST N
     set S_ICpath =
     set S_ICfile =
  else
     setenv DDM3D_RST Y
     set S_ICpath = $OUTDIR
     set S_ICfile = CCTM_SENGRID_${RUNID}_${YESTERDAY}.nc
  endif

  setenv CTM_NPMAX       $NPMAX
  setenv CTM_SENS_1      "$OUTDIR/CCTM_SENGRID_${CTM_APPL}.nc -v"
  setenv A_SENS_1        "$OUTDIR/CCTM_ASENS_${CTM_APPL}.nc -v"
  setenv CTM_SWETDEP_1   "$OUTDIR/CCTM_SENWDEP_${CTM_APPL}.nc -v"
  setenv CTM_SDRYDEP_1   "$OUTDIR/CCTM_SENDDEP_${CTM_APPL}.nc -v"
  setenv INIT_SENS_1     $S_ICpath/$S_ICfile
 
  # =====================================================================
  # Output Files
  # =====================================================================

  # set output file names
  setenv S_CGRID         "$OUTDIR/CCTM_CGRID_${CTM_APPL}.nc"
  setenv CTM_CONC_1      "$OUTDIR/CCTM_CONC_${CTM_APPL}.nc -v"
  setenv A_CONC_1        "$OUTDIR/CCTM_ACONC_${CTM_APPL}.nc -v"
  setenv MEDIA_CONC      "$OUTDIR/CCTM_MEDIA_CONC_${CTM_APPL}.nc -v"
  setenv CTM_DRY_DEP_1   "$OUTDIR/CCTM_DRYDEP_${CTM_APPL}.nc -v"
  setenv CTM_DEPV_DIAG   "$OUTDIR/CCTM_DEPV_${CTM_APPL}.nc -v"
  setenv B3GTS_S         "$OUTDIR/CCTM_B3GTS_S_${CTM_APPL}.nc -v"
  setenv BEIS_SOILOUT    "$OUTDIR/CCTM_BSOILOUT_${CTM_APPL}.nc"
  setenv MEGAN_SOILOUT   "$OUTDIR/CCTM_MSOILOUT_${CTM_APPL}.nc"
  setenv BDSNPOUT        "$OUTDIR/CCTM_BDSNPOUT_${CTM_APPL}.nc"
  setenv CTM_WET_DEP_1   "$OUTDIR/CCTM_WETDEP1_${CTM_APPL}.nc -v"
  setenv CTM_WET_DEP_2   "$OUTDIR/CCTM_WETDEP2_${CTM_APPL}.nc -v"
  setenv CTM_ELMO_1      "$OUTDIR/CCTM_ELMO_${CTM_APPL}.nc -v"
  setenv CTM_AELMO_1     "$OUTDIR/CCTM_AELMO_${CTM_APPL}.nc -v"
  setenv CTM_RJ_1        "$OUTDIR/CCTM_PHOTDIAG1_${CTM_APPL}.nc -v"
  setenv CTM_RJ_2        "$OUTDIR/CCTM_PHOTDIAG2_${CTM_APPL}.nc -v"
  setenv CTM_RJ_3        "$OUTDIR/CCTM_PHOTDIAG3_${CTM_APPL}.nc -v"
  setenv CTM_SSEMIS_1    "$OUTDIR/CCTM_SSEMIS_${CTM_APPL}.nc -v"
  setenv CTM_DUST_EMIS_1 "$OUTDIR/CCTM_DUSTEMIS_${CTM_APPL}.nc -v"
  setenv CTM_BUDGET      "$OUTDIR/CCTM_BUDGET_${CTM_APPL}.txt -v"
  setenv CTM_IPR_1       "$OUTDIR/CCTM_PA_1_${CTM_APPL}.nc -v"
  setenv CTM_IPR_2       "$OUTDIR/CCTM_PA_2_${CTM_APPL}.nc -v"
  setenv CTM_IPR_3       "$OUTDIR/CCTM_PA_3_${CTM_APPL}.nc -v"
  setenv CTM_IRR_1       "$OUTDIR/CCTM_IRR_1_${CTM_APPL}.nc -v"
  setenv CTM_IRR_2       "$OUTDIR/CCTM_IRR_2_${CTM_APPL}.nc -v"
  setenv CTM_IRR_3       "$OUTDIR/CCTM_IRR_3_${CTM_APPL}.nc -v"
  setenv CTM_DRY_DEP_MOS "$OUTDIR/CCTM_DDMOS_${CTM_APPL}.nc -v"
  setenv CTM_DEPV_MOS    "$OUTDIR/CCTM_DEPVMOS_${CTM_APPL}.nc -v"
  setenv CTM_VDIFF_DIAG  "$OUTDIR/CCTM_VDIFF_DIAG_${CTM_APPL}.nc -v"
  setenv CTM_VSED_DIAG   "$OUTDIR/CCTM_VSED_DIAG_${CTM_APPL}.nc -v"
  setenv CTM_LTNGDIAG_1  "$OUTDIR/CCTM_LTNGHRLY_${CTM_APPL}.nc -v"
  setenv CTM_LTNGDIAG_2  "$OUTDIR/CCTM_LTNGCOL_${CTM_APPL}.nc -v"
  setenv CTM_VEXT_1      "$OUTDIR/CCTM_VEXT_${CTM_APPL}.nc -v"

  # set floor file (neg concs)
  setenv FLOOR_FILE ${OUTDIR}/FLOOR_${CTM_APPL}.txt

  # look for existing log files and output files
  ( ls CTM_LOG_???.${CTM_APPL} > buff.txt ) >& /dev/null
  ( ls ${LOGDIR}/CTM_LOG_???.${CTM_APPL} >> buff.txt ) >& /dev/null
  set log_test = `cat buff.txt`; rm -f buff.txt

  set OUT_FILES = (${FLOOR_FILE} ${S_CGRID} ${CTM_CONC_1} ${A_CONC_1} ${MEDIA_CONC}         \
             ${CTM_DRY_DEP_1} $CTM_DEPV_DIAG $B3GTS_S $MEGAN_SOILOUT $BEIS_SOILOUT $BDSNPOUT \
             $CTM_WET_DEP_1 $CTM_WET_DEP_2 $CTM_ELMO_1 $CTM_AELMO_1             \
             $CTM_RJ_1 $CTM_RJ_2 $CTM_RJ_3 $CTM_SSEMIS_1 $CTM_DUST_EMIS_1 $CTM_IPR_1 $CTM_IPR_2       \
             $CTM_IPR_3 $CTM_BUDGET $CTM_IRR_1 $CTM_IRR_2 $CTM_IRR_3 $CTM_DRY_DEP_MOS                 \
             $CTM_DEPV_MOS $CTM_VDIFF_DIAG $CTM_VSED_DIAG $CTM_LTNGDIAG_1 $CTM_LTNGDIAG_2 $CTM_VEXT_1 )
  if ( $?CTM_ISAM ) then
     if ( $CTM_ISAM == 'Y' || $CTM_ISAM == 'T' ) then
        set OUT_FILES = (${OUT_FILES} ${SA_ACONC_1} ${SA_CONC_1} ${SA_DD_1} ${SA_WD_1}      \
                         ${SA_CGRID_1} )
     endif
  endif
  if ( $?CTM_DDM3D ) then
     if ( $CTM_DDM3D == 'Y' || $CTM_DDM3D == 'T' ) then
        set OUT_FILES = (${OUT_FILES} ${CTM_SENS_1} ${A_SENS_1} ${CTM_SWETDEP_1} ${CTM_SDRYDEP_1} )
     endif
  endif
  set OUT_FILES = `echo $OUT_FILES | sed "s; -v;;g" | sed "s;MPI:;;g" `
  ( ls $OUT_FILES > buff.txt ) >& /dev/null
  set out_test = `cat buff.txt`; rm -f buff.txt
  
  # delete previous output if requested
  if ( $CLOBBER_DATA == true || $CLOBBER_DATA == TRUE  ) then
     echo 
     echo "Existing Logs and Output Files for Day ${TODAYG} Will Be Deleted"

     # remove previous log files
     foreach file ( ${log_test} )
        /bin/rm -f $file  
     end
 
     # remove previous output files
     foreach file ( ${out_test} )
        /bin/rm -f $file  
     end
     /bin/rm -f ${OUTDIR}/CCTM_DESID*${CTM_APPL}.nc

  else
     # error if previous log files exist
     if ( "$log_test" != "" ) then
       echo "*** Logs exist - run ABORTED ***"
       echo "*** To overide, set CLOBBER_DATA = TRUE in run_cctm.csh ***"
       echo "*** and these files will be automatically deleted. ***"
       exit 1
     endif
     
     # error if previous output files exist
     if ( "$out_test" != "" ) then
       echo "*** Output Files Exist - run will be ABORTED ***"
       foreach file ( $out_test )
          echo " cannot delete $file"
       end
       echo "*** To overide, set CLOBBER_DATA = TRUE in run_cctm.csh ***"
       echo "*** and these files will be automatically deleted. ***"
       exit 1
     endif
  endif

  # for the run control ...
  setenv CTM_STDATE      $YYYYJJJ
  setenv CTM_STTIME      $STTIME
  setenv CTM_RUNLEN      $NSTEPS
  setenv CTM_TSTEP       $TSTEP
  setenv INIT_CONC_1 $ICpath/$ICFILE
  setenv BNDY_CONC_1 $BCpath/$BCFILE
  setenv OMI $OMIpath/$OMIfile
  setenv MIE_TABLE $OUTDIR/mie_table_coeffs_${compilerString}.txt
  setenv OPTICS_DATA $OMIpath/$OPTfile
 
  # species defn & photolysis
  setenv gc_matrix_nml ${NMLpath}/GC_$MECH.nml
  setenv ae_matrix_nml ${NMLpath}/AE_$MECH.nml
  setenv nr_matrix_nml ${NMLpath}/NR_$MECH.nml
  setenv tr_matrix_nml ${NMLpath}/Species_Table_TR_0.nml
 
  # check for photolysis input data
  setenv CSQY_DATA ${NMLpath}/CSQY_DATA_$MECH

  if (! (-e $CSQY_DATA ) ) then
     echo " $CSQY_DATA  not found "
     exit 1
  endif
  if (! (-e $OPTICS_DATA ) ) then
     echo " $OPTICS_DATA  not found "
     exit 1
  endif

  # ===================================================================
  # Execution Portion
  # ===================================================================

  # Print attributes of the executable
  if ( $CTM_DIAG_LVL != 0 ) then
     ls -l $BLD/$EXEC
     size $BLD/$EXEC
     unlimit
     limit
  endif

  # Print Startup Dialogue Information to Standard Out
  echo 
  echo "CMAQ Processing of Day $YYYYMMDD Began at `date`"
  echo 

  # ===================================================================
  # MPI Execution Command
  # ===================================================================
  echo ""
  # echo "=== Launching CMAQ with 30 MPI ranks ==="
  echo "=== Using broadcast algorithm $OMPI_MCA_coll_tuned_bcast_algorithm ==="
  echo ""

  ( /usr/bin/time -p mpirun -np $NPROCS $BLD/$EXEC ) |& tee buff_${EXECUTION_ID}.txt

  # Alternative execution methods tested:
  #
  # srun with PMI2:
  #( /usr/bin/time -p srun --mpi=pmi2 --cpu-bind=cores -n $NPROCS $BLD/$EXEC ) |& tee buff_${EXECUTION_ID}.txt
  #
  # mpirun with process binding:
  #( /usr/bin/time -p mpirun -np $NPROCS \
  #    --bind-to core \
  #    --map-by socket \
  #    --report-bindings \
  #    $BLD/$EXEC ) |& tee buff_${EXECUTION_ID}.txt
  #
  # mpirun with verbose output for debugging:
  #( /usr/bin/time -p mpirun -np $NPROCS \
  #    --mca pml_base_verbose 10 \
  #    --mca btl_base_verbose 10 \
  #    --display-map \
  #    $BLD/$EXEC ) |& tee buff_${EXECUTION_ID}.txt

  # Harvest Timing Output so that it may be reported below
  set rtarray = "${rtarray} `tail -3 buff_${EXECUTION_ID}.txt | grep -Eo '[+-]?[0-9]+([.][0-9]+)?' | head -1` "
  rm -rf buff_${EXECUTION_ID}.txt

  # Abort script if abnormal termination
  if ( ! -e $OUTDIR/CCTM_CGRID_${CTM_APPL}.nc ) then
    echo ""
    echo "**************************************************************"
    echo "** Runscript Detected an Error: CGRID file was not written. **"
    echo "**   This indicates that CMAQ was interrupted or an issue   **"
    echo "**   exists with writing output. The runscript will now     **"
    echo "**   abort rather than proceeding to subsequent days.       **"
    echo "**************************************************************"
    break
  endif

  # Print Concluding Text
  echo 
  echo "CMAQ Processing of Day $YYYYMMDD Finished at `date`"
  echo
  echo "\\\\\=====\\\\\=====\\\\\=====\\\\\=====/////=====/////=====/////=====/////"
  echo

  # ===================================================================
  # Finalize Run for This Day and Loop to Next Day
  # ===================================================================

  # Save Log Files and Move on to Next Simulation Day
  mv CTM_LOG_???.${CTM_APPL} $LOGDIR
  if ( $CTM_DIAG_LVL != 0 ) then
    mv CTM_DIAG_???.${CTM_APPL} $LOGDIR
  endif

  # The next simulation day will, by definition, be a restart
  setenv NEW_START false

  # Increment both Gregorian and Julian Days
  set TODAYG = `date -ud "${TODAYG}+1days" +%Y-%m-%d`
  set TODAYJ = `date -ud "${TODAYG}" +%Y%j`

end  # Loop to the next Simulation Day

# ===================================================================
# Generate Timing Report
# ===================================================================
set RTMTOT = 0
foreach it ( `seq ${NDAYS}` )
    set rt = `echo ${rtarray} | cut -d' ' -f${it}`
    set RTMTOT = `echo "${RTMTOT} + ${rt}" | bc -l`
end

set RTMAVG = `echo "scale=2; ${RTMTOT} / ${NDAYS}" | bc -l`
set RTMTOT = `echo "scale=2; ${RTMTOT} / 1" | bc -l`

echo
echo "=================================="
echo "  ***** CMAQ TIMING REPORT *****"
echo "=================================="
echo "Start Day: ${START_DATE}"
echo "End Day:   ${END_DATE}"
echo "Number of Simulation Days: ${NDAYS}"
echo "Domain Name:               ${GRID_NAME}"
echo "Number of Grid Cells:      ${NCELLS}  (ROW x COL x LAY)"
echo "Number of Layers:          ${NZ}"
echo "Number of Processes:       ${NPROCS}"
echo "   All times are in seconds."
echo
echo "Num  Day        Wall Time"
set d = 0
set day = ${START_DATE}
foreach it ( `seq ${NDAYS}` )
    # Set the right day and format it
    set d = `echo "${d} + 1"  | bc -l`
    set n = `printf "%02d" ${d}`

    # Choose the correct time variables
    set rt = `echo ${rtarray} | cut -d' ' -f${it}`

    # Write out row of timing data
    echo "${n}   ${day}   ${rt}"

    # Increment day for next loop
    set day = `date -ud "${day}+1days" +%Y-%m-%d`
end
echo "     Total Time = ${RTMTOT}"
echo "      Avg. Time = ${RTMAVG}"

exit