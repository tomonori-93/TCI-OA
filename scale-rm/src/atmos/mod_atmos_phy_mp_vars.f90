!-------------------------------------------------------------------------------
!> module Atmosphere / Physics Cloud Microphysics
!!
!! @par Description
!!          Container for mod_atmos_phy_mp
!!
!! @author Team SCALE
!!
!! @par History
!! @li      2014-05-04 (H.Yashiro)    [new]
!! @li      2015-09-08 (Y.Sato)       [add] Add ATMOS_PHY_MP_EVAPORATE
!<
!-------------------------------------------------------------------------------
#include "inc_openmp.h"
module mod_atmos_phy_mp_vars
  !-----------------------------------------------------------------------------
  !
  !++ used modules
  !
  use scale_precision
  use scale_stdio
  use scale_prof
  use scale_grid_index
  use scale_tracer
  !-----------------------------------------------------------------------------
  implicit none
  private
  !-----------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: ATMOS_PHY_MP_vars_setup
  public :: ATMOS_PHY_MP_vars_fillhalo
  public :: ATMOS_PHY_MP_vars_restart_read
  public :: ATMOS_PHY_MP_vars_restart_write

  public :: ATMOS_PHY_MP_vars_restart_create_add  ! add by satoki
  public :: ATMOS_PHY_MP_vars_restart_create
  public :: ATMOS_PHY_MP_vars_restart_open
  public :: ATMOS_PHY_MP_vars_restart_def_var
  public :: ATMOS_PHY_MP_vars_restart_enddef
  public :: ATMOS_PHY_MP_vars_restart_close

  !-----------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  logical,               public :: ATMOS_PHY_MP_RESTART_OUTPUT                = .false.                !< output restart file?

  character(len=H_LONG),  public :: ATMOS_PHY_MP_RESTART_IN_BASENAME           = ''                     !< Basename of the input  file
  logical,                public :: ATMOS_PHY_MP_RESTART_IN_POSTFIX_TIMELABEL  = .false.                !< Add timelabel to the basename of input  file?
  character(len=H_LONG),  public :: ATMOS_PHY_MP_RESTART_OUT_BASENAME          = ''                     !< Basename of the output file
  logical,                public :: ATMOS_PHY_MP_RESTART_OUT_POSTFIX_TIMELABEL = .true.                 !< Add timelabel to the basename of output file?
  character(len=H_MID),   public :: ATMOS_PHY_MP_RESTART_OUT_TITLE             = 'ATMOS_PHY_MP restart' !< title    of the output file
  character(len=H_SHORT), public :: ATMOS_PHY_MP_RESTART_OUT_DTYPE             = 'DEFAULT'              !< REAL4 or REAL8

  real(RP), public, allocatable :: ATMOS_PHY_MP_DENS_t(:,:,:)    ! tendency DENS [kg/m3/s]
  real(RP), public, allocatable :: ATMOS_PHY_MP_MOMZ_t(:,:,:)    ! tendency MOMZ [kg/m2/s2]
  real(RP), public, allocatable :: ATMOS_PHY_MP_MOMX_t(:,:,:)    ! tendency MOMX [kg/m2/s2]
  real(RP), public, allocatable :: ATMOS_PHY_MP_MOMY_t(:,:,:)    ! tendency MOMY [kg/m2/s2]
  real(RP), public, allocatable :: ATMOS_PHY_MP_RHOT_t(:,:,:)    ! tendency RHOT [K*kg/m3/s]
  real(RP), public, allocatable :: ATMOS_PHY_MP_RHOQ_t(:,:,:,:)  ! tendency rho*QTRC [kg/kg/s]

  real(RP), public, allocatable :: ATMOS_PHY_MP_EVAPORATE(:,:,:) ! number concentration of evaporated cloud [/m3]
  real(RP), public, allocatable :: ATMOS_PHY_MP_SFLX_rain(:,:)   ! precipitation flux (liquid) [kg/m2/s]
  real(RP), public, allocatable :: ATMOS_PHY_MP_SFLX_snow(:,:)   ! precipitation flux (solid)  [kg/m2/s]

  !-----------------------------------------------------------------------------
  !
  !++ Private procedure
  !
  !-----------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  integer,                private, parameter :: VMAX = 2       !< number of the variables
  integer,                private, parameter :: I_SFLX_rain = 1
  integer,                private, parameter :: I_SFLX_snow = 2

  character(len=H_SHORT), private            :: VAR_NAME(VMAX) !< name  of the variables
  character(len=H_MID),   private            :: VAR_DESC(VMAX) !< desc. of the variables
  character(len=H_SHORT), private            :: VAR_UNIT(VMAX) !< unit  of the variables
  integer,                private            :: VAR_ID(VMAX)   !< ID    of the variables
  integer,                private            :: restart_fid = -1  ! file ID

  data VAR_NAME / 'SFLX_rain', &
                  'SFLX_snow'  /
  data VAR_DESC / 'precipitation flux (liquid)', &
                  'precipitation flux (solid)'   /
  data VAR_UNIT / 'kg/m2/s', &
                  'kg/m2/s' /

  !-----------------------------------------------------------------------------
