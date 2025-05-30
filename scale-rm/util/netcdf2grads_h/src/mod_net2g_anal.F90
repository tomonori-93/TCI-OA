!-------------------------------------------------------------------------------------------
!> module NET2G anal
!!
!! @par Description
!!          Analysis module for post-process of scale
!!
!! @author Team SCALE
!!
!! @par History
!! @li  2015-02-03 (R.Yoshida)  original
!!
!<
!-------------------------------------------------------------------------------------------
module mod_net2g_anal
  !-----------------------------------------------------------------------------------------
  !
  !++ used modules
  !
  use mod_net2g_vars
  use mod_net2g_error

  !-----------------------------------------------------------------------------------------
  implicit none
  private
  !++ included parameters
#include "inc_net2g.h"
  !-----------------------------------------------------------------------------------------
  !
  !++ Public procedure
  !
  public :: anal_setup
  public :: anal_input_ref
  public :: anal_ref_interp
  public :: anal_simple

  !-----------------------------------------------------------------------------------------
  !
  !++ Public parameters & variables
  !
  !-----------------------------------------------------------------------------------------
  !
  !++ Private procedure
  !
  private :: anal_search_lev
  private :: anal_search_lev_extrp  ! add by satoki

  !-----------------------------------------------------------------------------------------
  !
  !++ Private parameters & variables
  !
  real(DP),allocatable, private :: ref(:,:,:,:)
  real(DP),allocatable, private :: wght_l(:,:), wght_u(:,:)
  integer, allocatable, private :: kl(:,:), ku(:,:)

  !-----------------------------------------------------------------------------------------
contains
  !-----------------------------------------------------------------------------------------

  !> allocate temporaly arraies
  !-----------------------------------------------------------------------------------------
  subroutine anal_setup( &
      mnxp,   & ! [in]
      mnyp,   & ! [in]
      nz,     & ! [in]
      nmnge   ) ! [in]
    implicit none

    integer, intent(in) :: mnxp, mnyp
    integer, intent(in) :: nz(3)
    integer, intent(in) :: nmnge
    !---------------------------------------------------------------------------

    allocate( ref(mnxp, mnyp, nz(1), nmnge) )
    allocate( wght_l(mnxp, mnyp) )
    allocate( wght_u(mnxp, mnyp) )
    allocate( kl    (mnxp, mnyp) )
    allocate( ku    (mnxp, mnyp) )

    return
  end subroutine anal_setup

  !> allocate temporaly arraies
  !-----------------------------------------------------------------------------------------
  subroutine anal_input_ref( &
      inp,   & ! [in]
      nm     ) ! [in]
    implicit none

    real(SP), intent(in) :: inp(:,:,:)
    integer,  intent(in) :: nm
    !---------------------------------------------------------------------------

    ref(:,:,:,nm) = dble( inp(:,:,:) )

    return
  end subroutine anal_input_ref

  !> simple analysis
  !-----------------------------------------------------------------------------------------
  subroutine anal_simple( &
      atype,    & ! [in ]
      is,       & ! [in ]
      ie,       & ! [in ]
      js,       & ! [in ]
      je,       & ! [in ]
      isn,      & ! [in ]
      jsn,      & ! [in ]
      nzn,      & ! [in ]
      indata,   & ! [in ]
      outdata   ) ! [out]
    implicit none

    integer,  intent(in)  :: atype
    integer,  intent(in)  :: is, ie, js, je
    integer,  intent(in)  :: isn, jsn, nzn
    real(DP), intent(in)  :: indata(:,:,:,:)
    real(SP), intent(out) :: outdata(:,:)

    integer :: i, j, ni, nj, k
    real(SP) :: work
    !---------------------------------------------------------------------------

    select case( atype )
    case ( a_slice )
       nj = jsn
!OCL XFILL
       do j = js, je
       ni = isn
       do i = is, ie
          outdata(i,j) = real( indata(ni,nj,1,1) )
       ni = ni + 1
       enddo
       nj = nj + 1
       enddo
    case ( a_max )
       nj = jsn
