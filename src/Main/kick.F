      SUBROUTINE KICK(I,ICASE,KW,DM)
*
*
*       Velocity kick for WD, neutron stars or black holes.
*       ---------------------------------------------------
* There are various choices that can be made for kicks. 
* Make sure you are comfortable with the choices set (see below) 
* as this will critically affect retention statistics. 
*
* For regular NSs the kick choice is controlled by the value of 
* DISP (sigma in BSE). Choices are: 
*    DISP < 0.0 - kick drawn randomly between 0 - ABS(DISP) km/s
*    DISP = 0.0 - no kick
*    DISP > 0.0 - kick drawn from a Maxwellian with dispersion DISP. 
* You may also choose to have the kick velocity distribution scaled 
* by VSTAR (i.e. scaled by the initial escape velocity). 
* To do this set VFAC to a non-zero value and VFAC*VSTAR will be 
* either the maximum of the flat distribution (DISP < 0) or 
* the dispersion of the Maxwellian (DISP > 0). 
*
* Then for an electron capture supernova or an accretion-induced 
* collapse the choice is determined by the value of ECSIG set 
* internally here. Choices are: 
*    ECSIG = 0.0 - no kick
*    ECSIG > 0.0 - kick drawn from a Maxwellian, dispersion ECSIG 
*    ECSIG < 0.0 - same as for the regular NSs but scaled by ABS(ECSIG).
* These supernova are identified by their mass of 1.26 Msun. 
*
* For BHs the kick choice is controlled by the value of BHFLAG.  
* Choices are: 
*    BHFLAG = 0 - no kick
*    BHFLAG = 1 - same as for the regular NSs
*    BHFLAG = 2 - same as for the regular NSs but scaled by fallback. 
*    BHFLAG = 3 - BH natal spin from Geneva models (experimental) implemented by Sambaran Banerjee 2019/20
*    BHFLAG = 4 - BH natal spin from MESA models (experimental) implemented by Sambaran Banerjee 2019/20
*
* Small kicks for WDs can also be set if KZ(25) > 0 in the input file. 
* In this case you can distinguish: 
*   WDSIG1 - He and COWDs
*   WDSIG2 - ONeWDs 
* as the dispersion in a Maxwellian for the different WD types. 
* A limit of WDKMAX is set. 
*     See Fellhauer et al. 2003, ApJ, 595, L53 for more on WD kicks.

*  M.A.S. MAS Manuel Arca Sedda 03 Nov 2021
*  Added a BH spin flag (BHSPINFL) to select BH natal spins
*     BHSPINFL = 0 - zero spins 
*     BHSPINFL = 1 - uniform spin distribution *
*     BHSPINFL = 2 - Gaussian spin distribution with mean = 0.5, dispersion = 0.2 *      
*     BHSPINFL = 3 - Maxwellian spin distribution with sigma = 0.2 *
*     BHSPINFL = 4 - Geneva models (implemented by Sambaran) *      
*     BHSPINFL = 5 - Mesa models (implemented by Sambaran) *
*  A new vector in common6.h has been defined, named
*     ASPN(NMAX)
      

      
      Include 'kspars.h'
      INCLUDE 'common6.h'
      REAL*8  RAN2,VK(4)
*     Unsafe for parallel
      SAVE  IPAIR, KC, VDIS, RI
      DATA  IPAIR,KC /0,0/
*       Common Blocks read in READSE (RSp Mar 23)
      integer ecflag,wdflag,nsflag,psflag,mdflag,bhflag,kmech,idum
      real*8 mch,mxns0,mxns1,nwind,bwind,flbv,disp,ecsig,
     *       wdsig1,wdsig2,wdkmax,vvfac,zmetal
      common/sse/ecflag,wdflag,nsflag,psflag,mdflag,bhflag,
     *       kmech,idum,mch,mxns0,mxns1,nwind,bwind,flbv,disp,ecsig,
     *       wdsig1,wdsig2,wdkmax,vvfac,zmetal
      integer bhspinfl,kicktype
      real*8 lambd1,alphac,xk2,xk3,acc1,acc2,xbeta,xxi,
     *      epsnov,eddfac,gamm1
      common/bse/lambd1,alphac,bhspinfl,kicktype,xk2,xk3,
     *      acc1,acc2,xbeta,xxi,epsnov,eddfac,gamm1
*
      REAL*8 VFAC
      REAL*8 DISP0, VK2
      LOGICAL IFLAT      
