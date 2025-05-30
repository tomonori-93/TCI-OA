MODULE common_obs_scale_H08VR
!=======================================================================
!
! [PURPOSE:] Observational procedures for H08VR
!
! [HISTORY:]
!   02/23/2021 Satoki Tsujino    added a new ID for H08 Vr
!   01/19/2022 Satoki Tsujino    cut the preprocesses
!
!=======================================================================
!
! [LETKF observation format]
!   (In files, all variables are stored in single-precision float)
!
!  column  description
!     (1)  variable type (1..nid_obs; see 'id_*_obs' parameters)
!     (2)  longitude (TC-center degree)
!     (3)  latitude (TC-center degree)
!     (4)  level/height
!            u,v,t,tv,q,rh: level (hPa)
!            ps: station elevation (m)
!     (5)  observation value
!            wind (m/s)
!            temperature (K)
!            specific humidity (kg/kg)
!            relative humidity (%)
!            surface pressure (hPa)
!     (6)  observation error
!            unit same as observation value
!     (7)  observation platform type (1..nobtype+1; see 'obtypelist' array)
!     (8)  observation time relative to analysis time (sec)
!
!=======================================================================
!$USE OMP_LIB
  USE common
  USE common_nml
  USE common_scale
  USE common_obs_scale
  USE common_mpi_scale
  use scale_grid, only: &
      DX, &
      DY

  IMPLICIT NONE
  PUBLIC

CONTAINS

!
!-----------------------------------------------------------------------
!   Himawari-8 VT obs subroutines by Satoki Tsujino (02/23/2021)
!   [Under construction]
!   Procedures:
!   1. Make vertical averages (Ub and Vb) of horizontal winds (U and V)
!      between two levels, and calculate tangential wind (Vr) from Ub and Vb
!   2. Make azimuthal average (Vrb) of Vr at each radius
!
!  [NOTE] stggrd: grid type of u and v  (Now, not supported)
!         0: non-staggered grid
!         1: staggered grid
!-----------------------------------------------------------------------
SUBROUTINE Trans_XtoY_H08VR(slot_v,procd_v,rig_tcobs,rjg_tcobs,rz1,rz2,  &
  &                         lon,lat,rad,valid,rigu,rigv,rjgu,rjgv,  &
  &                         v3d,v2d,cent_flag,yobs,qc,stggrd)
  use scale_mapproj, only: &
      MPRJ_rotcoef
  use scale_grid_index, only: &
      KHALO
  IMPLICIT NONE
  INTEGER,INTENT(in) :: slot_v   ! max. observation number for Vr observation in one process
  INTEGER,INTENT(in) :: procd_v  ! process number in all subdomains
  REAL(r_size),INTENT(IN) :: rig_tcobs(slot_v,procd_v),rjg_tcobs(slot_v,procd_v)  ! the first guess location for the storm center (lon,lat) in global domain
  REAL(r_size),INTENT(IN) :: rz1(slot_v,procd_v),rz2(slot_v,procd_v)  ! the levels (unit: m) for the vertical average
  REAL(r_size),INTENT(IN) :: lon(slot_v,procd_v),lat(slot_v,procd_v)  ! the first guess location for the storm center
  REAL(r_size),INTENT(IN) :: rad(slot_v,procd_v)   ! the radius from the storm center in azimuthal average
  LOGICAL,INTENT(IN) :: valid(slot_v,procd_v)      ! valid flag in avairable observation
  REAL(r_size),INTENT(IN) :: rigu(nlonh)  ! ri in u grid number for model variables in global domain
  REAL(r_size),INTENT(IN) :: rigv(nlonh)  ! ri v grid number for model variables in global domain
  REAL(r_size),INTENT(IN) :: rjgu(nlath)  ! rj u grid number for model variables in global domain
  REAL(r_size),INTENT(IN) :: rjgv(nlath)  ! rj v grid number for model variables in global domain
  REAL(r_size),INTENT(IN) :: v3d(nlevh,nlonh,nlath,nv3dd)  ! 3d model variables
  REAL(r_size),INTENT(IN) :: v2d(nlonh,nlath,nv2dd)  ! 2d model variables
  CHARACTER(3),INTENT(IN) :: cent_flag  ! Flag of the storm center in the model
                                        ! 'cal' = calculation from the slp, 'obs' = use of r{i,j}g_tcobs
  REAL(r_size),INTENT(OUT) :: yobs(slot_v,procd_v)  ! H(x)
  INTEGER,INTENT(OUT) :: qc(slot_v,procd_v)
  INTEGER,INTENT(IN),OPTIONAL :: stggrd
  INTEGER :: ii, jj, kk, m, ierr
  INTEGER :: ntheta                     ! sampling number for azimuthal direction at a radius
  INTEGER :: i_rigm,j_rjgm              ! floor(rig_rt),floor(rjg_rt)
  INTEGER,ALLOCATABLE :: i_Vrb(:)       ! variable for counting avairable points
  INTEGER :: i_Vrb_sec(nprocs_d)        ! variable for counting avairable points in each MPI rank
  REAL(r_size) :: r_inv                 ! inversion of rad(ii)
  REAL(r_size) :: theta                 ! azimuthal angle (rad)
  REAL(r_size) :: rig_rt,rjg_rt         ! rig and rjg at a certain point (rad(ii),theta)
  REAL(r_size) :: rigm,rjgm             ! rig(i_rigm),rjg(j_rjgm)
  REAL(r_size) :: xi,yj                 ! rotating operators for calculating Vr from u,v
  REAL(r_size) :: a,b                   ! ratios for the bilinear interpolation from the four points to (rad(ii),theta)
  REAL(r_size),ALLOCATABLE :: Vrb(:)    ! vertical average of Vr(theta) at a radius
  REAL(r_size) :: Vrb_sec               ! azimuthal average in a sector (i.e., a MPI rank) of Vrb(theta) at rad(ii)
  REAL(r_size) :: u(2,2),v(2,2),Vr(2,2) ! vertical averages of U, V, and Vr at which the four points are located near (rad(ii),theta)
