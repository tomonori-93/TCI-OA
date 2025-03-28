MODULE obsope_tools
!=======================================================================
!
! [PURPOSE:] Observation operator tools
!
! [HISTORY:]
!   November 2014  Guo-Yuan Lien  created
!   .............  See git history for the following revisions
!   Added comments by Satoki Tsujino
!   06/27/2024 Satoki Tsujino    added height check for H08UV
!
!=======================================================================
!$USE OMP_LIB
  USE common
  USE common_mpi
  USE common_scale
  USE common_mpi_scale
  USE common_obs_scale
  use common_nml
!  use scale_process, only: &
!    PRC_myrank
!    MPI_COMM_d => LOCAL_COMM_WORLD
  USE common_obs_scale_H08VT
  USE common_obs_scale_H08VR
  use scale_grid_index, only: &
    KHALO, IHALO, JHALO
#ifdef H08
  use scale_grid, only: &
    DX, DY,    &
    BUFFER_DX, &
    BUFFER_DY
#endif

  IMPLICIT NONE
  PUBLIC

CONTAINS

!-----------------------------------------------------------------------
! Observation operator calculation (Checked by satoki)
!-----------------------------------------------------------------------
SUBROUTINE obsope_cal(obsda_return, nobs_extern)
  IMPLICIT NONE

  type(obs_da_value), optional, intent(out) :: obsda_return
  integer, optional, intent(in) :: nobs_extern

  type(obs_da_value) :: obsda

  integer :: it, im, iof, islot, ierr
  integer :: n, nn, nsub, nmod, n1, n2
  integer :: nm, ns, nt, nu  ! Add by satoki

  integer :: nobs     ! observation number processed in this subroutine
  integer :: nobs_all
  integer :: nobs_max_per_file
  integer :: nobs_max_per_file_sub
  integer :: slot_nobsg
  integer :: tmp_nobsg_H08vt, tmp_nobsd_H08vt  ! add by satoki
  integer :: tmp_nobsg_H08vr, tmp_nobsd_H08vr  ! add by satoki

  integer :: ip, ibufs
  integer, allocatable :: cntr(:), dspr(:)
  integer, allocatable :: cnts(:), dsps(:)
  integer, allocatable :: bsn(:,:), bsna(:,:), bsnext(:,:)
  integer :: islot_time_out, islot_domain_out

  integer, allocatable :: obrank_bufs(:)
  real(r_size), allocatable :: ri_bufs(:)
  real(r_size), allocatable :: rj_bufs(:)

  integer, allocatable :: obset_bufs(:)
  integer, allocatable :: obidx_bufs(:)

  integer :: slot_id(SLOT_START:SLOT_END)
  real(r_size) :: slot_lb(SLOT_START:SLOT_END)
  real(r_size) :: slot_ub(SLOT_START:SLOT_END)

  real(r_size), allocatable :: v3dg(:,:,:,:)
  real(r_size), allocatable :: v2dg(:,:,:)
  real(r_size), allocatable :: rigu(:)  ! rig for u grid (Add by satoki)
  real(r_size), allocatable :: rigv(:)  ! rig for v grid (Add by satoki)
  real(r_size), allocatable :: rjgu(:)  ! rjg for u grid (Add by satoki)
  real(r_size), allocatable :: rjgv(:)  ! rjg for v grid (Add by satoki)
  real(r_size) :: rig, rjg
  real(r_size) :: mpi_bcast_v_H08vt(7)  ! Temporary array for MPI_BCAST (Add by satoki)
  real(r_size) :: mpi_bcast_v_H08vr(7)  ! Temporary array for MPI_BCAST (Add by satoki)

  integer, allocatable :: qc_p(:)
#ifdef H08
  real(r_size), allocatable :: lev_p(:)
  real(r_size), allocatable :: val2_p(:)
#endif

  real(r_size) :: ril, rjl, rk, rkz

  character(filelenmax) :: obsdafile
  character(len=11) :: obsda_suffix = '.000000.dat'
  character(len=4) :: nstr
  character(len=timer_name_width) :: timer_str

#ifdef H08
! -- for Himawari-8 obs --
  INTEGER :: nallprof ! H08: Num of all profiles (entire domain) required by RTTOV
  INTEGER :: ns ! H08 obs count
  INTEGER :: nprof_H08   ! num of H08 obs
  REAL(r_size),ALLOCATABLE :: ri_H08(:),rj_H08(:)
  REAL(r_size),ALLOCATABLE :: lon_H08(:),lat_H08(:)
  REAL(r_size),ALLOCATABLE :: tmp_ri_H08(:),tmp_rj_H08(:)
  REAL(r_size),ALLOCATABLE :: tmp_lon_H08(:),tmp_lat_H08(:)

  REAL(r_size),ALLOCATABLE :: yobs_H08(:),plev_obs_H08(:)
  REAL(r_size),ALLOCATABLE :: yobs_H08_clr(:)
  INTEGER :: ch
  INTEGER,ALLOCATABLE :: qc_H08(:)

! -- Rejecting obs over the buffer regions. --
!
! bris: "ri" at the wetern end of the domain excluding buffer regions
! brie: "ri" at the eastern end of the domain excluding buffer regions
! bris: "rj" at the southern end of the domain excluding buffer regions
! bris: "rj" at the northern end of the domain excluding buffer regions
!
! e.g.,   ri:    ...bris...........brie...
!             buffer |  NOT buffer  | buffer
!
!
  REAL(r_size) :: bris, brie
  REAL(r_size) :: brjs, brje
#endif

  INTEGER :: proc, nobs_0
! -- for Himawari-8 VT/VR obs (by satoki) --
  INTEGER :: nsvt, nsvr
  INTEGER :: nallprofvt, nallprofvr
  INTEGER :: nprof_H08vt, nprof_H08vr ! num of H08vt/vr obs
  INTEGER,ALLOCATABLE :: tmp_obsdp_H08vt(:),tmp_obsgp_H08vt(:,:)
  INTEGER,ALLOCATABLE :: tmp_obsdp_H08vr(:),tmp_obsgp_H08vr(:,:)
  REAL(r_size),ALLOCATABLE :: ri_H08vt(:,:),rj_H08vt(:,:)
  REAL(r_size),ALLOCATABLE :: lon_H08vt(:,:),lat_H08vt(:,:)
  REAL(r_size),ALLOCATABLE :: lev_H08vt(:,:),lev2_H08vt(:,:),rad_H08vt(:,:)
  REAL(r_size),ALLOCATABLE :: ri_H08vr(:,:),rj_H08vr(:,:)
  REAL(r_size),ALLOCATABLE :: lon_H08vr(:,:),lat_H08vr(:,:)
  REAL(r_size),ALLOCATABLE :: lev_H08vr(:,:),lev2_H08vr(:,:),rad_H08vr(:,:)
!org  REAL(r_size),ALLOCATABLE :: tmp_ri_H08vt(:),tmp_rj_H08vt(:)
!org  REAL(r_size),ALLOCATABLE :: tmp_lon_H08vt(:),tmp_lat_H08vt(:)
!org  REAL(r_size),ALLOCATABLE :: tmp_lev_H08vt(:),tmp_lev2_H08vt(:),tmp_rad_H08vt(:)

  REAL(r_size),ALLOCATABLE :: yobs_H08vt(:,:), yobs_H08vr(:,:)
  INTEGER,ALLOCATABLE :: qc_H08vt(:,:), qc_H08vr(:,:)
  LOGICAL,ALLOCATABLE :: valid_H08vt(:,:), valid_H08vr(:,:)

! -- for TC vital assimilation --
!  INTEGER :: obs_set_TCX, obs_set_TCY, obs_set_TCP ! obs set
!  INTEGER :: obs_idx_TCX, obs_idx_TCY, obs_idx_TCP ! obs index
  INTEGER :: bTC_proc ! the process where the background TC is located.
! bTC: background TC in each subdomain
! bTC(1,:) : tcx (m), bTC(2,:): tcy (m), bTC(3,:): mslp (Pa)
  REAL(r_size),ALLOCATABLE :: bTC(:,:)
  REAL(r_size) :: bTC_mslp

!-------------------------------------------------------------------------------

  call mpi_timer('', 2)

#ifdef H08
!  call phys2ij(MSLP_TC_LON,MSLP_TC_LAT,MSLP_TC_rig,MSLP_TC_rjg)
  bris = real(BUFFER_DX/DX,r_size) + real(IHALO,r_size) 
  brjs = real(BUFFER_DY/DY,r_size) + real(JHALO,r_size)
  brie = (real(nlong+2*IHALO,r_size) - bris)
  brje = (real(nlatg+2*JHALO,r_size) - brjs)
#endif

!-------------------------------------------------------------------------------
! First scan of all observation data: Compute their horizontal location and time
!-------------------------------------------------------------------------------
  ! Comment by satoki 
  ! Checking max obs number in each type, and counting total observation number

  nobs_all = 0
  nobs_max_per_file = 0
  do iof = 1, OBS_IN_NUM
    if (obs(iof)%nobs > nobs_max_per_file) then
      nobs_max_per_file = obs(iof)%nobs
    end if
    if (OBSDA_RUN(iof)) then
      nobs_all = nobs_all + obs(iof)%nobs
    end if
  end do

!  obs_set_TCX = -1
!  obs_set_TCY = -1
!  obs_set_TCP = -1
!  obs_idx_TCX = -1
!  obs_idx_TCY = -1
!  obs_idx_TCP = -1

  ! Comment by satoki 
  ! Checking obs number per process, and allocating buffer arrays
  nobs_max_per_file_sub = (nobs_max_per_file - 1) / nprocs_a + 1
  allocate (obrank_bufs(nobs_max_per_file_sub))
  allocate (ri_bufs(nobs_max_per_file_sub))
  allocate (rj_bufs(nobs_max_per_file_sub))

  allocate (cntr(nprocs_a))
  allocate (dspr(nprocs_a))

  mpi_bcast_v_H08vt = 0.0  ! Add by satoki
  mpi_bcast_v_H08vr = 0.0  ! Add by satoki

  ! Use all processes to compute the basic obsevration information
  ! (locations in model grids and the subdomains they belong to)
  !-----------------------------------------------------------------------------

  do iof = 1, OBS_IN_NUM
    if (obs(iof)%nobs > 0) then ! Process basic obsevration information for all observations since this information is not saved in obsda files
                                ! when using separate observation operators; ignore the 'OBSDA_RUN' setting for this section
      nsub = obs(iof)%nobs / nprocs_a
      nmod = mod(obs(iof)%nobs, nprocs_a)
      do ip = 1, nmod
        cntr(ip) = nsub + 1
      end do
      do ip = nmod+1, nprocs_a
        cntr(ip) = nsub
      end do
      dspr(1) = 0
      do ip = 2, nprocs_a
        dspr(ip) = dspr(ip-1) + cntr(ip-1)
      end do

      obrank_bufs(:) = -1
!$OMP PARALLEL DO PRIVATE(ibufs,n) SCHEDULE(STATIC)
      do ibufs = 1, cntr(myrank_a+1)
        n = dspr(myrank_a+1) + ibufs
!        select case (obs(iof)%elm(n))
!        case (id_tclon_obs)
!          obs_set_TCX = iof
!          obs_idx_TCX = n
!          cycle
!        case (id_tclat_obs)
!          obs_set_TCY = iof
!          obs_idx_TCY = n
!          cycle
!        case (id_tcmip_obs)
!          obs_set_TCP = iof
!          obs_idx_TCP = n
!          cycle
!        end select

        ! Comment by satoki: determining obs global(ig,jg) <- obs(lon,lat)
        call phys2ij(obs(iof)%lon(n), obs(iof)%lat(n), ri_bufs(ibufs), rj_bufs(ibufs))
        ! Comment by satoki: determining obs rank number <- global(ig,jg)
        call rij_rank(ri_bufs(ibufs), rj_bufs(ibufs), obrank_bufs(ibufs))
      end do ! [ ibufs = 1, cntr(myrank_a+1) ]