*     Get fallback from hrdiag.f
*     Safe for parallel
      REAL*8 CONVF,MNUEFF,MNSTYP
      real*8 FBFAC,FBTOT,MCO
      integer ECS
      REAL*8 JSPIN,NUMBER
      COMMON /FBACK/ FBFAC,FBTOT,MCO,ECS
*
*       Set variables with different names in common (RSp Mar23).
      VFAC = VVFAC
*
*     --03/07/14 11:30-lwang-ks-parallel--------------------------------*
***** Note: Here when icase eq. -147 means for ks communication
*****       I will be the processer id to share data
*     IF (ICASE.EQ.-147) THEN
*ifdef PARALLEL         
*        CALL MPI_BCAST(IPAIR,1,MPI_INTEGER,I,MPI_COMM_WORLD,ierr)
*        CALL MPI_BCAST(KC,1,MPI_INTEGER,I,MPI_COMM_WORLD,ierr)
*        CALL MPI_BCAST(VDIS,1,MPI_REAL8,I,MPI_COMM_WORLD,ierr)
*        CALL MPI_BCAST(RI,1,MPI_REAL8,I,MPI_COMM_WORLD,ierr)
*endif         
*        RETURN
*     END IF
*     --03/07/14 11:30-lwang-end-ks-parallel----------------------------*
*
*     Choose the kick settings.
*       Some suggested combinations are included: 
*
*       Adopt the Maxwellian of Hansen & Phinney (MN 291, 569, 1997) 
*     VFAC = 0.D0
*     DISP = 190.D0
*       Adopt the Maxwellian of Hobbs (MNRAS 360, 974, 2005)      
*     DISP = 265.D0
*       Take a flat distribution between 0-100 km/s for regular NSs, 
*     DISP = -100.0
*       for regular NSs, with EC kicks from a Maxwellian with a lower peak 
*     ECSIG = 20.D0
*       WD kicks depend on #25.       
*     WDSIG1 = 2.D0
*     WDSIG2 = 2.D0
*     WDKMAX = 6.D0
*       BH kicks scaled by fallback. 
*     BHFLAG = 2
*      
*     Current setting:
*     VFAC = 0.D0        ! Use DISP 
*     DISP = 265.D0      ! Adopt the Maxwellian of Hobbs (MNRAS 360, 974, 2005)
*     ECSIG = 3.0D0
*     WD kicks depend on #25. 
*     WDSIG1 = 2.D0      
*     WDSIG2 = 2.D0
*     WDKMAX = 6.D0
*     BHFLAG = 2
*     BHSPINFL = 3

******
*Manuel Arca Sedda May 2022
*
*      IF(DM .LT. 0.0)THEN
*         CALL KICKGW(I1,I2,kicktype)
*         GO TO 30
*      ENDIF
*
*     
*******
*     Chris L. Fryer. Oct 2018.
*     Code added by Sambaran Banerjee and adopted in LONG GITHUB
*     See arXiv: 1902.07718 (Banerjee, S., Belczynski, C., Fryer, C., et al.)
*
* CONVF: convective boost factor larger CO core masses 
*        in the case of convection-asymmerty-driven
*        kick mechanism (typical range: 2.0-10.0)
*
* MNUEFF: in case of neutrino-driven kick mechanism, the 
*         effective remnant mass beyond which the neutrino emission does not
*         enhance significantly as the remnant (baryonic) mass is increased
*         (typical range: 5.0-10.0 Msun)
*
* MNSTYP: typical mass of a neutron star with the input dispersion velocity 'DISP'
*
* KMECH: kick mechanism. 1 = standard momentum-conserving,
*                        2 = convection-asymmetry-driven,
*                        3 = collapse-asymmerty-driven,
*                        4 = neutrino driven
*
* It is assumed that one of these four mechanisms is the primary driver
* of SN natal kicks that we observe
*
      CONVF = 5.0D0
      MNUEFF = 7.0D0
      MNSTYP = 1.4D0
      KMECH = 3

*******

*       Save orbital parameters in case of KS binary (called from KSAPO).
      IF (ICASE.EQ.0) THEN
          IPAIR = I
          KC = KSTAR(N+IPAIR)
*       Identify the correct component (KSTAR reversed in MDOT).
          I1 = 2*IPAIR - 1
          I2 = I1 + 1
          IN = I1
          IF (KSTAR(I1).LT.0) THEN
              IN = I1
          ELSE IF (KSTAR(I2).LT.0) THEN
              IN = I2
          END IF
          KSTAR(IN) = IABS(KSTAR(IN))