!  REAL(r_size) :: slp2d(nlon,nlat)      ! 2d variable in local domain
!  REAL(r_size) :: slp2dg(nglon,nglat)   ! 2d variable in global domain
!  REAL(r_size) :: t,q,topo              ! temporary variables for calculating slp from ps
  real(r_size) :: rig_tc,rjg_tc         ! the storm center location in global domain of the model simulation
  REAL(r_size) :: v3du(nlevh,nlonh,nlath)  ! 3d model variables for u
  REAL(r_size) :: v3dv(nlevh,nlonh,nlath)  ! 3d model variables for v
  REAL(RP) :: rotc(2)

  INTEGER :: stggrd_ = 1
  if (present(stggrd)) stggrd_ = stggrd

  yobs = undef
  qc = iqc_good

!org  if (stggrd_ == 1) then  ! change u and v from vector points to scalar points
!org    do jj=1,nlath
!org      do ii=1,nlonh
!org        CALL itpl_2d_column(v3d(:,:,:,iv3dd_u),rigu(ii)-0.5_r_size,rjgu(jj),v3du(:,ii,jj))
!org        CALL itpl_2d_column(v3d(:,:,:,iv3dd_v),rigv(ii),rjgv(jj)-0.5_r_size,v3dv(:,ii,jj))
!org      end do
!org    end do
!org  else
!org    do jj=1,nlath
!org      do ii=1,nlonh
!org        CALL itpl_2d_column(v3d(:,:,:,iv3dd_u),rigu(ii),rjgu(jj),v3du(:,ii,jj))
!org        CALL itpl_2d_column(v3d(:,:,:,iv3dd_v),rigv(ii),rjgv(jj),v3dv(:,ii,jj))
!org      end do
!org    end do
!org  end if

! Calculation on Cartesian coordinates
!(no need)    call MPRJ_rotcoef(rotc,lon*deg2rad,lat*deg2rad)
!(no need)    if (elm == id_u_obs) then
!(no need)      yobs = u * rotc(1) - v * rotc(2)
!(no need)    else
!(no need)      yobs = u * rotc(2) + v * rotc(1)
!(no need)    end if
!-- under construction (to here)

  do kk=1,procd_v
    do ii=1,slot_v

      if(valid(ii,kk).eqv..true.)then

!  !-- Not (Process 1: Determine the storm center based on the SLP if cent_flag = 'cal')