!$OMP END PARALLEL DO

      call mpi_timer('obsope_cal:first_scan_cal:', 2, barrier=MPI_COMM_a)

      ! Comment by satoki: gathering obs information on rank, ig, jg from each process
      call MPI_ALLGATHERV(obrank_bufs, cntr(myrank_a+1), MPI_INTEGER, obs(iof)%rank, cntr, dspr, MPI_INTEGER, MPI_COMM_a, ierr)
      call MPI_ALLGATHERV(ri_bufs,     cntr(myrank_a+1), MPI_r_size,  obs(iof)%ri,   cntr, dspr, MPI_r_size,  MPI_COMM_a, ierr)
      call MPI_ALLGATHERV(rj_bufs,     cntr(myrank_a+1), MPI_r_size,  obs(iof)%rj,   cntr, dspr, MPI_r_size,  MPI_COMM_a, ierr)

      call mpi_timer('obsope_cal:first_scan_reduce:', 2)
    end if ! [ obs(iof)%nobs > 0 ]
  end do ! [ do iof = 1, OBS_IN_NUM ]

  deallocate (cntr, dspr)
  deallocate (obrank_bufs, ri_bufs, rj_bufs)

  ! Bucket sort of observation wrt. time slots and subdomains using the process rank 0
  !-----------------------------------------------------------------------------

  islot_time_out = SLOT_END + 1   ! slot = SLOT_END+1 for observation not in the assimilation time window
  islot_domain_out = SLOT_END + 2 ! slot = SLOT_END+2 for observation outside of the model domain

  allocate (bsn   (SLOT_START  :SLOT_END+2, 0:nprocs_d-1))
  allocate (bsna  (SLOT_START-1:SLOT_END+2, 0:nprocs_d-1))

  if (myrank_e == 0) then
    allocate ( obset_bufs(nobs_all) )
    allocate ( obidx_bufs(nobs_all) )
  end if

  if (myrank_a == 0) then
    allocate (bsnext(SLOT_START  :SLOT_END+2, 0:nprocs_d-1))
    bsn(:,:) = 0
    bsna(:,:) = 0
    bsnext(:,:) = 0

!$OMP PARALLEL PRIVATE(iof,n,islot)
    do iof = 1, OBS_IN_NUM
      if (OBSDA_RUN(iof) .and. obs(iof)%nobs > 0) then
!$OMP DO SCHEDULE(STATIC)
        do n = 1, obs(iof)%nobs
          if (obs(iof)%rank(n) == -1) then
            ! process the observations outside of the model domain in process rank 0
!$OMP ATOMIC
            bsn(islot_domain_out, 0) = bsn(islot_domain_out, 0) + 1
          else
            islot = ceiling(obs(iof)%dif(n) / SLOT_TINTERVAL - 0.5d0) + SLOT_BASE
            ! process the observations out of range for the analysis period (Comment by satoki)
            if (islot < SLOT_START .or. islot > SLOT_END) then
              islot = islot_time_out
            end if
!$OMP ATOMIC
            bsn(islot, obs(iof)%rank(n)) = bsn(islot, obs(iof)%rank(n)) + 1
          end if
        end do ! [ n = 1, obs(iof)%nobs ]
!$OMP END DO
      end if ! [ OBSDA_RUN(iof) .and. obs(iof)%nobs > 0 ]
    end do ! [ do iof = 1, OBS_IN_NUM ]
!$OMP END PARALLEL

    do ip = 0, nprocs_d-1
      if (ip > 0) then
        bsna(SLOT_START-1, ip) = bsna(SLOT_END+2, ip-1)
      end if
      do islot = SLOT_START, SLOT_END+2
        bsna(islot, ip) = bsna(islot-1, ip) + bsn(islot, ip)
      end do
      bsnext(SLOT_START:SLOT_END+2, ip) = bsna(SLOT_START-1:SLOT_END+1, ip)
    end do

    do iof = 1, OBS_IN_NUM
      if (OBSDA_RUN(iof) .and. obs(iof)%nobs > 0) then
        do n = 1, obs(iof)%nobs
          if (obs(iof)%rank(n) == -1) then
            ! process the observations outside of the model domain in process rank 0
            bsnext(islot_domain_out, 0) = bsnext(islot_domain_out, 0) + 1
            obset_bufs(bsnext(islot_domain_out, 0)) = iof
            obidx_bufs(bsnext(islot_domain_out, 0)) = n
          else
            islot = ceiling(obs(iof)%dif(n) / SLOT_TINTERVAL - 0.5d0) + SLOT_BASE