*     ks MPI communication KSTAR
*         call ksparmpi(K_store,K_int,K_KSTAR,IN,0,KSTAR(IN))
*
*     When call expel in cmbody and WD/NS binary form after Binary CE, 
*     There is big energy error when DM is large. It seems here the DM 
*     will be set to zero and then cause the issue. Thus suppress now.
C      Determine mass loss and actual disruption velocity.
C          DM = BODY(IN) - 1.4/ZMBAR
C          IF (KW.LT.13) DM = 0.0
C          VD2 = 2.0*(BODY(N+IPAIR) - DM)/R(IPAIR)
          VD2 = 2.0*(BODY(N+IPAIR))/R(IPAIR)
          VDIS = SQRT(VD2)*VSTAR
*       Set cluster escape velocity (add twice central potential).
C          VP2 = 2.0*BODY(N+IPAIR)/R(IPAIR)
          VESC = SQRT(VD2 + 4.0)*VSTAR
          SEMI = -0.5*BODY(N+IPAIR)/H(IPAIR)
          ZM1 = BODY(I1)*SMU
          ZM2 = BODY(I1+1)*SMU
          EB = BODY(I1)*BODY(I1+1)/BODY(N+IPAIR)*H(IPAIR)
          RI = R(IPAIR)
*       Skip on #25 = 0/1 for consistent net WD modification of EKICK.
          IF ((KW.LT.13.AND.KZ(25).EQ.0).OR.
     &        (KW.EQ.12.AND.KZ(25).NE.2)) GO TO 30
*       Sum whole binding energy (used by BINOUT for net change).
          EKICK = EKICK + EB
          EGRAV = EGRAV + EB
*     ks MPI communicaton EKICK EGRAV
*         call ksparmpi(K_store,K_real8,K_EGRAV,0,0,EB)
*         call ksparmpi(K_store,K_real8,K_EKICK,0,0,EB)
          I2 = I1 + 1
          if(rank.eq.0)
     &    WRITE (6,1)  TTOT*TSTAR, NAME(I1), NAME(I2), KSTAR(I1), 
     &         KSTAR(I2),ZM1,ZM2,VESC, VDIS, R(IPAIR)/SEMI, EB, R(IPAIR)
    1     FORMAT (' BINARY KICK:  TIME[Myr] NAME(I1) NAME(I2) K*(I1) ',
     &         'K*(I2) M(I1)[M*] M(I2)[M*] VESC[km/s] VDIS[km/s] ',
     &         'R12/SEMI EB R12[NB] ',1P,E14.3,0P,2I10,2I4,2F9.3,
     &         1P,5E14.3)
          NBKICK = NBKICK + 1
*       Remove any circularized KS binary from the CHAOS/SYNCH table.
          IF (KSTAR(N+IPAIR).GE.10.AND.NCHAOS.GT.0) THEN
              II = -(N + IPAIR)
              CALL SPIRAL(II)
              KSTAR(N+IPAIR) = 0
*     ks MPI communication KSTAR
*             call ksparmpi(K_store,K_int,K_KSTAR,N+IPAIR,0,
*    &             KSTAR(N+IPAIR))
          END IF
          GO TO 30
      END IF