contains
  !-----------------------------------------------------------------------------
  !> Setup
  subroutine ATMOS_PHY_MP_vars_setup
    use scale_process, only: &
       PRC_MPIstop
    use scale_const, only: &
       UNDEF => CONST_UNDEF
    use scale_atmos_phy_mp, only: &
       QS_MP, &
       QE_MP
    implicit none

    NAMELIST / PARAM_ATMOS_PHY_MP_VARS / &
       ATMOS_PHY_MP_RESTART_IN_BASENAME,           &
       ATMOS_PHY_MP_RESTART_IN_POSTFIX_TIMELABEL,  &
       ATMOS_PHY_MP_RESTART_OUTPUT,                &
       ATMOS_PHY_MP_RESTART_OUT_BASENAME,          &
       ATMOS_PHY_MP_RESTART_OUT_POSTFIX_TIMELABEL, &
       ATMOS_PHY_MP_RESTART_OUT_TITLE,             &
       ATMOS_PHY_MP_RESTART_OUT_DTYPE

    integer :: ierr
    integer :: iv
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '++++++ Module[VARS] / Categ[ATMOS PHY_MP] / Origin[SCALE-RM]'

    allocate( ATMOS_PHY_MP_DENS_t(KA,IA,JA)    )
    allocate( ATMOS_PHY_MP_MOMZ_t(KA,IA,JA)    )
    allocate( ATMOS_PHY_MP_MOMX_t(KA,IA,JA)    )
    allocate( ATMOS_PHY_MP_MOMY_t(KA,IA,JA)    )
    allocate( ATMOS_PHY_MP_RHOT_t(KA,IA,JA)    )
    allocate( ATMOS_PHY_MP_RHOQ_t(KA,IA,JA,QS_MP:QE_MP) )
    allocate( ATMOS_PHY_MP_EVAPORATE(KA,IA,JA)    )
    ! tentative approach
    ATMOS_PHY_MP_DENS_t(:,:,:)   = 0.0_RP
    ATMOS_PHY_MP_MOMZ_t(:,:,:)   = 0.0_RP
    ATMOS_PHY_MP_MOMX_t(:,:,:)   = 0.0_RP
    ATMOS_PHY_MP_MOMY_t(:,:,:)   = 0.0_RP
    ATMOS_PHY_MP_RHOT_t(:,:,:)   = 0.0_RP
    ATMOS_PHY_MP_RHOQ_t(:,:,:,:) = 0.0_RP
    ATMOS_PHY_MP_EVAPORATE(:,:,:) = 0.0_RP

    allocate( ATMOS_PHY_MP_SFLX_rain(IA,JA) )
    allocate( ATMOS_PHY_MP_SFLX_snow(IA,JA) )
    ATMOS_PHY_MP_SFLX_rain(:,:) = UNDEF
    ATMOS_PHY_MP_SFLX_snow(:,:) = UNDEF

    !--- read namelist
    rewind(IO_FID_CONF)
    read(IO_FID_CONF,nml=PARAM_ATMOS_PHY_MP_VARS,iostat=ierr)
    if( ierr < 0 ) then !--- missing
       if( IO_L ) write(IO_FID_LOG,*) '*** Not found namelist. Default used.'
    elseif( ierr > 0 ) then !--- fatal error
       write(*,*) 'xxx Not appropriate names in namelist PARAM_ATMOS_PHY_MP_VARS. Check!'
       call PRC_MPIstop
    endif
    if( IO_NML ) write(IO_FID_NML,nml=PARAM_ATMOS_PHY_MP_VARS)

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '*** [ATMOS_PHY_MP] prognostic/diagnostic variables'
    if( IO_L ) write(IO_FID_LOG,'(1x,A,A24,A,A48,A,A12,A)') &
               '***       |', 'VARNAME                 ','|', &
               'DESCRIPTION                                     ', '[', 'UNIT        ', ']'
    do iv = 1, VMAX
       if( IO_L ) write(IO_FID_LOG,'(1x,A,I3,A,A24,A,A48,A,A12,A)') &
                  '*** NO.',iv,'|',VAR_NAME(iv),'|',VAR_DESC(iv),'[',VAR_UNIT(iv),']'
    enddo

    if( IO_L ) write(IO_FID_LOG,*)
    if ( ATMOS_PHY_MP_RESTART_IN_BASENAME /= '' ) then
       if( IO_L ) write(IO_FID_LOG,*) '*** Restart input?  : YES, file = ', trim(ATMOS_PHY_MP_RESTART_IN_BASENAME)
       if( IO_L ) write(IO_FID_LOG,*) '*** Add timelabel?  : ', ATMOS_PHY_MP_RESTART_IN_POSTFIX_TIMELABEL
    else
       if( IO_L ) write(IO_FID_LOG,*) '*** Restart input?  : NO'
    endif
    if (       ATMOS_PHY_MP_RESTART_OUTPUT             &
         .AND. ATMOS_PHY_MP_RESTART_OUT_BASENAME /= '' ) then
       if( IO_L ) write(IO_FID_LOG,*) '*** Restart output? : YES, file = ', trim(ATMOS_PHY_MP_RESTART_OUT_BASENAME)
       if( IO_L ) write(IO_FID_LOG,*) '*** Add timelabel?  : ', ATMOS_PHY_MP_RESTART_OUT_POSTFIX_TIMELABEL
    else
       if( IO_L ) write(IO_FID_LOG,*) '*** Restart output? : NO'
       ATMOS_PHY_MP_RESTART_OUTPUT = .false.
    endif

    return
  end subroutine ATMOS_PHY_MP_vars_setup

  !-----------------------------------------------------------------------------
  !> HALO Communication
  subroutine ATMOS_PHY_MP_vars_fillhalo
    use scale_comm, only: &
       COMM_vars8, &
       COMM_wait
    implicit none
    !---------------------------------------------------------------------------

    call COMM_vars8( ATMOS_PHY_MP_SFLX_rain(:,:), 1 )
    call COMM_vars8( ATMOS_PHY_MP_SFLX_snow(:,:), 2 )
    call COMM_wait ( ATMOS_PHY_MP_SFLX_rain(:,:), 1 )
    call COMM_wait ( ATMOS_PHY_MP_SFLX_snow(:,:), 2 )

    return
  end subroutine ATMOS_PHY_MP_vars_fillhalo

  !-----------------------------------------------------------------------------
  !> Open restart file for read
  subroutine ATMOS_PHY_MP_vars_restart_open
    use scale_time, only: &
       TIME_gettimelabel
    use scale_fileio, only: &
       FILEIO_open
    implicit none

    character(len=19)     :: timelabel
    character(len=H_LONG) :: basename
    !---------------------------------------------------------------------------

    if( IO_L ) write(IO_FID_LOG,*)
    if( IO_L ) write(IO_FID_LOG,*) '*** Open restart file (ATMOS_PHY_MP) ***'

    if ( ATMOS_PHY_MP_RESTART_IN_BASENAME /= '' ) then

       if ( ATMOS_PHY_MP_RESTART_IN_POSTFIX_TIMELABEL ) then
          call TIME_gettimelabel( timelabel )
          basename = trim(ATMOS_PHY_MP_RESTART_IN_BASENAME)//'_'//trim(timelabel)
       else
          basename = trim(ATMOS_PHY_MP_RESTART_IN_BASENAME)
       endif

       if( IO_L ) write(IO_FID_LOG,*) '*** basename: ', trim(basename)

       call FILEIO_open( restart_fid, basename )
    else
       if( IO_L ) write(IO_FID_LOG,*) '*** restart file for ATMOS_PHY_MP is not specified.'
    endif

    return
  end subroutine ATMOS_PHY_MP_vars_restart_open

  !-----------------------------------------------------------------------------
  !> Read restart
  subroutine ATMOS_PHY_MP_vars_restart_read
    use scale_rm_statistics, only: &
       STATISTICS_checktotal, &
       STAT_total
    use scale_fileio, only: &
       FILEIO_read, &
       FILEIO_flush
    implicit none

    real(RP) :: total
    !---------------------------------------------------------------------------

    if ( restart_fid /= -1 ) then
       if( IO_L ) write(IO_FID_LOG,*)
       if( IO_L ) write(IO_FID_LOG,*) '*** Read from restart file (ATMOS_PHY_MP) ***'

       call FILEIO_read( ATMOS_PHY_MP_SFLX_rain(:,:),             & ! [OUT]
                         restart_fid, VAR_NAME(1), 'XY', step=1 ) ! [IN]
       call FILEIO_read( ATMOS_PHY_MP_SFLX_snow(:,:),             & ! [OUT]
                         restart_fid, VAR_NAME(2), 'XY', step=1 ) ! [IN]

       if ( IO_AGGREGATE ) then
          call FILEIO_flush( restart_fid ) ! X/Y halos have been read from file
       else
          call ATMOS_PHY_MP_vars_fillhalo
       end if

       if ( STATISTICS_checktotal ) then
          call STAT_total( total, ATMOS_PHY_MP_SFLX_rain(:,:), VAR_NAME(1) )
          call STAT_total( total, ATMOS_PHY_MP_SFLX_snow(:,:), VAR_NAME(2) )
       endif
    else
       if( IO_L ) write(IO_FID_LOG,*) '*** invalid restart file ID for ATMOS_PHY_MP.'
    endif

    return
  end subroutine ATMOS_PHY_MP_vars_restart_read

  !-----------------------------------------------------------------------------
  !> Create restart file
  !-- New routine by satoki
  subroutine ATMOS_PHY_MP_vars_restart_create_add( addfname )
    use scale_time, only: &
       TIME_gettimelabel
    use scale_fileio, only: &
       FILEIO_create
    implicit none

    character(len=H_LONG), intent(in) :: addfname
    character(len=19)     :: timelabel
    character(len=H_LONG) :: basename
    !---------------------------------------------------------------------------

    if ( addfname /= '' ) then

       if( IO_L ) write(IO_FID_LOG,*)
       if( IO_L ) write(IO_FID_LOG,*) '*** Create restart file (ATMOS_PHY_AE) ***'

       if ( ATMOS_PHY_MP_RESTART_OUT_POSTFIX_TIMELABEL ) then
          call TIME_gettimelabel( timelabel )
          basename = trim(addfname)//'_'//trim(timelabel)
       else
          basename = trim(addfname)
       endif

       if( IO_L ) write(IO_FID_LOG,*) '*** basename: ', trim(basename)

       call FILEIO_create( restart_fid,                                                             & ! [OUT]
                           basename, ATMOS_PHY_MP_RESTART_OUT_TITLE, ATMOS_PHY_MP_RESTART_OUT_DTYPE ) ! [IN]

    endif

    return
  end subroutine ATMOS_PHY_MP_vars_restart_create_add

  !-----------------------------------------------------------------------------
  !> Create restart file
  subroutine ATMOS_PHY_MP_vars_restart_create
    use scale_time, only: &
       TIME_gettimelabel
    use scale_fileio, only: &
       FILEIO_create
    implicit none

    character(len=19)     :: timelabel
    character(len=H_LONG) :: basename
    !---------------------------------------------------------------------------

    if ( ATMOS_PHY_MP_RESTART_OUT_BASENAME /= '' ) then

       if( IO_L ) write(IO_FID_LOG,*)
       if( IO_L ) write(IO_FID_LOG,*) '*** Create restart file (ATMOS_PHY_AE) ***'

       if ( ATMOS_PHY_MP_RESTART_OUT_POSTFIX_TIMELABEL ) then
          call TIME_gettimelabel( timelabel )
          basename = trim(ATMOS_PHY_MP_RESTART_OUT_BASENAME)//'_'//trim(timelabel)
       else
          basename = trim(ATMOS_PHY_MP_RESTART_OUT_BASENAME)
       endif

       if( IO_L ) write(IO_FID_LOG,*) '*** basename: ', trim(basename)

       call FILEIO_create( restart_fid,                                                             & ! [OUT]
                           basename, ATMOS_PHY_MP_RESTART_OUT_TITLE, ATMOS_PHY_MP_RESTART_OUT_DTYPE ) ! [IN]

    endif

    return
  end subroutine ATMOS_PHY_MP_vars_restart_create

  !-----------------------------------------------------------------------------
  !> Exit netCDF define mode
  subroutine ATMOS_PHY_MP_vars_restart_enddef
    use scale_fileio, only: &
       FILEIO_enddef
    implicit none

    if ( restart_fid /= -1 ) then
       call FILEIO_enddef( restart_fid ) ! [IN]
    endif

    return
  end subroutine ATMOS_PHY_MP_vars_restart_enddef

  !-----------------------------------------------------------------------------
  !> Close restart file
  subroutine ATMOS_PHY_MP_vars_restart_close
    use scale_fileio, only: &
       FILEIO_close
    implicit none
    !---------------------------------------------------------------------------

    if ( restart_fid /= -1 ) then
       if( IO_L ) write(IO_FID_LOG,*)
       if( IO_L ) write(IO_FID_LOG,*) '*** Close restart file (ATMOS_PHY_MP) ***'

       call FILEIO_close( restart_fid ) ! [IN]

       restart_fid = -1
    endif

    return
  end subroutine ATMOS_PHY_MP_vars_restart_close

  !-----------------------------------------------------------------------------
  !> Define variables in restart file
  subroutine ATMOS_PHY_MP_vars_restart_def_var
    use scale_fileio, only: &
       FILEIO_def_var
    implicit none
    !---------------------------------------------------------------------------

    if ( restart_fid /= -1 ) then

       call FILEIO_def_var( restart_fid, VAR_ID(1), VAR_NAME(1), VAR_DESC(1), &
                            VAR_UNIT(1), 'XY', ATMOS_PHY_MP_RESTART_OUT_DTYPE  ) ! [IN]
       call FILEIO_def_var( restart_fid, VAR_ID(2), VAR_NAME(2), VAR_DESC(2), &
                            VAR_UNIT(2), 'XY', ATMOS_PHY_MP_RESTART_OUT_DTYPE  ) ! [IN]

    endif

    return
  end subroutine ATMOS_PHY_MP_vars_restart_def_var

  !-----------------------------------------------------------------------------
  !> Write restart
  subroutine ATMOS_PHY_MP_vars_restart_write
    use scale_rm_statistics, only: &
       STATISTICS_checktotal, &
       STAT_total
    use scale_fileio, only: &
       FILEIO_write_var
    implicit none

    real(RP) :: total
    !---------------------------------------------------------------------------

    if ( restart_fid /= -1 ) then

       call ATMOS_PHY_MP_vars_fillhalo

       if ( STATISTICS_checktotal ) then
          call STAT_total( total, ATMOS_PHY_MP_SFLX_rain(:,:), VAR_NAME(1) )
          call STAT_total( total, ATMOS_PHY_MP_SFLX_snow(:,:), VAR_NAME(2) )
       endif

       call FILEIO_write_var( restart_fid, VAR_ID(1), ATMOS_PHY_MP_SFLX_rain(:,:), &
                              VAR_NAME(1), 'XY' ) ! [IN]
       call FILEIO_write_var( restart_fid, VAR_ID(2), ATMOS_PHY_MP_SFLX_snow(:,:), &
                              VAR_NAME(2), 'XY' ) ! [IN]

    endif

    return
  end subroutine ATMOS_PHY_MP_vars_restart_write

end module mod_atmos_phy_mp_vars