!(debug) write(*,*) "dif check", iof, n, obs(iof)%dif(n), islot
            if (islot < SLOT_START .or. islot > SLOT_END) then
              islot = islot_time_out
            end if
            bsnext(islot, obs(iof)%rank(n)) = bsnext(islot, obs(iof)%rank(n)) + 1
            obset_bufs(bsnext(islot, obs(iof)%rank(n))) = iof
            obidx_bufs(bsnext(islot, obs(iof)%rank(n))) = n
          end if
        end do ! [ n = 1, obs(iof)%nobs ]
      end if ! [ OBSDA_RUN(iof) .and. obs(iof)%nobs > 0 ]
    end do ! [ do iof = 1, OBS_IN_NUM ]

    deallocate (bsnext)

    call mpi_timer('obsope_cal:bucket_sort:', 2)
  end if ! [ myrank_a == 0 ]

  ! Broadcast the bucket-sort observation numbers to all processes and print
  !-----------------------------------------------------------------------------

  call mpi_timer('', 2, barrier=MPI_COMM_a)

  call MPI_BCAST(bsn,  (SLOT_END-SLOT_START+3)*nprocs_d, MPI_INTEGER, 0, MPI_COMM_a, ierr)
  call MPI_BCAST(bsna, (SLOT_END-SLOT_START+4)*nprocs_d, MPI_INTEGER, 0, MPI_COMM_a, ierr)

  call mpi_timer('obsope_cal:sort_info_bcast:', 2)

  do islot = SLOT_START, SLOT_END
    slot_id(islot) = islot - SLOT_START + 1
    slot_lb(islot) = (real(islot - SLOT_BASE, r_size) - 0.5d0) * SLOT_TINTERVAL
    slot_ub(islot) = (real(islot - SLOT_BASE, r_size) + 0.5d0) * SLOT_TINTERVAL
  end do

  if (LOG_LEVEL >= 2) then
    write (nstr, '(I4)') SLOT_END - SLOT_START + 1
    write (6, *)
    write (6, '(A,I6,A)') 'OBSERVATION COUNTS BEFORE QC (FROM OBSOPE):'
    write (6, '(A,'//nstr//"('=========='),A)") '====================', '===================='
    write (6, '(A,'//nstr//'I10.4)') '            SLOT #  ', slot_id(:)
    write (6, '(A,'//nstr//'F10.1)') '            FROM (s)', slot_lb(:)
    write (6, '(A,'//nstr//'F10.1,A)') 'SUBDOMAIN #   TO (s)', slot_ub(:), '  OUT_TIME     TOTAL'
    write (6, '(A,'//nstr//"('----------'),A)") '--------------------', '--------------------'
    do ip = 0, nprocs_d-1
      write (6, '(I11.6,9x,'//nstr//'I10,2I10)') ip, bsn(SLOT_START:SLOT_END, ip), bsn(islot_time_out, ip), bsna(SLOT_END+1, ip) - bsna(SLOT_START-1, ip)
    end do
    write (6, '(A,'//nstr//"('----------'),A)") '--------------------', '--------------------'
    write (6, '(A,'//nstr//'(10x),10x,I10)') ' OUT_DOMAIN         ', bsn(islot_domain_out, 0)
    write (6, '(A,'//nstr//"('----------'),A)") '--------------------', '--------------------'
    write (6, '(A,'//nstr//'I10,2I10)') '      TOTAL         ', sum(bsn(SLOT_START:SLOT_END, :), dim=2), sum(bsn(islot_time_out, :)), bsna(SLOT_END+2, nprocs_d-1)
    write (6, '(A,'//nstr//"('=========='),A)") '====================', '===================='
  end if

  ! Scatter the basic obsevration information to processes group {myrank_e = 0},
  ! each of which only gets the data in its own subdomain
  !-----------------------------------------------------------------------------

  nobs = bsna(SLOT_END+2, myrank_d) - bsna(SLOT_START-1, myrank_d)

  obsda%nobs = nobs
  call obs_da_value_allocate(obsda, 0)

  if (present(obsda_return)) then
    if (present(nobs_extern)) then
      obsda_return%nobs = nobs + nobs_extern
    else
      obsda_return%nobs = nobs
    end if
    call obs_da_value_allocate(obsda_return, nitmax)
  end if

  if (myrank_e == 0) then
    allocate (cnts(nprocs_d))
    allocate (dsps(nprocs_d))
    do ip = 0, nprocs_d-1
      dsps(ip+1) = bsna(SLOT_START-1, ip)
      cnts(ip+1) = bsna(SLOT_END+2, ip) - dsps(ip+1)
    end do

    call MPI_SCATTERV(obset_bufs, cnts, dsps, MPI_INTEGER, obsda%set, cnts(myrank_d+1), MPI_INTEGER, 0, MPI_COMM_d, ierr)
    call MPI_SCATTERV(obidx_bufs, cnts, dsps, MPI_INTEGER, obsda%idx, cnts(myrank_d+1), MPI_INTEGER, 0, MPI_COMM_d, ierr)

    call mpi_timer('obsope_cal:mpi_scatterv:', 2)

    deallocate (cnts, dsps)
    deallocate (obset_bufs, obidx_bufs)
  end if ! [ myrank_e == 0 ]

  ! Broadcast the basic obsevration information
  ! from processes group {myrank_e = 0} to all processes
  !-----------------------------------------------------------------------------

  call mpi_timer('', 2, barrier=MPI_COMM_e)

  call MPI_BCAST(obsda%set, nobs, MPI_INTEGER, 0, MPI_COMM_e, ierr)
  call MPI_BCAST(obsda%idx, nobs, MPI_INTEGER, 0, MPI_COMM_e, ierr)

  if (present(obsda_return)) then
    obsda_return%set(1:nobs) = obsda%set
    obsda_return%idx(1:nobs) = obsda%idx
  end if

  call mpi_timer('obsope_cal:mpi_broadcast:', 2)

!-------------------------------------------------------------------------------
! Second scan of observation data in own subdomain: Compute H(x), QC, ... etc.
!-------------------------------------------------------------------------------

  allocate ( v3dg (nlevh,nlonh,nlath,nv3dd) )
  allocate ( v2dg (nlonh,nlath,nv2dd) )
  allocate ( rigu (nlonh) )  ! Add by satoki
  allocate ( rigv (nlonh) )  ! Add by satoki
  allocate ( rjgu (nlath) )  ! Add by satoki
  allocate ( rjgv (nlath) )  ! Add by satoki

  do it = 1, nitmax
    im = myrank_to_mem(it)
    if ((im >= 1 .and. im <= MEMBER) .or. im == mmdetin) then

      write (6,'(A,I6.6,A,I4.4,A,I6.6)') 'MYRANK ',myrank,' is processing member ', &
            im, ', subdomain id #', myrank_d

      if (nobs > 0) then
        obsda%qc(1:nobs) = iqc_undef
#ifdef H08
!        obsda%lev(1:nobs) = 0.0d0
!        obsda%val2(1:nobs) = 0.0d0
#endif
      end if

      ! Observations not in the assimilation time window
      ! 
      n1 = bsna(islot_time_out-1, myrank_d) - bsna(SLOT_START-1, myrank_d) + 1
      n2 = bsna(islot_time_out,   myrank_d) - bsna(SLOT_START-1, myrank_d)
      if (n1 <= n2) then
        obsda%qc(n1:n2) = iqc_time
      end if

      ! Observations outside of the model domain
      ! 
      n1 = bsna(islot_domain_out-1, myrank_d) - bsna(SLOT_START-1, myrank_d) + 1
      n2 = bsna(islot_domain_out,   myrank_d) - bsna(SLOT_START-1, myrank_d)
      if (n1 <= n2) then
        obsda%qc(n1:n2) = iqc_out_h
      end if

      ! Valid observations: loop over time slots
      ! 
      do islot = SLOT_START, SLOT_END
        write (6, '(A,I3,A,F9.1,A,F9.1,A)') 'Slot #', islot-SLOT_START+1, ': time window (', slot_lb(islot), ',', slot_ub(islot), '] sec'

        n1 = bsna(islot-1, myrank_d) - bsna(SLOT_START-1, myrank_d) + 1
        n2 = bsna(islot,   myrank_d) - bsna(SLOT_START-1, myrank_d)
        slot_nobsg = sum(bsn(islot, :))

        if (slot_nobsg <= 0) then
          write (6, '(A)') ' -- no observations found in this time slot... do not need to read model data'
          cycle
        end if

        write (6, '(A,I10)') ' -- # obs in the slot = ', slot_nobsg
        write (6, '(A,I6,A,I6,A,I10)') ' -- # obs in the slot and processed by rank ', myrank, ' (subdomain #', myrank_d, ') = ', bsn(islot, myrank_d)

        call mpi_timer('', 2)

        ! Reading ens. output from SCALE (Comment by satoki)
!(ORG: by satoki)        call read_ens_history_iter(it, islot, v3dg, v2dg)
        call read_ens_history_iter(it, islot, v3dg, v2dg,  &
  &                                rigu=rigu, rigv=rigv, rjgu=rjgu, rjgv=rjgv)

        write (timer_str, '(A30,I4,A7,I4,A2)') 'obsope_cal:read_ens_history(t=', it, ', slot=', islot, '):'
        call mpi_timer(trim(timer_str), 2)

        allocate ( tmp_obsdp_H08vt (slot_nobsg) )  ! Add by satoki
        allocate ( tmp_obsgp_H08vt (slot_nobsg,nprocs_d) )  ! Add by satoki
        allocate ( tmp_obsdp_H08vr (slot_nobsg) )  ! Add by satoki
        allocate ( tmp_obsgp_H08vr (slot_nobsg,nprocs_d) )  ! Add by satoki

        tmp_nobsd_H08vt = 0  ! Add by satoki
        tmp_obsdp_H08vt = 0  ! Add by satoki
        tmp_nobsd_H08vr = 0  ! Add by satoki
        tmp_obsdp_H08vr = 0  ! Add by satoki

!(ORG: remove due to H08vt satoki)!$OMP PARALLEL DO SCHEDULE(DYNAMIC,5) PRIVATE(nn,n,iof,ril,rjl,rk,rkz)
        do nn = n1, n2
          iof = obsda%set(nn)
          n = obsda%idx(nn)

          ! Convert (ril,rjl) in local domain from the myrank and (rig,rjg) in global domain
          ! for the observation (Comment by satoki)
          call rij_g2l(myrank_d, obs(iof)%ri(n), obs(iof)%rj(n), ril, rjl)

          if (.not. USE_OBS(obs(iof)%typ(n))) then
            obsda%qc(nn) = iqc_otype
            cycle
          end if

          select case (OBS_IN_FORMAT(iof))
          !=====================================================================
          case (obsfmt_prepbufr)  ! For prepbufr (Comment by satoki)
          !---------------------------------------------------------------------
            !-- OBS_IN_FORMAT = 'PREPBUF' & obs%elm = id_{u,v}_obs & obs%typ = 'SATWND' (4)
            !--  -> obs%lev = [m] (add by satoki for satellite AMV H08UV)
            if(((obs(iof)%elm(n)==id_u_obs).or.(obs(iof)%elm(n)==id_v_obs)).and. &
  &           obs(iof)%typ(n)==4)then
              call phys2ijkz(v3dg(:,:,:,iv3dd_hgt), ril, rjl, obs(iof)%lev(n), rk, obsda%qc(nn))
            else  ! below is original code (by satoki)
              call phys2ijk(v3dg(:,:,:,iv3dd_p), obs(iof)%elm(n), ril, rjl, obs(iof)%lev(n), rk, obsda%qc(nn))
            end if
            if (obsda%qc(nn) == iqc_good) then
              call Trans_XtoY(obs(iof)%elm(n), ril, rjl, rk, &
                              obs(iof)%lon(n), obs(iof)%lat(n), v3dg, v2dg, obsda%val(nn), obsda%qc(nn))
            end if
          !=====================================================================
          case (obsfmt_radar)  ! For radar (Comment by satoki)
          !---------------------------------------------------------------------
            if (obs(iof)%lev(n) > RADAR_ZMAX) then
              obsda%qc(nn) = iqc_radar_vhi
              if (LOG_LEVEL >= 3) then
                write(6,'(A,F8.1,A,I5)') '[Warning] radar observation is too high: lev=', obs(iof)%lev(n), ', elem=', obs(iof)%elm(n)
              end if
            else
              call phys2ijkz(v3dg(:,:,:,iv3dd_hgt), ril, rjl, obs(iof)%lev(n), rkz, obsda%qc(nn))
            end if
            if (obsda%qc(nn) == iqc_good) then
              call Trans_XtoY_radar(obs(iof)%elm(n), obs(iof)%meta(1), obs(iof)%meta(2), obs(iof)%meta(3), ril, rjl, rkz, &
                                    obs(iof)%lon(n), obs(iof)%lat(n), obs(iof)%lev(n), v3dg, v2dg, obsda%val(nn), obsda%qc(nn))
              if (obsda%qc(nn) == iqc_ref_low) obsda%qc(nn) = iqc_good ! when process the observation operator, we don't care if reflectivity is too small

              !!!!!! may not need to do this at this stage !!!!!!
              !if (obs(iof)%elm(n) == id_radar_ref_obs) then
              !  obsda%val(nn) = 10.0d0 * log10(obsda%val(nn))
              !end if
              !!!!!!
            end if
#ifdef H08
          !=====================================================================
!          case (obsfmt_h08)
          !---------------------------------------------------------------------

#endif
          !=====================================================================
          case (obsfmt_h08vt)  ! For H08VT (Added by satoki)
          !---------------------------------------------------------------------
            tmp_nobsd_H08vt = tmp_nobsd_H08vt + 1
            tmp_obsdp_H08vt(tmp_nobsd_H08vt) = nn

          !=====================================================================
          case (obsfmt_h08vr)  ! For H08VR (Added by satoki)
          !---------------------------------------------------------------------
            tmp_nobsd_H08vr = tmp_nobsd_H08vr + 1
            tmp_obsdp_H08vr(tmp_nobsd_H08vr) = nn

          !=====================================================================

          end select

!              ENDIF ! H08 ????????????

        end do ! [ nn = n1, n2 ]
!(ORG: remove due to H08vt satoki)!$OMP END PARALLEL DO



#ifdef H08
          ELSEIF(OBS_IN_FORMAT(iof) == obsfmt_h08) THEN ! H08

            nprof_H08 = 0
!            nobs_0 = nobs
            nallprof = obs(iof)%nobs/nch

            ALLOCATE(tmp_ri_H08(nallprof))
            ALLOCATE(tmp_rj_H08(nallprof))
            ALLOCATE(tmp_lon_H08(nallprof))
            ALLOCATE(tmp_lat_H08(nallprof))

            do n = 1, nallprof
              ns = (n - 1) * nch + 1
              if (obs(iof)%dif(ns) > slot_lb(islot) .and. obs(iof)%dif(ns) <= slot_ub(islot)) then
!                nslot = nslot + 1
                call phys2ij(obs(iof)%lon(ns),obs(iof)%lat(ns),rig,rjg)
                call rij_rank_g2l(rig,rjg,proc,ritmp,rjtmp)

                if (myrank_d == proc) then
                  nprof_H08 = nprof_H08 + 1 ! num of prof in myrank node
                  tmp_ri_H08(nprof_H08) = ritmp
                  tmp_rj_H08(nprof_H08) = rjtmp
                  tmp_lon_H08(nprof_H08) = obs(iof)%lon(ns)
                  tmp_lat_H08(nprof_H08) = obs(iof)%lat(ns)

!                  nobs = nobs + nch
!                  nobs_slot = nobs_slot + 1
                  obsda%set(nobs-nch+1:nobs) = iof
!!!!!!                  obsda%ri(nobs-nch+1:nobs) = rig
!!!!!!                  obsda%rj(nobs-nch+1:nobs) = rjg
                  ri(nobs-nch+1:nobs) = ritmp
                  rj(nobs-nch+1:nobs) = rjtmp
                  do ch = 1, nch
                    obsda%idx(nobs-nch+ch) = ns + ch - 1
                  enddo

                end if ! [ myrank_d == proc ]
              end if ! [ obs(iof)%dif(n) > slot_lb(islot) .and. obs(iof)%dif(n) <= slot_ub(islot) ]
            end do ! [ n = 1, nallprof ]

            IF(nprof_H08 >=1)THEN
              ALLOCATE(ri_H08(nprof_H08))
              ALLOCATE(rj_H08(nprof_H08))
              ALLOCATE(lon_H08(nprof_H08))
              ALLOCATE(lat_H08(nprof_H08))

              ri_H08 = tmp_ri_H08(1:nprof_H08)
              rj_H08 = tmp_rj_H08(1:nprof_H08)
              lon_H08 = tmp_lon_H08(1:nprof_H08)
              lat_H08 = tmp_lat_H08(1:nprof_H08)

            ENDIF

            DEALLOCATE(tmp_ri_H08,tmp_rj_H08)
            DEALLOCATE(tmp_lon_H08,tmp_lat_H08)

#endif

#ifdef H08
          ELSEIF((OBS_IN_FORMAT(iof) == obsfmt_h08).and.(nprof_H08 >=1 ))THEN ! H08
! -- Note: Trans_XtoY_H08 is called without OpenMP but it can use a parallel (with OpenMP) RTTOV routine
!
            !------
            if (.not. USE_OBS(23)) then
              obsda%qc(nobs_0+1:nobs) = iqc_otype
            else
            !------

            ALLOCATE(yobs_H08(nprof_H08*nch))
            ALLOCATE(yobs_H08_clr(nprof_H08*nch))
            ALLOCATE(plev_obs_H08(nprof_H08*nch))
            ALLOCATE(qc_H08(nprof_H08*nch))

            CALL Trans_XtoY_H08(nprof_H08,ri_H08,rj_H08,&
                                lon_H08,lat_H08,v3dg,v2dg,&
                                yobs_H08,plev_obs_H08,&
                                qc_H08,yobs_H08_clr=yobs_H08_clr)

! Clear sky yobs(>0)
! Cloudy sky yobs(<0)

            obsda%qc(nobs_0+1:nobs) = iqc_obs_bad

            ns = 0
            DO nn = nobs_0 + 1, nobs
              ns = ns + 1

              obsda%val(nn) = yobs_H08(ns)
              obsda%qc(nn) = qc_H08(ns)

              if(obsda%qc(nn) == iqc_good)then
!!!!!!                rig = obsda%ri(nn)
!!!!!!                rjg = obsda%rj(nn)

! -- tentative treatment around the TC center --
!                dist_MSLP_TC = sqrt(((rig - MSLP_TC_rig) * DX)**2&
!                                   +((rjg - MSLP_TC_rjg) * DY)**2)

!                if(dist_MSLP_TC <= dist_MSLP_TC_MIN)then
!                  obsda%qc(nn) = iqc_obs_bad
!                endif

! -- Rejecting Himawari-8 obs over the buffer regions. --
                if((rig <= bris) .or. (rig >= brie) .or.&
                   (rjg <= brjs) .or. (rjg >= brje))then
                  obsda%qc(nn) = iqc_obs_bad
                endif
              endif

!
!  NOTE: T.Honda (10/16/2015)
!  The original H08 obs does not inlcude the level information.
!  However, we have the level information derived by RTTOV (plev_obs_H08) here, 
!  so that we substitute the level information into obsda%lev.  
!  The substituted level information is used in letkf_tools.f90
!
              obsda%lev(nn) = plev_obs_H08(ns)
              obsda%val2(nn) = yobs_H08_clr(ns)

!              write(6,'(a,f12.1,i9)')'H08 debug_plev',obsda%lev(nn),nn

            END DO ! [ nn = nobs_0 + 1, nobs ]

            DEALLOCATE(ri_H08, rj_H08)
            DEALLOCATE(lon_H08, lat_H08)
            DEALLOCATE(yobs_H08, plev_obs_H08)
            DEALLOCATE(yobs_H08_clr)
            DEALLOCATE(qc_H08)

            !------
            end if ! [.not. USE_OBS(23)]
            !------

#endif
!!!          ENDIF ! H08

        !---------------------------------------------------------------------
        ! Calculate H(x) for H08VT (Added by Satoki Tsujino)
        !---------------------------------------------------------------------
!        write (6, '(A,I10)') ' -- # obs in the slot = ', slot_nobsg
!        write (6, '(A,I6,A,I6,A,I10)') ' -- # obs in the slot and processed by rank ', myrank, ' (subdomain #', myrank_d, ') = ', bsn(islot, myrank_d)

!org      if(myrank_e == 0)then
        !-- Allocate internal working variables
        !-- [Note]: Number of the array element is greater than that used 
        !--         in real (=nprof_H08vt still not defined here) for safety
        ALLOCATE(ri_H08vt(slot_nobsg,nprocs_d))
        ALLOCATE(rj_H08vt(slot_nobsg,nprocs_d))
        ALLOCATE(lon_H08vt(slot_nobsg,nprocs_d))
        ALLOCATE(lat_H08vt(slot_nobsg,nprocs_d))
        ALLOCATE(rad_H08vt(slot_nobsg,nprocs_d))
        ALLOCATE(lev_H08vt(slot_nobsg,nprocs_d))
        ALLOCATE(lev2_H08vt(slot_nobsg,nprocs_d))
        ALLOCATE(valid_H08vt(slot_nobsg,nprocs_d))

        ri_H08vt = 0.0
        rj_H08vt = 0.0
        lon_H08vt = 0.0
        lat_H08vt = 0.0
        rad_H08vt = 0.0
        lev_H08vt = 0.0
        lev2_H08vt = 0.0
        valid_H08vt = .false.

            !-- 1. Gather all observations of H08VT
!org        tmp_nobsg_H08vt = 0
!org        call mpi_timer('', 2, barrier = MPI_COMM_d)

!org        call MPI_AllReduce(tmp_nobsd_H08vt,tmp_nobsg_H08vt,1,MPI_INTEGER,MPI_SUM,MPI_COMM_d,ierr)  ! sum[rank(0-M)] -> rank(0-M)
!(debug) write(*,*) "satoki (debug1)", tmp_obsgp_H08vt(:,myrank_d+1)
        call mpi_timer('', 2, barrier = MPI_COMM_d)
        call MPI_ALLGATHER(tmp_obsdp_H08vt,slot_nobsg,MPI_INTEGER,  &
  &                        tmp_obsgp_H08vt,slot_nobsg,MPI_INTEGER,  &
  &                        MPI_COMM_d,ierr)  ! Share among all processes
        call mpi_timer('tmp_obsgp_H08vt Allgather', 2, barrier = MPI_COMM_d)
!(debug) write(*,*) "check1", tmp_obsdp_H08vt
!(debug) write(*,*) "check2", tmp_obsgp_H08vt

        !-- 2. Check available observations in each subdomain, and 
        !--    Broadcast the observations to all subdomains
        nprof_H08vt = 0  ! total count
        !do nn = n1, n2
!org        do nn = 1, tmp_nobsg_H08vt

        do ns = 1, nprocs_d      ! For subdomain processes
          do nt = 1, slot_nobsg  ! For observations in each subdomain
            nu = tmp_obsgp_H08vt(nt,ns)
!(debug) write(*,*) "satoki check2, nt, ns, nu", nt, ns, nu
            if( nu > 0 )then

              if( myrank_d == ns - 1 )then  ! Enter in an MPI rank (ns - 1)
                iof = obsda%set(nu)
                nm = obsda%idx(nu)

!not use                if (.not. USE_OBS(obs(iof)%typ(nm))) then
!not use                  obsda%qc(nu) = iqc_otype
!not use                  cycle
!not use                end if

!org            nprof_H08vt = 0
!org            nallprofvt = obs(iof)%nobs

!org            ALLOCATE(tmp_ri_H08vt(nallprofvt))
!org            ALLOCATE(tmp_rj_H08vt(nallprofvt))
!org            ALLOCATE(tmp_lon_H08vt(nallprofvt))
!org            ALLOCATE(tmp_lat_H08vt(nallprofvt))
!org            ALLOCATE(tmp_rad_H08vt(nallprofvt))
!org            ALLOCATE(tmp_lev_H08vt(nallprofvt))
!org            ALLOCATE(tmp_lev2_H08vt(nallprofvt))

!(debug) write(*,*) "satoki tmp  check", nu, iof, obs(iof)%dif(nu)
!orig(2024/01/22)                n = nu
                n = nm
!org            do n = 1, nallprofvt
                if (obs(iof)%dif(n) > slot_lb(islot) .and. obs(iof)%dif(n) <= slot_ub(islot)) then
!(debug) write(*,*) "obs check satoki", obs(iof)%rad(n), obs(iof)%lon(n),  &
!(debug)   &obs(iof)%lat(n), obs(iof)%lev(n), obs(iof)%lev2(n)
                  call phys2ij(obs(iof)%lon(n),obs(iof)%lat(n),rig,rjg)  ! Search rig,rjg from lon,lat
                  call rij_rank(rig,rjg,proc)  ! Calculate ril,rjl from myrank

                  nprof_H08vt = nprof_H08vt + 1 ! num of prof in myrank

!org (no need?)            if (myrank_d == proc) then
!org              nprof_H08vt = nprof_H08vt + 1 ! num of prof in myrank
!org              tmp_ri_H08vt(nprof_H08vt) = rig
!org              tmp_rj_H08vt(nprof_H08vt) = rjg
!org              tmp_lon_H08vt(nprof_H08vt) = obs(iof)%lon(n)
!org              tmp_lat_H08vt(nprof_H08vt) = obs(iof)%lat(n)
!org              tmp_rad_H08vt(nprof_H08vt) = obs(iof)%rad(n)
!org              tmp_lev_H08vt(nprof_H08vt) = obs(iof)%lev(n)
!org              tmp_lev2_H08vt(nprof_H08vt) = obs(iof)%lev2(n)
                  mpi_bcast_v_H08vt(1) = rig
                  mpi_bcast_v_H08vt(2) = rjg
                  mpi_bcast_v_H08vt(3) = obs(iof)%lon(n)
                  mpi_bcast_v_H08vt(4) = obs(iof)%lat(n)
                  mpi_bcast_v_H08vt(5) = obs(iof)%rad(n)
                  mpi_bcast_v_H08vt(6) = obs(iof)%lev(n)
                  mpi_bcast_v_H08vt(7) = obs(iof)%lev2(n)
                  valid_H08vt(nt,ns) = .true.

!                  nobs_slot = nobs_slot + 1
                  !obsda%set(nprof_H08vt) = iof
                  obsda%set(nu) = iof
                  !obsda%ri(nprof_H08vt) = rig
                  !obsda%rj(nprof_H08vt) = rjg
                  !obsda%idx(nprof_H08vt) = n  ! No check
                  obsda%idx(nu) = n  ! No check

!org (no need?)            end if ! [ myrank_d == proc ]
                end if ! [ obs(iof)%dif(n) > slot_lb(islot) .and. obs(iof)%dif(n) <= slot_ub(islot) ]
!org            end do ! [ n = 1, nallprofvt ]

              end if ! [ myrank_d == ns - 1 ]

write(*,*) "satoki bcast check3, nt, ns, nu", nt, ns, nu, myrank_d, mpi_bcast_v_H08vt
              call mpi_timer('', 2, barrier = MPI_COMM_d)
              call MPI_BCAST(nprof_H08vt,1, MPI_INTEGER, ns-1, MPI_COMM_d, ierr)
              call MPI_BCAST(valid_H08vt(nt,ns),1, MPI_LOGICAL, ns-1, MPI_COMM_d, ierr)
              call MPI_BCAST(mpi_bcast_v_H08vt, 7, MPI_r_size,  ns-1, MPI_COMM_d, ierr)
              call mpi_timer('', 2, barrier = MPI_COMM_d)

!(debug) write(*,*) "satoki bcast check4, nt, ns, nu", nt, ns, nu, myrank_d, mpi_bcast_v_H08vt
              ri_H08vt(nt,ns)    = mpi_bcast_v_H08vt(1)
              rj_H08vt(nt,ns)    = mpi_bcast_v_H08vt(2)
              lon_H08vt(nt,ns)   = mpi_bcast_v_H08vt(3)
              lat_H08vt(nt,ns)   = mpi_bcast_v_H08vt(4)
              rad_H08vt(nt,ns)   = mpi_bcast_v_H08vt(5)
              lev_H08vt(nt,ns)   = mpi_bcast_v_H08vt(6)
              lev2_H08vt(nt,ns)  = mpi_bcast_v_H08vt(7)

!org            IF(nprof_H08vt >=1)THEN

!org              ri_H08vt   = tmp_ri_H08vt(1:nprof_H08vt)
!org              rj_H08vt   = tmp_rj_H08vt(1:nprof_H08vt)
!org              lon_H08vt  = tmp_lon_H08vt(1:nprof_H08vt)
!org              lat_H08vt  = tmp_lat_H08vt(1:nprof_H08vt)
!org              rad_H08vt  = tmp_rad_H08vt(1:nprof_H08vt)
!org              lev_H08vt  = tmp_lev_H08vt(1:nprof_H08vt)
!org              lev2_H08vt = tmp_lev2_H08vt(1:nprof_H08vt)

            !------
!              if (.not. USE_OBS(23)) then
!                obsda%qc(nobs_0+1:nobs) = iqc_otype
!              else
            !------

            else

              exit

            end if  ! [ nu > 0 ]

          end do  ! [ nt = 1, slot_nobsg ] ! For observations in each subdomain
        end do  ! [ ns = 1, nprocs_d ]     ! For subdomain processes

        call mpi_timer('', 2, barrier = MPI_COMM_d)
!(debug) write(*,*) "satoki check Enter Trans_XtoY_H08VT"
        ALLOCATE(yobs_H08vt(slot_nobsg,nprocs_d))
        ALLOCATE(qc_H08vt(slot_nobsg,nprocs_d))

!(debug) write(*,*) "rad check satoki", rad_H08vt, nprof_H08vt
!(debug) write(*,*) "satoki checkk, Enter Trans"!, OBS_IN_FORMAT(iof), iof
        !-- 3. Enter the actual observation operator [H(x)] for H08VT
        !--    [out]: yobs_H08vt,qc_H08vt for each subdomain
        CALL Trans_XtoY_H08VT(slot_nobsg,nprocs_d,ri_H08vt,rj_H08vt,lev_H08vt,lev2_H08vt,  &
  &                           lon_H08vt,lat_H08vt,rad_H08vt,valid_H08vt,  &
  &                           rigu,rigv,rjgu,rjgv,v3dg,v2dg,'obs',yobs_H08vt,qc_H08vt,1)
!(debug) write(*,*) "satoki check Exit Trans_XtoY_H08VT"

!        obsda%qc(nobs_0+1:nobs) = iqc_obs_bad

!org        nsvt = 0
!org        DO nt = 1, nprof_H08vt
!        DO nn = nobs_0 + 1, nobs
!org          nsvt = nsvt + 1

!org          obsda%val(nt) = yobs_H08vt(nsvt)
!org          obsda%qc(nt) = qc_H08vt(nsvt)

!          if(obsda%qc(nn) == iqc_good)then
!!!!!!          rig = obsda%ri(nn)
!!!!!!          rjg = obsda%rj(nn)

! -- tentative treatment around the TC center --
!            dist_MSLP_TC = sqrt(((rig - MSLP_TC_rig) * DX)**2&
!                               +((rjg - MSLP_TC_rjg) * DY)**2)

!            if(dist_MSLP_TC <= dist_MSLP_TC_MIN)then
!              obsda%qc(nn) = iqc_obs_bad
!            endif

! -- Rejecting Himawari-8 obs over the buffer regions. --
!            if((rig <= bris) .or. (rig >= brie) .or.&
!               (rjg <= brjs) .or. (rjg >= brje))then
!              obsda%qc(nn) = iqc_obs_bad
!            endif
!          endif

!
!          write(6,'(a,f12.1,i9)')'H08 debug_plev',obsda%lev(nn),nn

!        END DO ! [ nt = 1, nprof_H08vt ]

        !-- 4. Return H(x) to obs variables in the "original" subdomain
        !--    [NOTE]: yobs_H08vt,qc_H08vt have been shared among all subdomains
!org (no longer share among all processes in the loop)            do ns = 1, nprocs_d      ! For subdomain processes
        do nt = 1, slot_nobsg  ! For observations in each subdomain

          nu = tmp_obsgp_H08vt(nt,myrank_d+1)

          if( nu > 0 )then

!org (not need because automatically myrank_d == ns - 1)                if( myrank_d == ns - 1 )then  ! Enter in an MPI rank (ns - 1)
            iof = obsda%set(nu)
            nm = obsda%idx(nu)

            if (.not. USE_OBS(obs(iof)%typ(nm))) then
              cycle
            end if

!orig(2024/01/22)            n = nu
            n = nm

            if (obs(iof)%dif(n) > slot_lb(islot) .and. obs(iof)%dif(n) <= slot_ub(islot)) then

              obsda%val(nu) = yobs_H08vt(nt,myrank_d+1)
              obsda%qc(nu) = qc_H08vt(nt,myrank_d+1)

            end if ! [ obs(iof)%dif(n) > slot_lb(islot) .and. obs(iof)%dif(n) <= slot_ub(islot) ]

!org            end if ! [ myrank_d == ns - 1 ]

          else

            exit

          end if  ! [ nu > 0 ]

        end do  ! [ nt = 1, slot_nobsg ] ! For observations in each subdomain
!org        end do  ! [ ns = 1, nprocs_d ]     ! For subdomain processes

        DEALLOCATE(ri_H08vt,rj_H08vt)
        DEALLOCATE(lon_H08vt,lat_H08vt)
        DEALLOCATE(rad_H08vt)
        DEALLOCATE(lev_H08vt,lev2_H08vt)
        DEALLOCATE(valid_H08vt)

        DEALLOCATE(yobs_H08vt)
        DEALLOCATE(qc_H08vt)

!org          ENDIF  ! [ myrank_e == 0 ]

        deallocate ( tmp_obsdp_H08vt )
        deallocate ( tmp_obsgp_H08vt )

!org              DEALLOCATE(tmp_ri_H08vt,tmp_rj_H08vt)
!org              DEALLOCATE(tmp_lon_H08vt,tmp_lat_H08vt)
!org              DEALLOCATE(tmp_rad_H08vt)
!org              DEALLOCATE(tmp_lev_H08vt,tmp_lev2_H08vt)

          !------
!          end if ! [.not. USE_OBS(23)]
!org            ENDIF  ![ OBS_IN_FORMAT(iof) == obsfmt_h08 ] ! H08VT
          !------

          !=====================================================================

!org          end do ! [ nn = 1, slot_nobs ]

        !---------------------------------------------------------------------
        ! Calculate H(x) for H08VR (Added by Satoki Tsujino)
        !---------------------------------------------------------------------
!        write (6, '(A,I10)') ' -- # obs in the slot = ', slot_nobsg
!        write (6, '(A,I6,A,I6,A,I10)') ' -- # obs in the slot and processed by rank ', myrank, ' (subdomain #', myrank_d, ') = ', bsn(islot, myrank_d)

!org      if(myrank_e == 0)then
        !-- Allocate internal working variables
        !-- [Note]: Number of the array element is greater than that used 
        !--         in real (=nprof_H08vr still not defined here) for safety
        ALLOCATE(ri_H08vr(slot_nobsg,nprocs_d))
        ALLOCATE(rj_H08vr(slot_nobsg,nprocs_d))
        ALLOCATE(lon_H08vr(slot_nobsg,nprocs_d))
        ALLOCATE(lat_H08vr(slot_nobsg,nprocs_d))
        ALLOCATE(rad_H08vr(slot_nobsg,nprocs_d))
        ALLOCATE(lev_H08vr(slot_nobsg,nprocs_d))
        ALLOCATE(lev2_H08vr(slot_nobsg,nprocs_d))
        ALLOCATE(valid_H08vr(slot_nobsg,nprocs_d))

        ri_H08vr = 0.0
        rj_H08vr = 0.0
        lon_H08vr = 0.0
        lat_H08vr = 0.0
        rad_H08vr = 0.0
        lev_H08vr = 0.0
        lev2_H08vr = 0.0
        valid_H08vr = .false.

            !-- 1. Gather all observations of H08VR
!org        tmp_nobsg_H08vr = 0
!org        call mpi_timer('', 2, barrier = MPI_COMM_d)

!org        call MPI_AllReduce(tmp_nobsd_H08vr,tmp_nobsg_H08vr,1,MPI_INTEGER,MPI_SUM,MPI_COMM_d,ierr)  ! sum[rank(0-M)] -> rank(0-M)
!(debug) write(*,*) "satoki (debug1)", tmp_obsgp_H08vr(:,myrank_d+1)
        call mpi_timer('', 2, barrier = MPI_COMM_d)
        call MPI_ALLGATHER(tmp_obsdp_H08vr,slot_nobsg,MPI_INTEGER,  &
  &                        tmp_obsgp_H08vr,slot_nobsg,MPI_INTEGER,  &
  &                        MPI_COMM_d,ierr)  ! Share among all processes
        call mpi_timer('tmp_obsgp_H08vr Allgather', 2, barrier = MPI_COMM_d)
!(debug) write(*,*) "check1", tmp_obsdp_H08vr
!(debug) write(*,*) "check2", tmp_obsgp_H08vr

        !-- 2. Check available observations in each subdomain, and 
        !--    Broadcast the observations to all subdomains
        nprof_H08vr = 0  ! total count
        !do nn = n1, n2
!org        do nn = 1, tmp_nobsg_H08vr

        do ns = 1, nprocs_d      ! For subdomain processes
          do nt = 1, slot_nobsg  ! For observations in each subdomain
            nu = tmp_obsgp_H08vr(nt,ns)
!(debug) write(*,*) "satoki check2, nt, ns, nu", nt, ns, nu
            if( nu > 0 )then

              if( myrank_d == ns - 1 )then  ! Enter in an MPI rank (ns - 1)
                iof = obsda%set(nu)
                nm = obsda%idx(nu)

!not use                if (.not. USE_OBS(obs(iof)%typ(nm))) then
!not use                  obsda%qc(nu) = iqc_otype
!not use                  cycle
!not use                end if

!org            nprof_H08vr = 0
!org            nallprofvr = obs(iof)%nobs

!org            ALLOCATE(tmp_ri_H08vr(nallprofvr))
!org            ALLOCATE(tmp_rj_H08vr(nallprofvr))
!org            ALLOCATE(tmp_lon_H08vr(nallprofvr))
!org            ALLOCATE(tmp_lat_H08vr(nallprofvr))
!org            ALLOCATE(tmp_rad_H08vr(nallprofvr))
!org            ALLOCATE(tmp_lev_H08vr(nallprofvr))
!org            ALLOCATE(tmp_lev2_H08vr(nallprofvr))

!(debug) write(*,*) "satoki tmp  check", nu, iof, obs(iof)%dif(nu)
!orig(2024/01/22)                n = nu
                n = nm
!org            do n = 1, nallprofvr
                if (obs(iof)%dif(n) > slot_lb(islot) .and. obs(iof)%dif(n) <= slot_ub(islot)) then
!(debug) write(*,*) "obs check satoki", obs(iof)%rad(n), obs(iof)%lon(n),  &
!(debug)   &obs(iof)%lat(n), obs(iof)%lev(n), obs(iof)%lev2(n)
                  call phys2ij(obs(iof)%lon(n),obs(iof)%lat(n),rig,rjg)  ! Search rig,rjg from lon,lat
                  call rij_rank(rig,rjg,proc)  ! Calculate ril,rjl from myrank

                  nprof_H08vr = nprof_H08vr + 1 ! num of prof in myrank

!org (no need?)            if (myrank_d == proc) then
!org              nprof_H08vr = nprof_H08vr + 1 ! num of prof in myrank
!org              tmp_ri_H08vr(nprof_H08vr) = rig
!org              tmp_rj_H08vr(nprof_H08vr) = rjg
!org              tmp_lon_H08vr(nprof_H08vr) = obs(iof)%lon(n)
!org              tmp_lat_H08vr(nprof_H08vr) = obs(iof)%lat(n)
!org              tmp_rad_H08vr(nprof_H08vr) = obs(iof)%rad(n)
!org              tmp_lev_H08vr(nprof_H08vr) = obs(iof)%lev(n)
!org              tmp_lev2_H08vr(nprof_H08vr) = obs(iof)%lev2(n)
                  mpi_bcast_v_H08vr(1) = rig
                  mpi_bcast_v_H08vr(2) = rjg
                  mpi_bcast_v_H08vr(3) = obs(iof)%lon(n)
                  mpi_bcast_v_H08vr(4) = obs(iof)%lat(n)
                  mpi_bcast_v_H08vr(5) = obs(iof)%rad(n)
                  mpi_bcast_v_H08vr(6) = obs(iof)%lev(n)
                  mpi_bcast_v_H08vr(7) = obs(iof)%lev2(n)
                  valid_H08vr(nt,ns) = .true.

!                  nobs_slot = nobs_slot + 1
                  !obsda%set(nprof_H08vr) = iof
                  obsda%set(nu) = iof
                  !obsda%ri(nprof_H08vr) = rig
                  !obsda%rj(nprof_H08vr) = rjg
                  !obsda%idx(nprof_H08vr) = n  ! No check
                  obsda%idx(nu) = n  ! No check

!org (no need?)            end if ! [ myrank_d == proc ]
                end if ! [ obs(iof)%dif(n) > slot_lb(islot) .and. obs(iof)%dif(n) <= slot_ub(islot) ]
!org            end do ! [ n = 1, nallprofvr ]

              end if ! [ myrank_d == ns - 1 ]

write(*,*) "satoki bcast check3, nt, ns, nu", nt, ns, nu, myrank_d, mpi_bcast_v_H08vr
              call mpi_timer('', 2, barrier = MPI_COMM_d)
              call MPI_BCAST(nprof_H08vr,1, MPI_INTEGER, ns-1, MPI_COMM_d, ierr)
              call MPI_BCAST(valid_H08vr(nt,ns),1, MPI_LOGICAL, ns-1, MPI_COMM_d, ierr)
              call MPI_BCAST(mpi_bcast_v_H08vr, 7, MPI_r_size,  ns-1, MPI_COMM_d, ierr)
              call mpi_timer('', 2, barrier = MPI_COMM_d)

!(debug) write(*,*) "satoki bcast check4, nt, ns, nu", nt, ns, nu, myrank_d, mpi_bcast_v_H08vr
              ri_H08vr(nt,ns)    = mpi_bcast_v_H08vr(1)
              rj_H08vr(nt,ns)    = mpi_bcast_v_H08vr(2)
              lon_H08vr(nt,ns)   = mpi_bcast_v_H08vr(3)
              lat_H08vr(nt,ns)   = mpi_bcast_v_H08vr(4)
              rad_H08vr(nt,ns)   = mpi_bcast_v_H08vr(5)
              lev_H08vr(nt,ns)   = mpi_bcast_v_H08vr(6)
              lev2_H08vr(nt,ns)  = mpi_bcast_v_H08vr(7)

!org            IF(nprof_H08vr >=1)THEN

!org              ri_H08vr   = tmp_ri_H08vr(1:nprof_H08vr)
!org              rj_H08vr   = tmp_rj_H08vr(1:nprof_H08vr)
!org              lon_H08vr  = tmp_lon_H08vr(1:nprof_H08vr)
!org              lat_H08vr  = tmp_lat_H08vr(1:nprof_H08vr)
!org              rad_H08vr  = tmp_rad_H08vr(1:nprof_H08vr)
!org              lev_H08vr  = tmp_lev_H08vr(1:nprof_H08vr)
!org              lev2_H08vr = tmp_lev2_H08vr(1:nprof_H08vr)

            !------
!              if (.not. USE_OBS(23)) then
!                obsda%qc(nobs_0+1:nobs) = iqc_otype
!              else
            !------

            else

              exit

            end if  ! [ nu > 0 ]

          end do  ! [ nt = 1, slot_nobsg ] ! For observations in each subdomain
        end do  ! [ ns = 1, nprocs_d ]     ! For subdomain processes

        call mpi_timer('', 2, barrier = MPI_COMM_d)
!(debug) write(*,*) "satoki check Enter Trans_XtoY_H08VR"
        ALLOCATE(yobs_H08vr(slot_nobsg,nprocs_d))
        ALLOCATE(qc_H08vr(slot_nobsg,nprocs_d))

!(debug) write(*,*) "rad check satoki", rad_H08vr, nprof_H08vr
!(debug) write(*,*) "satoki checkk, Enter Trans"!, OBS_IN_FORMAT(iof), iof
        !-- 3. Enter the actual observation operator [H(x)] for H08VR
        !--    [out]: yobs_H08vr,qc_H08vr for each subdomain
        CALL Trans_XtoY_H08VR(slot_nobsg,nprocs_d,ri_H08vr,rj_H08vr,lev_H08vr,lev2_H08vr,  &
  &                           lon_H08vr,lat_H08vr,rad_H08vr,valid_H08vr,  &
  &                           rigu,rigv,rjgu,rjgv,v3dg,v2dg,'obs',yobs_H08vr,qc_H08vr,1)
!(debug) write(*,*) "satoki check Exit Trans_XtoY_H08VR"

!        obsda%qc(nobs_0+1:nobs) = iqc_obs_bad

!org        nsvr = 0
!org        DO nt = 1, nprof_H08vr
!        DO nn = nobs_0 + 1, nobs
!org          nsvr = nsvr + 1

!org          obsda%val(nt) = yobs_H08vr(nsvr)
!org          obsda%qc(nt) = qc_H08vr(nsvr)

!          if(obsda%qc(nn) == iqc_good)then
!!!!!!          rig = obsda%ri(nn)
!!!!!!          rjg = obsda%rj(nn)

! -- tentative treatment around the TC center --
!            dist_MSLP_TC = sqrt(((rig - MSLP_TC_rig) * DX)**2&
!                               +((rjg - MSLP_TC_rjg) * DY)**2)

!            if(dist_MSLP_TC <= dist_MSLP_TC_MIN)then
!              obsda%qc(nn) = iqc_obs_bad
!            endif

! -- Rejecting Himawari-8 obs over the buffer regions. --
!            if((rig <= bris) .or. (rig >= brie) .or.&
!               (rjg <= brjs) .or. (rjg >= brje))then
!              obsda%qc(nn) = iqc_obs_bad
!            endif
!          endif

!
!          write(6,'(a,f12.1,i9)')'H08 debug_plev',obsda%lev(nn),nn

!        END DO ! [ nt = 1, nprof_H08vr ]

        !-- 4. Return H(x) to obs variables in the "original" subdomain
        !--    [NOTE]: yobs_H08vr,qc_H08vr have been shared among all subdomains
!org (no longer share among all processes in the loop)            do ns = 1, nprocs_d      ! For subdomain processes
        do nt = 1, slot_nobsg  ! For observations in each subdomain

          nu = tmp_obsgp_H08vr(nt,myrank_d+1)

          if( nu > 0 )then

!org (not need because automatically myrank_d == ns - 1)                if( myrank_d == ns - 1 )then  ! Enter in an MPI rank (ns - 1)
            iof = obsda%set(nu)
            nm = obsda%idx(nu)

            if (.not. USE_OBS(obs(iof)%typ(nm))) then
              cycle
            end if

!orig(2024/01/22)            n = nu
            n = nm

            if (obs(iof)%dif(n) > slot_lb(islot) .and. obs(iof)%dif(n) <= slot_ub(islot)) then

              obsda%val(nu) = yobs_H08vr(nt,myrank_d+1)
              obsda%qc(nu) = qc_H08vr(nt,myrank_d+1)

            end if ! [ obs(iof)%dif(n) > slot_lb(islot) .and. obs(iof)%dif(n) <= slot_ub(islot) ]

!org            end if ! [ myrank_d == ns - 1 ]

          else

            exit

          end if  ! [ nu > 0 ]

        end do  ! [ nt = 1, slot_nobsg ] ! For observations in each subdomain
!org        end do  ! [ ns = 1, nprocs_d ]     ! For subdomain processes

        DEALLOCATE(ri_H08vr,rj_H08vr)
        DEALLOCATE(lon_H08vr,lat_H08vr)
        DEALLOCATE(rad_H08vr)
        DEALLOCATE(lev_H08vr,lev2_H08vr)
        DEALLOCATE(valid_H08vr)

        DEALLOCATE(yobs_H08vr)
        DEALLOCATE(qc_H08vr)

!org          ENDIF  ! [ myrank_e == 0 ]

        deallocate ( tmp_obsdp_H08vr )
        deallocate ( tmp_obsgp_H08vr )

!org              DEALLOCATE(tmp_ri_H08vr,tmp_rj_H08vr)
!org              DEALLOCATE(tmp_lon_H08vr,tmp_lat_H08vr)
!org              DEALLOCATE(tmp_rad_H08vr)
!org              DEALLOCATE(tmp_lev_H08vr,tmp_lev2_H08vr)

          !------
!          end if ! [.not. USE_OBS(23)]
!org            ENDIF  ![ OBS_IN_FORMAT(iof) == obsfmt_h08 ] ! H08VT
          !------

          !=====================================================================

!org          end do ! [ nn = 1, slot_nobs ]

! ###  -- TC vital assimilation -- ###
!          if (obs_idx_TCX > 0 .and. obs_idx_TCY > 0 .and. obs_idx_TCP > 0) then
!          if (obs(iof)%dif(obs_idx_TCX) == obs(iof)%dif(obs_idx_TCY) .and. &
!              obs(iof)%dif(obs_idx_TCY) == obs(iof)%dif(obs_idx_TCP)) then
!           
!            if (obs(iof)%dif(obs_idx_TCX) > slot_lb(islot) .and. &
!              obs(iof)%dif(obs_idx_TCX) <= slot_ub(islot)) then
!              nslot = nslot + 3 ! TC vital obs should have 3 data (i.e., lon, lat, and MSLP)

!              !!! bTC(1,:) : lon, bTC(2,:): lat, bTC(3,:): mslp
!              ! bTC(1,:) : tcx (m), bTC(2,:): tcy (m), bTC(3,:): mslp
!              allocate(bTC(3,0:nprocs_d-1))

!              bTC = 9.99d33

!              ! Note: obs(iof)%dat(obs_idx_TCX) is not longitude (deg) but X (m).
!              !       Units of the original TC vital position are converted in
!              !       subroutine read_obs in common_obs_scale.f90.
!              !
!              call phys2ij(obs(iof)%lon(obs_idx_TCX),obs(iof)%lat(obs_idx_TCX),rig,rjg) 
!              call rij_rank_g2l(rig,rjg,proc,ril,rjl)
!              call search_tc_subdom(rig,rjg,v2dg,bTC(1,myrank_d),bTC(2,myrank_d),bTC(3,myrank_d))
!  
!!              CALL MPI_BARRIER(MPI_COMM_d,ierr)
!              if (nprocs_d > 1) then
!                CALL MPI_ALLREDUCE(MPI_IN_PLACE,bTC,3*nprocs_d,MPI_r_size,MPI_MIN,MPI_COMM_d,ierr)
!              end if

!              ! Assume MSLP of background TC is lower than 1100 (hPa). 
!              bTC_mslp = 1100.0d2
!              do n = 0, nprocs_d - 1
!                write(6,'(3e20.5)')bTC(1,n),bTC(2,n),bTC(3,n) ! debug
!                if (bTC(3,n) < bTC_mslp ) then
!                  bTC_mslp = bTC(3,n)
!                  bTC_proc = n
!                endif
!              enddo ! [ n = 0, nprocs_d - 1]

!              if (myrank_d == proc) then
!                do n = 1, 3
!                  nobs = nobs + 1
!                  nobs_slot = nobs_slot + 1
!                  obsda%set(nobs) = iof
!                  if(n==1) obsda%idx(nobs) = obs_idx_TCX
!                  if(n==2) obsda%idx(nobs) = obs_idx_TCY
!                  if(n==3) obsda%idx(nobs) = obs_idx_TCP
!!!!!!                  obsda%ri(nobs) = rig
!!!!!!                  obsda%rj(nobs) = rjg
!                  ri(nobs) = ril
!                  rj(nobs) = rjl

!                  obsda%val(nobs) = bTC(n,bTC_proc)
!                  obsda%qc(nobs) = iqc_good
!                enddo ! [ n = 1, 3 ]

!              endif
!              deallocate(bTC)

!            endif ! [ obs(iof)%dif(n) > slot_lb(islot) .and. obs(iof)%dif(n) <= slot_ub(islot) ]
!          endif ! [ obs_idx_TCX > 0 ...]
!          endif !


 
        write (timer_str, '(A30,I4,A7,I4,A2)') 'obsope_cal:obsope_step_2   (t=', it, ', slot=', islot, '):'
        call mpi_timer(trim(timer_str), 2)
      end do ! [ islot = SLOT_START, SLOT_END ]

      call mpi_timer('', 2)

      ! Write obsda data to files if OBSDA_OUT = .true.
      ! 
      if (OBSDA_OUT) then
!        write (6,'(A,I6.6,A,I4.4,A,I6.6)') 'MYRANK ',myrank,' is writing observations for member ', &
!              im, ', subdomain id #', myrank_d
        if (im <= MEMBER) then
          obsdafile = OBSDA_OUT_BASENAME
          call filename_replace_mem(obsdafile, im)
        else if (im == mmean) then
          obsdafile = OBSDA_MEAN_OUT_BASENAME
        else if (im == mmdet) then
          obsdafile = OBSDA_MDET_OUT_BASENAME
        end if
        write (obsda_suffix(2:7),'(I6.6)') myrank_d
        write (6,'(A,I6.6,2A)') 'MYRANK ', myrank,' is writing an obsda file ', trim(obsdafile)//obsda_suffix
        call write_obs_da(trim(obsdafile)//obsda_suffix,obsda,0)

        write (timer_str, '(A30,I4,A2)') 'obsope_cal:write_obs_da    (t=', it, '):'
        call mpi_timer(trim(timer_str), 2)
      end if

      ! Prepare variables that will need to be communicated if obsda_return is given
      ! 
      if (present(obsda_return)) then
#ifdef H08
        call obs_da_value_partial_reduce_iter(obsda_return, it, 1, nobs, obsda%val, obsda%qc, obsda%lev, obsda%val2)
#else
        call obs_da_value_partial_reduce_iter(obsda_return, it, 1, nobs, obsda%val, obsda%qc)
#endif

        write (timer_str, '(A30,I4,A2)') 'obsope_cal:partial_reduce  (t=', it, '):'
        call mpi_timer(trim(timer_str), 2)
      end if ! [ present(obsda_return) ]

    end if ! [ (im >= 1 .and. im <= MEMBER) .or. im == mmdetin ]
  end do ! [ it = 1, nitmax ]

  deallocate ( v3dg, v2dg )
  deallocate ( rigu, rigv, rjgu, rjgv )  ! Add by satoki
  deallocate ( bsn, bsna )
  call obs_da_value_deallocate(obsda)

  return
end subroutine obsope_cal
!-----------------------------------------------------------------------
! Observation generator calculation (Checked by satoki)
! Comment by satoki: Replacing obs%dat with observation based on the model variables. 
!-----------------------------------------------------------------------
SUBROUTINE obsmake_cal(obs)
  IMPLICIT NONE

  TYPE(obs_info),INTENT(INOUT) :: obs(OBS_IN_NUM)
  REAL(r_size),ALLOCATABLE :: v3dg(:,:,:,:)
  REAL(r_size),ALLOCATABLE :: v2dg(:,:,:)

  integer :: islot,proc
  integer :: n,nslot,nobs,nobs_slot,ierr,iqc,iof
  integer :: nobsmax,nobsall
  real(r_size) :: rig,rjg,ril,rjl,rk,rkz
  real(r_size) :: slot_lb,slot_ub
  real(r_size),allocatable :: bufr(:)
  real(r_size),allocatable :: error(:)

  CHARACTER(10) :: obsoutfile = 'obsout.dat'
  INTEGER :: ns 
#ifdef H08
! obsmake for H08 is not available !! (03/17/2016) T.Honda
! -- for Himawari-8 obs --
  INTEGER :: nallprofvt ! H08: Num of all profiles (entire domain) required by RTTOV
  INTEGER :: nprof_H08 ! num of H08 obs
  REAL(r_size),ALLOCATABLE :: ril_H08(:),rjl_H08(:)
  REAL(r_size),ALLOCATABLE :: lon_H08(:),lat_H08(:)
  REAL(r_size),ALLOCATABLE :: tmp_ril_H08(:),tmp_rjl_H08(:)
  REAL(r_size),ALLOCATABLE :: tmp_lon_H08(:),tmp_lat_H08(:)

  REAL(r_size),ALLOCATABLE :: yobs_H08(:),plev_obs_H08(:)
  INTEGER,ALLOCATABLE :: qc_H08(:)
  INTEGER,ALLOCATABLE :: idx_H08(:) ! index array
  INTEGER :: ich
#endif

!-----------------------------------------------------------------------

  write (6,'(A,I6.6,A,I6.6)') 'MYRANK ', myrank, ' is processing subdomain id #', myrank_d

  allocate ( v3dg (nlevh,nlonh,nlath,nv3dd) )
  allocate ( v2dg (nlonh,nlath,nv2dd) )

  do iof = 1, OBS_IN_NUM
    obs(iof)%dat = 0.0d0
  end do

  nobs = 0
  do islot = SLOT_START, SLOT_END
    slot_lb = (real(islot-SLOT_BASE,r_size) - 0.5d0) * SLOT_TINTERVAL
    slot_ub = (real(islot-SLOT_BASE,r_size) + 0.5d0) * SLOT_TINTERVAL
    write (6,'(A,I3,A,F9.1,A,F9.1,A)') 'Slot #', islot-SLOT_START+1, ': time window (', slot_lb, ',', slot_ub, '] sec'

    call read_ens_history_iter(1,islot,v3dg,v2dg)

    do iof = 1, OBS_IN_NUM
      IF(OBS_IN_FORMAT(iof) /= obsfmt_h08)THEN ! except H08 obs
        nslot = 0
        nobs_slot = 0
        do n = 1, obs(iof)%nobs

          if (obs(iof)%dif(n) > slot_lb .and. obs(iof)%dif(n) <= slot_ub) then
            nslot = nslot + 1

            call phys2ij(obs(iof)%lon(n),obs(iof)%lat(n),rig,rjg)
            call rij_rank_g2l(rig,rjg,proc,ril,rjl)

  !          if (myrank_d == 0) then
  !            print *, proc, rig, rjg, ril, rjl
  !          end if

            if (proc < 0 .and. myrank_d == 0) then ! if outside of the global domain, processed by myrank_d == 0
              obs(iof)%dat(n) = undef
            end if

            if (myrank_d == proc) then
              nobs = nobs + 1
              nobs_slot = nobs_slot + 1

  !IF(NINT(elem(n)) == id_ps_obs) THEN
  !  CALL itpl_2d(v2d(:,:,iv2d_orog),ril,rjl,dz)
  !  rk = rlev(n) - dz
  !  IF(ABS(rk) > threshold_dz) THEN ! pressure adjustment threshold
  !    ! WRITE(6,'(A)') '* PS obs vertical adjustment beyond threshold'
  !    ! WRITE(6,'(A,F10.2,A,F6.2,A,F6.2,A)') '* dz=',rk,&
  !    ! & ', (lon,lat)=(',elon(n),',',elat(n),')'
  !    CYCLE
  !  END IF
  !END IF

              select case (OBS_IN_FORMAT(iof))
              !=================================================================
              case (obsfmt_prepbufr)
              !-----------------------------------------------------------------
                !-- OBS_IN_FORMAT = 'PREPBUF' & obs%elm = id_{u,v}_obs & obs%typ = 'SATWND' (4)
                !--  -> obs%lev = [m] (add by satoki for satellite AMV H08UV)
                if(((obs(iof)%elm(n)==id_u_obs).or.(obs(iof)%elm(n)==id_v_obs)).and. &
  &               obs(iof)%typ(n)==4)then
                  call phys2ijkz(v3dg(:,:,:,iv3dd_hgt),ril,rjl,obs(iof)%lev(n),rk,iqc)
                else  ! below is original code (by satoki)
                  call phys2ijk(v3dg(:,:,:,iv3dd_p),obs(iof)%elm(n),ril,rjl,obs(iof)%lev(n),rk,iqc)
                end if
                if (iqc == iqc_good) then
                  call Trans_XtoY(obs(iof)%elm(n),ril,rjl,rk, &
                                  obs(iof)%lon(n),obs(iof)%lat(n),v3dg,v2dg,obs(iof)%dat(n),iqc)
                end if
              !=================================================================
              case (obsfmt_radar)
              !-----------------------------------------------------------------
                call phys2ijkz(v3dg(:,:,:,iv3dd_hgt),ril,rjl,obs(iof)%lev(n),rkz,iqc)
                if (iqc == iqc_good) then
                  call Trans_XtoY_radar(obs(iof)%elm(n),obs(iof)%meta(1),obs(iof)%meta(2),obs(iof)%meta(3),ril,rjl,rkz, &
                                        obs(iof)%lon(n),obs(iof)%lat(n),obs(iof)%lev(n),v3dg,v2dg,obs(iof)%dat(n),iqc)
 !!! For radar observation, when reflectivity value is too low, do not generate ref/vr observations
 !!! No consideration of the terrain blocking effects.....
                end if
#ifdef H08
              !=================================================================
!              case (obsfmt_h08)
              !-----------------------------------------------------------------

#endif
              !=================================================================
              end select

              if (iqc /= iqc_good) then
                obs(iof)%dat(n) = undef
              end if

            end if ! [ myrank_d == proc ]

          end if ! [ obs%dif(n) > slot_lb .and. obs%dif(n) <= slot_ub ]

        end do ! [ n = 1, obs%nobs ]

#ifdef H08
! -- H08 part --
      ELSEIF(OBS_IN_FORMAT(iof) == obsfmt_h08)THEN ! H08
        nslot = 0
        nobs_slot = 0
        nprof_H08 = 0

        nallprofvt = obs(iof)%nobs/nch

        ALLOCATE(tmp_ril_H08(nallprofvt))
        ALLOCATE(tmp_rjl_H08(nallprofvt))
        ALLOCATE(tmp_lon_H08(nallprofvt))
        ALLOCATE(tmp_lat_H08(nallprofvt))
        ALLOCATE(idx_H08(nallprofvt))

        do n = 1, nallprofvt
          ns = (n - 1) * nch + 1
          if (obs(iof)%dif(n) > slot_lb .and. obs(iof)%dif(n) <= slot_ub) then
            nslot = nslot + 1

            call phys2ij(obs(iof)%lon(ns),obs(iof)%lat(ns),rig,rjg)
            call rij_rank_g2l(rig,rjg,proc,ril,rjl)


            if (proc < 0 .and. myrank_d == 0) then ! if outside of the global domain, processed by myrank_d == 0
              obs(iof)%dat(ns:ns+nch-1) = undef
            end if

            if (myrank_d == proc) then
              nprof_H08 = nprof_H08 + 1 ! num of prof in myrank node
              idx_H08(nprof_H08) = ns ! idx of prof in myrank node
              tmp_ril_H08(nprof_H08) = ril
              tmp_rjl_H08(nprof_H08) = rjl
              tmp_lon_H08(nprof_H08) = obs(iof)%lon(ns)
              tmp_lat_H08(nprof_H08) = obs(iof)%lat(ns)

              nobs = nobs + nch
              nobs_slot = nobs_slot + nch

            end if ! [ myrank_d == proc ]

          end if ! [ obs%dif(n) > slot_lb .and. obs%dif(n) <= slot_ub ]

        end do ! [ n = 1, nallprofvt ]

        IF(nprof_H08 >=1)THEN
          ALLOCATE(ril_H08(nprof_H08))
          ALLOCATE(rjl_H08(nprof_H08))
          ALLOCATE(lon_H08(nprof_H08))
          ALLOCATE(lat_H08(nprof_H08))

          ril_H08 = tmp_ril_H08(1:nprof_H08)
          rjl_H08 = tmp_rjl_H08(1:nprof_H08)
          lon_H08 = tmp_lon_H08(1:nprof_H08)
          lat_H08 = tmp_lat_H08(1:nprof_H08)

          ALLOCATE(yobs_H08(nprof_H08*nch))
          ALLOCATE(plev_obs_H08(nprof_H08*nch))
          ALLOCATE(qc_H08(nprof_H08*nch))

          CALL Trans_XtoY_H08(nprof_H08,ril_H08,rjl_H08,&
                              lon_H08,lat_H08,v3dg,v2dg,&
                              yobs_H08,plev_obs_H08,&
                              qc_H08)

          DO n = 1, nprof_H08
            ns = idx_H08(n)

            obs(iof)%lon(ns:ns+nch-1)=lon_H08(n:n+nch-1)
            obs(iof)%lat(ns:ns+nch-1)=lat_H08(n:n+nch-1)

            DO ich = 1, nch-1
              IF(qc_H08(n+ich-1) == iqc_good)THEN
                obs(iof)%dat(ns+ich-1)=undef
              ELSE
                obs(iof)%dat(ns+ich-1)=yobs_H08(n+ich-1)
              ENDIF
            ENDDO
          ENDDO

        ENDIF

        DEALLOCATE(tmp_ril_H08,tmp_rjl_H08)
        DEALLOCATE(tmp_lon_H08,tmp_lat_H08)


! -- end of H08 part --
#endif
      ENDIF

    end do ! [ iof = 1, OBS_IN_NUM ]

    write (6,'(3A,I10)') ' -- [', trim(OBS_IN_NAME(iof)), '] nobs in the slot = ', nslot
    write (6,'(3A,I6,A,I10)') ' -- [', trim(OBS_IN_NAME(iof)), '] nobs in the slot and processed by rank ', myrank, ' = ', nobs_slot

  end do ! [ islot = SLOT_START, SLOT_END ]

  deallocate ( v3dg, v2dg )

  if (myrank_d == 0) then
    nobsmax = 0
    nobsall = 0
    do iof = 1, OBS_IN_NUM
      if (obs(iof)%nobs > nobsmax) nobsmax = obs(iof)%nobs
      nobsall = nobsall + obs(iof)%nobs
    end do

    allocate ( bufr(nobsmax) )
    allocate ( error(nobsall) )

    !-- Comment by satoki: このルーチンがどこにも見当たらない (intrinsic?).
    call com_randn(nobsall, error) ! generate all random numbers at the same time
    ns = 0
  end if

  do iof = 1, OBS_IN_NUM

    call MPI_REDUCE(obs(iof)%dat,bufr(1:obs(iof)%nobs),obs(iof)%nobs,MPI_r_size,MPI_SUM,0,MPI_COMM_d,ierr)

    if (myrank_d == 0) then
      obs(iof)%dat = bufr(1:obs(iof)%nobs)

      do n = 1, obs(iof)%nobs
        select case(obs(iof)%elm(n))
        case(id_u_obs)
          obs(iof)%err(n) = OBSERR_U
        case(id_v_obs)
          obs(iof)%err(n) = OBSERR_V
        case(id_t_obs,id_tv_obs)
          obs(iof)%err(n) = OBSERR_T
        case(id_q_obs)
          obs(iof)%err(n) = OBSERR_Q
        case(id_rh_obs)
          obs(iof)%err(n) = OBSERR_RH
        case(id_ps_obs)
          obs(iof)%err(n) = OBSERR_PS
        case(id_radar_ref_obs,id_radar_ref_zero_obs)
          obs(iof)%err(n) = OBSERR_RADAR_REF
        case(id_radar_vr_obs)
          obs(iof)%err(n) = OBSERR_RADAR_VR
!
! -- Not available (02/09/2015)
!        case(id_H08IR_obs) ! H08
!          obs(iof)%err(n) = OBSERR_H08(ch) !H08
!        case default
          write(6,'(A)') '[Warning] skip assigning observation error (unsupported observation type)'
        end select

        if (obs(iof)%dat(n) /= undef .and. obs(iof)%err(n) /= undef) then
          obs(iof)%dat(n) = obs(iof)%dat(n) + obs(iof)%err(n) * error(ns+n)
        end if

!print *, '######', obs%elm(n), obs%dat(n)
      end do ! [ n = 1, obs(iof)%nobs ]

      ns = ns + obs(iof)%nobs
    end if ! [ myrank_d == 0 ]

  end do ! [ iof = 1, OBS_IN_NUM ]

  if (myrank_d == 0) then
    deallocate ( bufr )
    deallocate ( error )

    call write_obs_all(obs, missing=.false., file_suffix='.out') ! only at the head node
  end if

end subroutine obsmake_cal

!-------------------------------------------------------------------------------
! Model-to-observation simulator calculation (Checked by satoki)
!-------------------------------------------------------------------------------
subroutine obssim_cal(v3dgh, v2dgh, v3dgsim, v2dgsim, stggrd)
  use scale_grid, only: &
      GRID_CX, GRID_CY, &
      DX, DY
  use scale_grid_index, only: &
      IHALO, JHALO, KHALO
  use scale_mapproj, only: &
      MPRJ_xy2lonlat

  implicit none

  real(r_size), intent(in) :: v3dgh(nlevh,nlonh,nlath,nv3dd)
  real(r_size), intent(in) :: v2dgh(nlonh,nlath,nv2dd)
  real(r_size), intent(out) :: v3dgsim(nlev,nlon,nlat,OBSSIM_NUM_3D_VARS)
  real(r_size), intent(out) :: v2dgsim(nlon,nlat,OBSSIM_NUM_2D_VARS)
  integer, intent(in), optional :: stggrd

  integer :: i, j, k, iv3dsim, iv2dsim
  real(r_size) :: ri, rj, rk
  real(r_size) :: lon, lat, lev
  real(r_size) :: tmpobs
  integer :: tmpqc

!-------------------------------------------------------------------------------

  write (6,'(A,I6.6,A,I6.6)') 'MYRANK ', myrank, ' is processing subdomain id #', myrank_d

  do j = 1, nlat
    rj = real(j + JHALO, r_size)

    do i = 1, nlon
      ri = real(i + IHALO, r_size)
      call MPRJ_xy2lonlat((ri-1.0_r_size) * DX + GRID_CX(1), (rj-1.0_r_size) * DY + GRID_CY(1), lon, lat)
      lon = lon * rad2deg
      lat = lat * rad2deg

      do k = 1, nlev
        rk = real(k + KHALO, r_size)

        do iv3dsim = 1, OBSSIM_NUM_3D_VARS
          select case (OBSSIM_3D_VARS_LIST(iv3dsim))
          case (id_radar_ref_obs, id_radar_ref_zero_obs, id_radar_vr_obs, id_radar_prh_obs)
            lev = v3dgh(k+KHALO, i+IHALO, j+JHALO, iv3dd_hgt)
            call Trans_XtoY_radar(OBSSIM_3D_VARS_LIST(iv3dsim), OBSSIM_RADAR_LON, OBSSIM_RADAR_LAT, OBSSIM_RADAR_Z, ri, rj, rk, &
                                  lon, lat, lev, v3dgh, v2dgh, tmpobs, tmpqc, stggrd)
            if (tmpqc == iqc_ref_low) tmpqc = iqc_good ! when process the observation operator, we don't care if reflectivity is too small
          case default
            call Trans_XtoY(OBSSIM_3D_VARS_LIST(iv3dsim), ri, rj, rk, &
                            lon, lat, v3dgh, v2dgh, tmpobs, tmpqc, stggrd)
          end select

          if (tmpqc == 0) then
            v3dgsim(k,i,j,iv3dsim) = real(tmpobs, r_sngl)
          else
            v3dgsim(k,i,j,iv3dsim) = real(undef, r_sngl)
          end if
        end do ! [ iv3dsim = 1, OBSSIM_NUM_3D_VARS ]

        ! 2D observations calculated when k = 1
        if (k == 1) then
          do iv2dsim = 1, OBSSIM_NUM_2D_VARS
            select case (OBSSIM_2D_VARS_LIST(iv2dsim))
!            case (id_H08IR_obs)               !!!!!! H08 as 2D observations ???
!              call Trans_XtoY_radar_H08(...)
!            case (id_tclon_obs, id_tclat_obs, id_tcmip_obs)
!              call ...
            case default
              call Trans_XtoY(OBSSIM_2D_VARS_LIST(iv2dsim), ri, rj, rk, &
                              lon, lat, v3dgh, v2dgh, tmpobs, tmpqc, stggrd)
            end select

            if (tmpqc == 0) then
              v2dgsim(i,j,iv2dsim) = real(tmpobs, r_sngl)
            else
              v2dgsim(i,j,iv2dsim) = real(undef, r_sngl)
            end if
          end do ! [ iv2dsim = 1, OBSSIM_NUM_2D_VARS ]
        end if ! [ k == 1 ]

      end do ! [ k = 1, nlev ]

    end do ! [ i = 1, nlon ]

  end do ! [ j = 1, nlat ]

!-------------------------------------------------------------------------------

end subroutine obssim_cal

!!!!!! it is not good to open/close a file many times for different steps !!!!!!
!-------------------------------------------------------------------------------
! Write the subdomain model data into a single GrADS file (Checked by satoki)
!-------------------------------------------------------------------------------
subroutine write_grd_mpi(filename, nv3dgrd, nv2dgrd, step, v3d, v2d)
  implicit none
  character(*), intent(in) :: filename
  integer, intent(in) :: nv3dgrd
  integer, intent(in) :: nv2dgrd
  integer, intent(in) :: step
  real(r_size), intent(in) :: v3d(nlev,nlon,nlat,nv3dgrd)
  real(r_size), intent(in) :: v2d(nlon,nlat,nv2dgrd)

  real(r_sngl) :: bufs4(nlong,nlatg)
  real(r_sngl) :: bufr4(nlong,nlatg)
  integer :: iunit, iolen
  integer :: k, n, irec, ierr
  integer :: proc_i, proc_j
  integer :: ishift, jshift

  call rank_1d_2d(myrank_d, proc_i, proc_j)
  ishift = proc_i * nlon
  jshift = proc_j * nlat

  if (myrank_d == 0) then
    iunit = 55
    inquire (iolength=iolen) iolen
    open (iunit, file=trim(filename), form='unformatted', access='direct', &
          status='unknown', convert='native', recl=nlong*nlatg*iolen)
    irec = (nlev * nv3dgrd + nv2dgrd) * (step-1)
  end if

  do n = 1, nv3dgrd
    do k = 1, nlev
      bufs4(:,:) = 0.0
      bufs4(1+ishift:nlon+ishift, 1+jshift:nlat+jshift) = real(v3d(k,:,:,n), r_sngl)
      call MPI_REDUCE(bufs4, bufr4, nlong*nlatg, MPI_REAL, MPI_SUM, 0, MPI_COMM_d, ierr)
      if (myrank_d == 0) then
        irec = irec + 1
        write (iunit, rec=irec) bufr4
      end if
    end do
  end do

  do n = 1, nv2dgrd
    bufs4(:,:) = 0.0
    bufs4(1+ishift:nlon+ishift, 1+jshift:nlat+jshift) = real(v2d(:,:,n), r_sngl)
    call MPI_REDUCE(bufs4, bufr4, nlong*nlatg, MPI_REAL, MPI_SUM, 0, MPI_COMM_d, ierr)
    if (myrank_d == 0) then
      irec = irec + 1
      write (iunit, rec=irec) bufr4
    end if
  end do

  if (myrank_d == 0) then
    close (iunit)
  end if

  return
end subroutine write_grd_mpi

!=======================================================================

END MODULE obsope_tools