*
*       Generate velocity kick for neutron star (Gordon Drukier Tokyo paper).
*     IT = 0
*     V0 = 330.0
*     VCUT = 1000.0
*   2 VT = VCUT/V0*RAN2(IDUM1)
*     VP = VT*(2.0*RAN2(IDUM1) - 1.0)
*     VN = SQRT(VT**2 - VP**2)
*     FAC = 1.0/0.847*VN**0.3/(1.0 + VN**3.3)
*     IF (FAC.LT.RAN2(IDUM1).AND.IT.LT.10) GO TO 2
*     VKICK = V0*VT
*
******* BELOW IS THE PREVIOUS NBODY6++GPU-JUL2019 ****************
*C*       Adopt the Maxwellian of Hansen & Phinney (MNRAS 291, 569, 1997).
*C     DISP = 190.0
*
*       Adopt the Maxwellian of Hobbs (MNRAS 360, 974, 2005)
*      DISP = 265.0
*
*       Include velocity dispersion in terms of VSTAR (Parameter statement!).
*      IF (VFAC.GT.0.0D0) THEN
*          DISP = VFAC*VSTAR
*      END IF
*
*       Allow for optional type-dependent WD kick.
*      IF (KW.LT.13) THEN
*          IF (KZ(25).EQ.1.AND.(KW.EQ.10.OR.KW.EQ.11)) THEN
*              DISP = 5.0
*          ELSE IF (KZ(25).GT.1.AND.KW.EQ.12) THEN
*              DISP = 5.0
*          ELSE
*              DISP = 0.0
*          END IF
*      END IF
*
*       Use Henon's method for pairwise components (Douglas Heggie 22/5/97).
*      DO 2 K = 1,2
*          X1 = RAN2(IDUM1)
*          X2 = RAN2(IDUM1)
*       Generate two velocities from polar coordinates S & THETA.
*          S = DISP*SQRT(-2.0*LOG(1.0 - X1))
*          THETA = TWOPI*X2
*          VK(2*K-1) = S*COS(THETA)
*          VK(2*K) = S*SIN(THETA)
*    2 CONTINUE
*      VKICK = SQRT(VK(1)**2 + VK(2)**2 + VK(3)**2)
*      VK(4) = VKICK
*      IF(KW.EQ.14) VKICK = VKICK*(1.D0-fallback)
*
*       Limit kick velocity to VDIS+10*VSTAR/10*VST for binary/single stars.
*C      IF (IPAIR.GT.0) THEN
*C          VBF = SQRT(VDIS**2 + 100.0*VSTAR**2)
*C          VKICK = MIN(VKICK,VBF)
*C      ELSE
*C          VKICK = MIN(VKICK,10.0D0*VSTAR)
*       Ensure escape of massless star.
*      IF (IPAIR.LE.0.AND.BODY(I).EQ.0.0D0) VKICK = 10.0*VSTAR
*C      END IF
*     VKICK = VKICK/VSTAR
*
*      IF (VKICK.EQ.0.0) GO TO 30
*
*       Randomize the velocity components.
*     A(4) = 0.0
*     DO 5 K = 1,3
*         A(K) = 2.0*RAN2(IDUM1) - 1.0
*         A(4) = A(4) + A(K)**2
*   5 CONTINUE
***************** END OF NBODY6++GPU-July2019 ************
* 
******** BELOW IS TAKEN FROM LONG GITHUB - 26.10.2019 *********
*
      ZM = BODY(I)*ZMBAR
      VKICK = 0.D0
*
      IFLAT = .FALSE.
      IF(DISP.LT.-0.01)THEN
         IF(KW.EQ.13.AND.ZM.GE.1.28) IFLAT = .TRUE.
         IF(KW.EQ.13.AND.ZM.LT.1.28.AND.ECSIG.LT.-0.01) IFLAT = .TRUE.
         IF(KW.EQ.14.AND.BHFLAG.GT.0) IFLAT = .TRUE.
      ENDIF
*
      IF(IFLAT)THEN
*
*       Generate the kick velocity from a flat distribution. 
         DISP0 = ABS(DISP)
         IF(VFAC.GT.0.001D0) DISP0 = VFAC*VSTAR
         IF(KW.EQ.13.AND.ZM.LT.1.28) DISP0 = DISP0*ABS(ECSIG)
*
         VKICK = RAN2(IDUM1)*DISP0
         THETA = RAN2(IDUM1)*TWOPI
         SPHI = RAN2(IDUM1)
         X1 = ASIN(SPHI)
         CPHI = COS(X1)
         VK(1) = COS(THETA)*CPHI*VKICK
         VK(2) = SIN(THETA)*CPHI*VKICK
         VK(3) = SPHI*VKICK
         VK2 = VKICK*VKICK

      ELSE
*
*       Generate the kick velocity using a Maxwellian distribution. 
         DISP0 = MAX(DISP,0.D0)
         IF(VFAC.GT.0.001D0) DISP0 = VFAC*VSTAR
         IF(KW.EQ.10.OR.KW.EQ.11) DISP0 = MAX(WDSIG1,0.D0)
         IF(KW.EQ.12) DISP0 = MAX(WDSIG2,0.D0)

c         IF(KW.EQ.13.AND.ZM.LT.1.28)THEN
c		Sambaran 2019.11.19.

         IF(ECS.EQ.1)THEN
            IF(ECSIG.LT.-0.01)THEN
               DISP0 = DISP0*ABS(ECSIG)
            ELSE
               DISP0 = MAX(ECSIG,0.D0)
            ENDIF