!     select case (cent_flag(1:3))
!     case ('cal')
!        write(*,*) "Under construction..."
!     !-- 1. convert surface pressure (v2d(:,:,iv2dd_ps)) to sea level pressure
!       do jj=1,nlat
!          do ii=1,nlon
!             CALL itpl_2d(v2d(:,:,iv2dd_t2m),ri,rj,t)
!             CALL itpl_2d(v2d(:,:,iv2dd_q2m),ri,rj,q)
!             CALL itpl_2d(v2d(:,:,iv2dd_topo),ri,rj,topo)
!             CALL itpl_2d(v2d(:,:,iv2dd_ps),ri,rj,slp2d(ii,jj))
!             CALL prsadj(slp2d(ii,jj),-1.0d0*topo,t,q)
!          end do
!       end do
!
!    !-- 2. gather slp2d in each local domain to slp2dg in global domain
!    !--    (the rank to which the storm center (rig_tcobs,rjg_tcobs) belongs)
!
!       call MPI_Barrier()
!       call MPI_Gather()  ! rank(0-M) -> rankm
!
!    !-- 3. determine the storm center in the model simulation on only rankm
!    !--    (slp2dg -> rig_tc,rjg_tc)
!
!       call MPI_Barrier()
!       if(my_rank==m)then
!          call DC_Braun()
!       end if
!
!    !-- 4. broadcast (rig_tc,rjg_tc)
!       call MPI_Barrier()
!       call MPI_Bcast()  ! rankm -> rank(0-M)
!
!     case('obs')

        rig_tc=rig_tcobs(ii,kk)
        rjg_tc=rjg_tcobs(ii,kk)

!     end select

        r_inv=1.0d0/rad(ii,kk)

        !-- (Process 0: Preprocess)
        !-- 0.1 define azimuthal sampling number at each observation radius (rad(ii,kk))

        ntheta=int(360.0*deg2rad*rad(ii,kk)/DX)
        allocate(Vrb(ntheta))
        allocate(i_Vrb(ntheta))  ! For counting avairable points
        Vrb=0.0d0
        i_Vrb=0

!$OMP PARALLEL DEFAULT(SHARED)
!$OMP DO SCHEDULE(RUNTIME)  &
!$OMP &  PRIVATE(jj,theta,rig_rt,rjg_rt,i_rigm,j_rjgm,rigm,rjgm,u,v,xi,yj,Vr,a,b)

        do jj=1,ntheta

        !-- 0.2 calculate ri(r,t)g,rj(r,t)g at rad(ii,kk) and theta

          theta=360.0*deg2rad*real(jj-1)/real(ntheta-1)

          rig_rt=rig_tc+(rad(ii,kk)/DX)*cos(theta)
          rjg_rt=rjg_tc+(rad(ii,kk)/DY)*sin(theta)

        !-- 0.3 determine the nearest grid in the model for rig_rt,rjg_rt
        !--     (rig_rt,rjg_rt) -> (rigm(i_rigm),rjgm(j_rjgm))
        !-- [NOTE]: (rigv, rjgu) is identical to each scalar point. 

!(debug) write(*,*) "(debug) satoki: ",nlonh, nlath, rig_rt, rjg_rt,  &
!(debug)  &                      rigv, rjgu 
          call rgrt_floor( nlonh, nlath, rig_rt, rjg_rt,  &
  &                        rigv, rjgu, i_rigm, j_rjgm, rigm, rjgm )

!(debug) write(*,*) "(debug) satoki: i_rigm, j_rjgm", i_rigm, j_rjgm
          if((i_rigm==0).or.(j_rjgm==0))then  ! point [rad(ii,kk), theta] is outside the domain
             cycle
          end if

          !-- (Process 1: Make vertical averages of horizontal winds)
          !-- 1.1 make vertical averages of horizontal winds (U and V)
          !--     at the four points (i.e., rigm~rigm+1,rjgm~rjgm+1)

!(debug) write(*,*) "(debug) satoki: vert", nlevh,rz1(ii,kk), rz2(ii,kk),v3d(:,1,1,iv3dd_hgt), v3d(:,1,1,iv3dd_u)
          call vert_ave( nlevh,rz1(ii,kk), rz2(ii,kk),  &
  &                      v3d(:,i_rigm:i_rigm+1,j_rjgm:j_rjgm+1,iv3dd_hgt),  &
  &                      v3d(:,i_rigm:i_rigm+1,j_rjgm:j_rjgm+1,iv3dd_u),  &
  &                      u(1:2,1:2) )
          call vert_ave( nlevh,rz1(ii,kk), rz2(ii,kk),  &
  &                      v3d(:,i_rigm:i_rigm+1,j_rjgm:j_rjgm+1,iv3dd_hgt),  &
  &                      v3d(:,i_rigm:i_rigm+1,j_rjgm:j_rjgm+1,iv3dd_v),  &
  &                      v(1:2,1:2) )