!OCL PREFETCH
       do j = js, je
       ni = isn
       do i = is, ie
          outdata(i,j) = real( maxval(indata(ni,nj,:,1)) )
       ni = ni + 1
       enddo
       nj = nj + 1
       enddo
    case ( a_min )
       nj = jsn
!OCL PREFETCH
       do j = js, je
       ni = isn
       do i = is, ie
          outdata(i,j) = real( minval(indata(ni,nj,:,1)) )
       ni = ni + 1
       enddo
       nj = nj + 1
       enddo
    case ( a_sum )
       nj = jsn
!OCL PREFETCH
       do j = js, je
       ni = isn
       do i = is, ie
          work = 0.0D0
          do k = 1, nzn
             work = work + real( indata(ni,nj,k,1) )
          enddo
          outdata(i,j) = work
       ni = ni + 1
       enddo
       nj = nj + 1
       enddo
    case ( a_ave )
       nj = jsn
!OCL PREFETCH
       do j = js, je
       ni = isn
       do i = is, ie
          work = 0.0D0
          do k = 1, nzn
             work = work + real( indata(ni,nj,k,1) )
          enddo
          outdata(i,j) = work / real(nzn)
       ni = ni + 1
       enddo
       nj = nj + 1
       enddo
    case default
       call err_abort( 0, __LINE__, loc_anal )
    end select

    return
  end subroutine anal_simple

  !> hgt/pres level interpolation
  !-----------------------------------------------------------------------------------------
  subroutine anal_ref_interp( &
      ctype,     & ! [in ]
      lev,       & ! [in ]
      org,       & ! [in ]
      logwgt,    & ! [in ]
      is,  ie,   & ! [in ]
      js,  je,   & ! [in ]
      isn, ien,  & ! [in ]
      jsn, jen,  & ! [in ]
      nzn, nm,   & ! [in ]
      interp     ) ! [out]
    implicit none

    integer,  intent(in)  :: ctype
    real(SP), intent(in)  :: lev
    real(DP), intent(in)  :: org(:,:,:,:)
    logical,  intent(in)  :: logwgt
    integer,  intent(in)  :: is, ie, js, je
    integer,  intent(in)  :: isn, ien
    integer,  intent(in)  :: jsn, jen
    integer,  intent(in)  :: nzn, nm
    real(SP), intent(out) :: interp(:,:)

    real(SP) :: diff_l, diff_u
    integer :: i, j, ii, jj
    !---------------------------------------------------------------------------

!(ORG: satoki)    call anal_search_lev( ctype, lev, isn, ien,  &
!(ORG: satoki)                          jsn, jen, nzn, nm      )
! change to anal_search_lev_extrp by satoki
    call anal_search_lev_extrp( ctype, lev, isn, ien,  &
                                jsn, jen, nzn, nm      )

    jj = jsn
!OCL PREFETCH
    do j = js, je
    ii = isn
    do i = is, ie
       diff_l = abs( wght_l(ii,jj) - UNDEF_DP )
       diff_u = abs( wght_u(ii,jj) - UNDEF_DP )
       if ( diff_l < EPS_SP .or. diff_u < EPS_SP ) then
          interp(i,j) = real( UNDEF_DP )
       else
          if ( logwgt ) then
             interp(i,j) = real(  wght_l(ii,jj) * log(org(ii,jj,kl(ii,jj),1)) &
                                + wght_u(ii,jj) * log(org(ii,jj,ku(ii,jj),1)) )
             interp(i,j) = exp (interp(i,j))
          else
             interp(i,j) = real(  wght_l(ii,jj) * org(ii,jj,kl(ii,jj),1) &
                                + wght_u(ii,jj) * org(ii,jj,ku(ii,jj),1) )
          endif
       endif
    ii = ii + 1
    enddo
    jj = jj + 1
    enddo

    return
  end subroutine anal_ref_interp

  !> serach levels upper and lower of level
  !-----------------------------------------------------------------------------------------
  subroutine anal_search_lev( &
      ctype,      & ! [in ]
      lev,        & ! [in ]
      isn, ien,   & ! [in ]
      jsn, jen,   & ! [in ]
      nz,  nm     ) ! [in ]
    implicit none

    integer,  intent(in)  :: ctype
    real(SP), intent(in)  :: lev
    integer,  intent(in)  :: isn, ien
    integer,  intent(in)  :: jsn, jen
    integer,  intent(in)  :: nz, nm

    integer  :: ii, jj, kk
    real(DP) :: hgt,  hgt_l,  hgt_u
    real(DP) :: plog, plog_l, plog_u
    real(DP) :: diff
    !---------------------------------------------------------------------------

    select case( ctype )
    case ( c_height )