c            WRITE(6,*) "ECS-NS formation",
c		Sambaran 2019.11.19.

            if(rank.eq.0)WRITE(6,*) "ECS/AIC NS formation",
     &           " M[M*] M0[M*] K*0 I NAME K* VDISP Time[Myr]: ",
     &           BODY(I)*ZMBAR, BODY0(I)*ZMBAR, KW, I, NAME(I), 
     &           KSTAR(I),DISP0, TTOT*TSTAR
         ENDIF
         IF(KW.EQ.14.AND.BHFLAG.EQ.0) DISP0 = 0.D0

*     Use Henon's method for pairwise components (Douglas Heggie 22/5/97).
         DO 2 K = 1,2
            X1 = RAN2(IDUM1)
            X2 = RAN2(IDUM1)
*     Generate two velocities from polar coordinates S & THETA.
            S = DISP0*SQRT(-2.0*LOG(1.0 - X1))
            THETA = TWOPI*X2
            VK(2*K-1) = S*COS(THETA)
            VK(2*K) = S*SIN(THETA)
 2       CONTINUE

         IF(DISP0.GT.0.001D0)THEN
            VK2 = VK(1)**2 + VK(2)**2 + VK(3)**2
            VKICK = SQRT(VK2)
         ELSE
            VK2 = 0.D0
            VKICK = 0.D0
         ENDIF

      ENDIF

      VK(4) = VKICK

* Impose the maximum WD kick velocity. 
*
      IF(KW.GE.10.AND.KW.LE.12.AND.VKICK.GT.WDKMAX)THEN
         VKICK = WDKMAX
      ENDIF

* Restrict the BH kick velocity by fallback. 
* This could be done better but in the N-body code we only have 
* limited information. 
*     Code added by Sambaran Banerjee and then ported to the LONG GITHIB
*     See arXiv: 1902.07718 (Banerjee, S., Belczynski, C., Fryer, C., et al.)
*
*****
      IF (BHFLAG.GT.1) THEN
         IF (KW.EQ.13.OR.KW.EQ.14) THEN
*********Skip ECS-NS *********
            IF(ECS.EQ.0)THEN
*********Standard momentum-conserving kick *********
               VKICK = VK(4)*(1.0D0 - FBFAC)
*********Convection-asymmetry-driven kick ********
               IF ((KMECH.EQ.2).AND.(MCO.LE.3.5D0))
     &              VKICK = VKICK*(MNSTYP/ZM)
               IF ((KMECH.EQ.2).AND.(MCO.GT.3.5D0))
     &              VKICK = VKICK*(MNSTYP/ZM)*CONVF
*********Collapse-asymmetry-driven kick ********
               IF ((KMECH.EQ.3).AND.(MCO.LE.3.0D0))
     &              VKICK = VKICK*(MNSTYP/ZM)
               IF ((KMECH.EQ.3).AND.(MCO.GT.3.0D0))
     &              VKICK = VKICK*(MNSTYP/ZM)*0.1D0
*********Neutrino-driven kick *****************
***** FOLLOWING DISCUSSION 26.10.2019 - DO NOT TAKE THIS!!!
*              IF (KMECH.EQ.4)
*     &              VKICK = VK(4)*(MIN(ZM,MNUEFF)/ZM)
***********************************************
            ENDIF
      if(rank.eq.0)WRITE (6,190)TTOT,NAME(I),I,KW,KSTAR(I),
     &      TTOT*TSTAR,BODY(I)*ZMBAR, BODY0(I)*ZMBAR,
     &      FBFAC, FBTOT, VKICK, KMECH
  190 FORMAT (' NS/BH FORMATION FALLBACK TIME[NB]',1P,E17.10,
     &        ' NM=',I10,' I=',I10,' KW,KW0=',2I4,
     &        ' TIME[Myr]=',E13.5,' M,M0[*]=',2E13.5,
     &        ' FB FBTOT VK[km/s] KMECH: ',3E12.5,I4)
            END IF
*
*******BH Kerr Metric spin parameter *****
         IF (KW.EQ.14) THEN

           CALL SPIN_SELECT(BHSPINFL,ZMET,MCO,NUMBER)
           aspin = NUMBER
           ASPN(I) = aspin
* JSPIN in N-Body units
           JSPIN = aspin*BODY(I)**2/CLIGHT
* JSPIN in Msun*Rsun**2/Myr
           JSPIN = JSPIN*SPNFAC 