!(debug) write(*,*) "(debug) satoki: u,v", u(1:2,1:2), v(1:2,1:2)
          !-- 1.2 calculate Vr from U and V at the four points,
          !--     and interpolate Vr(rad(ii,kk),theta) from the four Vr

          xi=(rigv(i_rigm)-rig_tc)*DX*r_inv
          yj=(rjgu(j_rjgm)-rjg_tc)*DY*r_inv
          Vr(1,1)=xi*u(1,1)+yj*v(1,1)  ! rigm,rjgm

          xi=(rigv(i_rigm+1)-rig_tc)*DX*r_inv
          yj=(rjgu(j_rjgm)-rjg_tc)*DY*r_inv
          Vr(2,1)=xi*u(2,1)+yj*v(2,1)  ! rigm+1,rjgm

          xi=(rigv(i_rigm)-rig_tc)*DX*r_inv
          yj=(rjgu(j_rjgm+1)-rjg_tc)*DY*r_inv
          Vr(1,2)=xi*u(1,2)+yj*v(1,2)  ! rigm,rjgm+1

          xi=(rigv(i_rigm+1)-rig_tc)*DX*r_inv
          yj=(rjgu(j_rjgm+1)-rjg_tc)*DY*r_inv
          Vr(2,2)=xi*u(2,2)+yj*v(2,2)  ! rigm+1,rjgm+1

          a=rig_rt-rigm
          b=rjg_rt-rjgm
          Vrb(jj)=(1.0-b)*(1.0-a)*Vr(1,1)+(1.0-b)*a*Vr(2,1)  &
  &              +b*(1.0-a)*Vr(1,2)+b*a*Vr(2,2)
          i_Vrb(jj)=1  ! avairable flag for azimuthal average

        end do  ! [ jj=1, ntheta ]

!$OMP END DO
!$OMP END PARALLEL

        !-- (Process 2: make azimuthal average Vrb_sec (sector range) of Vrb at rad(ii,kk))

        call azim_sum( ntheta, Vrb, i_Vrb, Vrb_sec )

        !-- 2.1 Gather Vrb_sec (and i_Vrb_sec) in each rank to Vrbg_sec in rankm
        !--     (rankm includes the storm center (rig_tcobs,rjg_tcobs))
        !-- 2.2 make average of Vrb_sec in each sector at rad(ii,kk)
        !-- 2.3 Broadcast the results to all MPI ranks
        !-- [Note]: These procedures are coupled by MPI_ALLREDUCE

!org        if(myrank_e == 0)then
!(debug) write(*,*) "v check satoki", rad(ii,kk), yobs(ii,kk)
          call mpi_timer('', 2, barrier = MPI_COMM_d)
          call MPI_AllReduce(Vrb_sec,yobs(ii,kk),1,MPI_r_size,MPI_SUM,MPI_COMM_d,ierr)  ! sum[rank(0-M)] -> rank(0-M)
!org        end if
!       call azim_sum( nprocs_d, Vrb_sec, i_Vrb_sec, yobs(ii,kk) )
        yobs(ii,kk)=yobs(ii,kk)/real(ntheta)
!(debug) write(*,*) "v check satoki", rad(ii,kk), yobs(ii,kk)

!       if(i_Vrb_sec(my_rank)==1)then
        qc(ii,kk)=iqc_good  ! No check
!       else
!          qc(ii,kk)=iqc_obs_bad  ! Not include in this rank
!       end if

        deallocate(Vrb)
        deallocate(i_Vrb)

        call MPI_Barrier(MPI_COMM_d,ierr)

      end if  ! [ valid(ii,kk).eqv..true. ]

    end do  ! [ ii = 1, slot_v ]

  end do  ! [ kk = 1, procd_v ]

  RETURN
END SUBROUTINE Trans_XtoY_H08VR

END MODULE common_obs_scale_H08VR