!OCL PREFETCH
       do jj = jsn, jen
       do ii = isn, ien
          !allow extrapolation
          diff = ref(ii,jj,1,nm) - dble( lev )
          if ( diff > 0 ) then
             wght_l(ii,jj) = UNDEF_DP
             wght_u(ii,jj) = UNDEF_DP
          else
             do kk = 2, nz
                if ( ref(ii,jj,kk,nm) > lev ) exit
             enddo
             if ( kk > nz ) then
                write (*, '(1X,A)' ) "ERROR: requested vertical level is too high."
                write (*, '(1X,A,F12.2,A)' ) "       requested vertical level: ", lev, " [m]"
                write (*, '(1X,A,F12.2,A)' ) "       input data top level: ", ref(ii,jj,nz,nm), " [m]"
                call err_abort( 1, __LINE__, loc_main )
             endif

             ku(ii,jj) = kk
             kl(ii,jj) = kk - 1

             hgt   = dble( lev )
             hgt_l = ref(ii,jj,kk-1,nm)
             hgt_u = ref(ii,jj,kk,  nm)

             wght_l(ii,jj) = (hgt-hgt_u) / (hgt_l-hgt_u)
             wght_u(ii,jj) = (hgt_l-hgt) / (hgt_l-hgt_u)
          endif
       enddo
       enddo

    case ( c_pres )
!OCL PREFETCH
       do jj = jsn, jen
       do ii = isn, ien
          !allow extrapolation
          diff = ref(ii,jj,1,nm) - dble( lev )
          if ( diff < 0 ) then
             wght_l(ii,jj) = UNDEF_DP
             wght_u(ii,jj) = UNDEF_DP
          else
             do kk = 2, nz
                if ( ref(ii,jj,kk,nm) < lev ) exit
             enddo
             if ( kk > nz ) then
                write (*, '(1X,A)' ) "ERROR: requested vertical level is too high."
                write (*, '(1X,A,F12.2,A)' ) "       requested vertical level: ", lev, " [Pa]"
                write (*, '(1X,A,F12.2,A)' ) "       input data top level: ", ref(ii,jj,nz,nm), " [Pa]"
                call err_abort( 1, __LINE__, loc_main )
             endif

             ku(ii,jj) = kk
             kl(ii,jj) = kk - 1

             plog   = log( dble( lev )        )
             plog_l = log( ref(ii,jj,kk-1,nm) )
             plog_u = log( ref(ii,jj,kk,  nm) )

             wght_l(ii,jj) = (plog-plog_u) / (plog_l-plog_u)
             wght_u(ii,jj) = (plog_l-plog) / (plog_l-plog_u)
          endif
       enddo
       enddo

    case default
       call err_abort( 0, __LINE__, loc_anal )

    end select

    return
  end subroutine anal_search_lev

  !> serach levels upper and lower of level with extrapolation
  !  Add by satoki
  !-----------------------------------------------------------------------------------------
  subroutine anal_search_lev_extrp( &
      ctype,      & ! [in ]
      lev,        & ! [in ]
      isn, ien,   & ! [in ]
      jsn, jen,   & ! [in ]
      nz,  nm     ) ! [in ]
    implicit none

    integer,  intent(in)  :: ctype
    real(SP), intent(in)  :: lev
    integer,  intent(in)  :: isn, ien
    integer,  intent(in)  :: jsn, jen
    integer,  intent(in)  :: nz, nm

    integer  :: ii, jj, kk
    real(DP) :: hgt,  hgt_l,  hgt_u
    real(DP) :: plog, plog_l, plog_u
    real(DP) :: diff
    !---------------------------------------------------------------------------

    select case( ctype )
    case ( c_height )