***********************************
          if(rank.eq.0)
     &    WRITE (6,22)  TTOT, I, NAME(I), KSTAR(I),TTOT*TSTAR,
     &        BODY(I)*ZMBAR,SPIN(I),JSPIN,ASPN(I)
   22     FORMAT (' BH-SPIN: TIME[NB]',1P,E17.10,' I',I10,
     &       '  NAME',I10,' KW',I4,' Time[Myr]',E12.5,' M[M*]',E12.5,
     &       '  J[NB] J[MsRs^2/Myr] ASPIN ',3E12.5)
        ENDIF
*******************************************
      ENDIF
*      
      IF (DM.LT.1.0D-10) VKICK = VK(4)   ! Retain VKICK for tiny DM.
*       Limit kick velocity to VDIS+10*VSTAR/10*VST.
*       (disabled)
      IF (IPAIR.GT.0) THEN
          VBF = SQRT(VDIS**2 + 100.0*VSTAR**2)
*       Include large kick velocity to ensure escape of disrupted star.
          IF (KW.LT.10.OR.(KW.LT.13.AND.KZ(25).EQ.0)) VKICK = 1.0*VBF
*         VKICK = MIN(VKICK,VBF)
*         VKICK = MAX(VKICK,VDIS+3.0*VSTAR)
      ELSE
*         VKICK = MIN(VKICK,10.0D0*VSTAR)
*       Ensure escape of massless star.
          IF (BODY(I).EQ.0.0D0) VKICK = 10.0*VSTAR
      END IF
*
      IF (VKICK.NE.VK(4)) THEN
         DO K = 1,3
            VK(K) = VK(K)*VKICK/VK(4)
         ENDDO
         VK2 = VKICK*VKICK
         VK(4) = VKICK
      END IF

*       Skip case of zero kick velocity.
      IF (VKICK.EQ.0.0D0.OR.DISP0.EQ.0.0D0) then
         if(rank.eq.0)
     &    WRITE (6,18)  TTOT, I, NAME(I), KSTAR(I), KW, KC,
     &         TTOT*TSTAR,BODY0(I)*ZMBAR,ZM,SQRT(VI2)*VSTAR,
     &         VKICK*VSTAR, SQRT(VF2)*VSTAR, VK(4),FBFAC
   18     FORMAT (' ZERO VELOCITY KICK: TIME[NB]',1P,E17.10,' I',I10,
     &         '  NAME',I10,' K*0',I4,'  K*',I4,'  K*(ICM)',I4,
     &         '  Time[Myr]',E12.5,' M0[M*]',E12.5,' MN[M*]',E12.5,
     &         '  VI[km/s]',E12.5,' VK[km/s]',E12.5' VF[km/s]',E12.5,
     &         '  VK0[km/s]',E12.5,' FB',E12.5)
         GO TO 30
      ENDIF

*
*
*     Add truncated/full kick velocity and initialize X0DOT.
      VKICK = VKICK/VSTAR
      VI2 = 0.0
      VF2 = 0.0
      CALL JPRED(I,TIME,TIME)
      DO 10 K = 1,3
          VI2 = VI2 + XDOT(K,I)**2
          XDOT(K,I) = XDOT(K,I) + VK(K)/VSTAR
          X0DOT(K,I) = XDOT(K,I)
          VF2 = VF2 + XDOT(K,I)**2
   10 CONTINUE
*
*     Modify energy loss due to increased velocity of single particle.
      DETMP = - 0.5*BODY(I)*(VF2 - VI2)
      ECDOT = ECDOT + DETMP
*     ks MPI communication
*     call ksparmpi(K_store,K_real8,K_ECDOT,0,0,DETMP)
      NKICK = NKICK + 1
*
*       Replace final velocity by relative velocity for binary kick.
      IF (IPAIR.GT.0) THEN
          JP = KVEC(I)
          J = I + 1
          IF (I.EQ.2*JP) J = I - 1
          VF2 = 0.0
          CALL JPRED(J,TIME,TIME)
          DO 15 K = 1,3
              VF2 = VF2 + (XDOT(K,I) - XDOT(K,J))**2
   15     CONTINUE
          HNEW = 0.5*VF2 - (BODY(I) + BODY(J))/RI
*       Exclude colliding WDs.
          IF (BODY(I) + BODY(J).EQ.0.0D0) THEN
              EB1 = 0.0
          ELSE
              EB1 = BODY(I)*BODY(J)/(BODY(I) + BODY(J))*HNEW
          END IF
          IF (EB1.LT.0.0) THEN
              EKICK = EKICK - EB1
              EGRAV = EGRAV - EB1
*     ks MPI communicaton EKICK EGRAV
*             call ksparmpi(K_store,K_real8,K_EGRAV,0,0,-EB1)
*             call ksparmpi(K_store,K_real8,K_EKICK,0,0,-EB1)
          END IF
          IPAIR = 0
      END IF
*
*     IF (NKICK.LT.50.OR.NAME(I).LE.2*NBIN0.OR.
*    &    (KW.GE.13.AND.TTOT*TSTAR.GT.100.0)) THEN
          ZM = BODY(I)*ZMBAR
          if(rank.eq.0)
     &    WRITE (6,20)  TTOT, I, NAME(I), KSTAR(I), KW, KC,
     &         TTOT*TSTAR,BODY0(I)*ZMBAR,ZM,SQRT(VI2)*VSTAR,
     &         VKICK*VSTAR, SQRT(VF2)*VSTAR, VK(4),FBFAC
   20     FORMAT (' FULL VELOCITY KICK: TIME[NB]',1P,E17.10,' I',I10,
     &         '  NAME',I10,' K*0',I4,'  K*',I4,'  K*(ICM)',I4,
     &         '  Time[Myr]',E12.5,' M0[M*]',E12.5,' MN[M*]',E12.5,
     &         '  VI[km/s]',E12.5,' VK[km/s]',E12.5' VF[km/s]',E12.5,
     &         '  VK0[km/s]',E12.5,' FB',E12.5)
          KC = 0
*     END IF
*
*       Highlight BH/NS velocities below 4 times rms velocity.
      IF (VKICK.LT.4.0*SQRT(0.5).AND.KW.GE.13) THEN
          if(rank.eq.0)
     &    WRITE (6,25)  I, NAME(I), KW, VKICK*VSTAR, SQRT(VF2)*VSTAR
   25     FORMAT (' LOW KICK:    I',I10,'  NAME',I10,'  K*',I4,
     &         '  VK[km/s]',F7.2,'  VF[km/s]',F7.2)
      END IF
*
*       Include optional list of high-velocity particles (double counting!).
*     IF (KZ(37).GT.0) THEN
*         CALL HIVEL(I)
*     END IF
*
   30 RETURN
*
      END



      
********** SUBROUTINE FOR SPIN INITIALIZATION **************

      SUBROUTINE SPIN_SELECT(SPINFLAG, METALLICITY, MCORE,NUMBER)

      Include 'kspars.h'
      INCLUDE 'common6.h'
      REAL*8 NUMBER
      REAL*8 METALLICITY, MCORE
      INTEGER SPINFLAG
            
      CALL BSPIN(SPINFLAG,METALLICITY,MCORE,NUMBER)
         
      END SUBROUTINE


      
****************SPIN SELECTION ******************

      

      SUBROUTINE BSPIN(SPINFLAG,METALLICITY,MCORE,SPINVALUE)

      Include 'kspars.h'
      INCLUDE 'common6.h'
      REAL*8 aspin, aconst, bconst, alow, mone, mtwo, JSPIN
      REAL*8 aone, bone, atwo, btwo
      REAL*8 NUMBER
      REAL*8 METALLICITY, MCORE
      REAL*8 SPINVALUE
      INTEGER SPINFLAG

      
      NUMBER = -1000.D0
      
      IF(SPINFLAG .EQ. 0)THEN
         aspin = 0.0D0

      ELSE IF(SPINFLAG.EQ.1)THEN
***   BH natal spin uniform distribution
         aspin = RAND()

      ELSE IF(SPINFLAG.EQ.2)THEN
***   BH natal spin Maxwellian distribution
         CALL GAUSS(NUMBER)         
         aspin = NUMBER
      ELSE IF(SPINFLAG.EQ.3)THEN
***   BH natal spin Gaussian distribution
         CALL MAXW(NUMBER)
         aspin = NUMBER
      ELSE IF(SPINFLAG.EQ.4)THEN