!OCL PREFETCH
       do jj = jsn, jen
       do ii = isn, ien
          !allow extrapolation
          diff = ref(ii,jj,1,nm) - dble( lev )
          if ( diff > 0 ) then
             wght_l(ii,jj) = UNDEF_DP
             wght_u(ii,jj) = UNDEF_DP
          else
             do kk = 2, nz
                if ( ref(ii,jj,kk,nm) > lev ) exit
             enddo
             if ( kk > nz ) then
                write (*, '(1X,A)' ) "ERROR: requested vertical level is too high."
                write (*, '(1X,A,F12.2,A)' ) "       requested vertical level: ", lev, " [m]"
                write (*, '(1X,A,F12.2,A)' ) "       input data top level: ", ref(ii,jj,nz,nm), " [m]"
                call err_abort( 1, __LINE__, loc_main )
             endif

             ku(ii,jj) = kk
             kl(ii,jj) = kk - 1

             hgt   = dble( lev )
             hgt_l = ref(ii,jj,kk-1,nm)
             hgt_u = ref(ii,jj,kk,  nm)

             wght_l(ii,jj) = (hgt-hgt_u) / (hgt_l-hgt_u)
             wght_u(ii,jj) = (hgt_l-hgt) / (hgt_l-hgt_u)
          endif
       enddo
       enddo

    case ( c_pres )
!OCL PREFETCH
       do jj = jsn, jen
       do ii = isn, ien
          !allow extrapolation
          diff = ref(ii,jj,1,nm) - dble( lev )
          if ( diff < 0 ) then
             do kk = 2, nz
                if ( ref(ii,jj,kk,nm) < lev ) exit
             enddo
             if ( kk > nz ) then
                write (*, '(1X,A)' ) "ERROR: requested vertical level is too high."
                write (*, '(1X,A,F12.2,A)' ) "       requested vertical level: ", lev, " [Pa]"
                write (*, '(1X,A,F12.2,A)' ) "       input data top level: ", ref(ii,jj,nz,nm), " [Pa]"
                call err_abort( 1, __LINE__, loc_main )
             endif

             ku(ii,jj) = kk
             kl(ii,jj) = kk - 1

             wght_l(ii,jj) = 0.0d0
             wght_u(ii,jj) = 1.0d0
          else
             do kk = 2, nz
                if ( ref(ii,jj,kk,nm) < lev ) exit
             enddo
             if ( kk > nz ) then
                write (*, '(1X,A)' ) "ERROR: requested vertical level is too high."
                write (*, '(1X,A,F12.2,A)' ) "       requested vertical level: ", lev, " [Pa]"
                write (*, '(1X,A,F12.2,A)' ) "       input data top level: ", ref(ii,jj,nz,nm), " [Pa]"
                call err_abort( 1, __LINE__, loc_main )
             endif

             ku(ii,jj) = kk
             kl(ii,jj) = kk - 1

             plog   = log( dble( lev )        )
             plog_l = log( ref(ii,jj,kk-1,nm) )
             plog_u = log( ref(ii,jj,kk,  nm) )

             wght_l(ii,jj) = (plog-plog_u) / (plog_l-plog_u)
             wght_u(ii,jj) = (plog_l-plog) / (plog_l-plog_u)
          endif
       enddo
       enddo

    case default
       call err_abort( 0, __LINE__, loc_anal )

    end select

    return
  end subroutine anal_search_lev_extrp

end module mod_net2g_anal