***   BH natal spin from Geneva models (experimental)
        IF (METALLICITY .LT. 0.001D0) THEN
           alow = 0.25D0
           mtwo = 38.8D0
           mone = 32.0D0
           aconst = -0.088D0
           bconst = 3.666D0
        ELSEIF (METALLICITY.GE.0.001D0.AND.METALLICITY.LT.0.004D0) THEN
           alow = 0.0D0
           mtwo = 27.7D0
           mone = 18.0D0
           aconst = -0.088D0
           bconst = 2.434D0
        ELSEIF (METALLICITY.ge.0.004D0.and.METALLICITY.lt.0.01D0) THEN
           alow = 0.25D0
           mtwo = 37.8D0
           mone = 31.0D0
           aconst = -0.088D0
           bconst = 3.578D0
        ELSE
           alow = 0.13D0
           mtwo = 24.2D0
           mone = 16.0D0
           aconst = -0.088D0
           bconst = 2.258D0
        ENDIF
        
        IF (MCORE.LE.mone) THEN
           aspin = 0.85D0
        ELSEIF (MCORE.GT.mone.AND.MCORE.LT.mtwo) THEN
           aspin = (aconst*MCORE) + bconst
        ELSE
           aspin = alow
        ENDIF
        IF (aspin.LT.0.0D0) THEN
           aspin = 0.0D0
        ENDIF

        
      ELSEIF(SPINFLAG.EQ.5)THEN

********** BH natal spin from MESA models (experimental)
        IF (METALLICITY.LT.0.001D0) THEN
           aone = -0.0010D0
           bone = 0.125D0
           atwo = 0.0D0
           btwo = 0.0D0
           mone = 1.0E+10
        ELSEIF (METALLICITY.GE.0.001D0.AND.METALLICITY.LT.0.004D0) THEN
           aone = 0.0076D0
           bone = 0.050D0
           atwo = -0.0019D0
           btwo = 0.165D0
           mone = 12.09D0
        ELSEIF (METALLICITY.GE.0.004D0.AND.METALLICITY.LT.0.01D0) THEN
           aone = -0.0006D0
           bone = 0.105D0
           atwo = 0.0D0
           btwo = 0.0D0
           mone = 1.0E+10
        ELSE
           aone = -0.0016D0
           bone = 0.115D0
           atwo = 0.0D0
           btwo = 0.0D0
           mone = 1.0D+10
        ENDIF
        IF (MCORE.LE.mone) THEN
           aspin = (aone*MCORE) + bone
        ELSE
           aspin = (atwo*MCORE) + btwo
        ENDIF
        IF (aspin.LT.0.0D0)THEN
           aspin = 0.0D0
        ENDIF




              

      ENDIF


      SPINVALUE = aspin
      

      END SUBROUTINE




************ ROUTINES NEEDED ******************+      
      SUBROUTINE GAUSS(GSS)

      REAL *8 PDF,MU,SIGMA,PDFMAX,PX,PRE
      REAL *8 PDFX
      REAL *8 RAN2
      REAL *8 GSS
      
      MU = 0.5
      SIGMA=0.2D0
      PI = 3.14159265358979D0
           
      PDFMAX = 1./SQRT(2.D0*PI*SIGMA*SIGMA)

      DO WHILE (1 .GT. 0)
         PDFX = PDFMAX*RAND()
         PX = RAND()
         PRE =1./SQRT(2.D0*PI*SIGMA*SIGMA)
         PDF = PRE * EXP(-0.5*((PX-MU)/SIGMA)**2.D0)
         
         IF(PDF .GT. PDFX)THEN
            GSS = PX
            GO TO 10 
         ENDIF

         !WRITE(*,*) PDFX,PX,PDF,PDFMAX
         
         
      END DO

 10   CONTINUE
      
      
      END SUBROUTINE


      
      SUBROUTINE MAXW(MXL)

      REAL *8 PDF,MU,SIGMA,PDFMAX,PX,PRE
      REAL *8 PDFX
      REAL *8 RAN2
      REAL *8 MXL
      
      SIGMA=0.2D0
      PI = 3.14159265358979D0


      PX  = 2.D0*SIGMA*SQRT(2.D0/PI)
      PRE = SQRT(2.D0/PI)/SIGMA**3.D0 
      PDF = PRE * PX**2.D0*EXP(-PX**2.D0/(2.*SIGMA**2.D0))
      PDFMAX = PDF
      
      DO WHILE (1 .GT. 0)
         PDFX = PDFMAX*RAND()
         PX = RAND()
         PRE = SQRT(2.D0/PI)/SIGMA**3.D0 
         PDF = PRE * PX**2.D0*EXP(-PX**2.D0/(2.*SIGMA**2.D0))
         IF(PDF .GT. PDFX)THEN
            MXL = PX
            GO TO 10 
         ENDIF

         !WRITE(*,*) PDFX,PX,PDF,PDFMAX
         
         
      END DO

 10   CONTINUE
      
      
      END SUBROUTINE
