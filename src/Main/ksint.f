      SUBROUTINE KSINT(I1)
*
*
*       Regularized integration.
*       ------------------------
*
      Include 'kspars.h'
      INCLUDE 'common6.h'
      include 'timing.h'
*     Safe for parallel, no value change, used value: tmdis,namem,nameg,kstarm
      COMMON/BINARY/  CM(4,MMAX),XREL(3,MMAX),VREL(3,MMAX),
     &                HM(MMAX),UM(4,MMAX),UMDOT(4,MMAX),TMDIS(MMAX),
     &                NAMEM(MMAX),NAMEG(MMAX),KSTARM(MMAX),IFLAGM(MMAX)
*     No value change, used value: TOSC,namec
      COMMON/MODES/  EB0(NTMAX),ZJ0(NTMAX),ECRIT(NTMAX),AR(NTMAX),
     &               BR(NTMAX),EOSC(4,NTMAX),EDEC(NTMAX),TOSC(NTMAX),
     &               ZP(NTMAX),ES(NTMAX),CZ(2,NTMAX),IOSC(NTMAX),
     &               NAMEC(NTMAX)
*     Safe for parallel, no value change
      COMMON/SLOW0/  RANGE,ISLOW(10)
*      COMMON/GAMDOT/  DGAM
      REAL*8  UI(4),UIDOT(4),XI(6),VI(6),FP(6),FD(6),A_EIN,CL2
      INTEGER RES
      LOGICAL IQ,LBRAKE
*
*       Set second component, pair index & c.m. index.
      I2 = I1 + 1
      IPAIR = KVEC(I1)
      I = N + IPAIR
      IPHASE = 0
      call jpred(i,time,time)
*
      CL2 = CLIGHT**2   
*
*       Define perturber membership & inverse c.m. mass.
      NNB0 = LIST(1,I1)
      BODYIN = 1.0/BODY(I)
*
      SEMI = -0.5*BODY(I)/H(IPAIR)
      ECC2 = (1.0-R(IPAIR)/SEMI)**2+TDOT2(IPAIR)**2/(SEMI*BODY(I))
      ECC = SQRT(ECC2)
      A_EIN = 0.D0
        LBRAKE = KZ273.EQ.3.AND.
     &    (KSTAR(I1).GE.10.AND.KSTAR(I1).LE.14).AND.
     &    (KSTAR(I2).GE.10.AND.KSTAR(I2).LE.14).AND.
     &    H(IPAIR).LT.0.D0.AND.ECC.GT.0.D0
        IF (LBRAKE) A_EIN = 3.0*TWOPI*BODY(I)/(SEMI*CL2*(1-ECC2))
*       Check for further unperturbed motion.
*       Make sure relativistic binary is not unperturbed.
      IF (NNB0.EQ.0.AND.H(IPAIR).LT.0.0) THEN
         call cputim(tt1)
          CALL UNPERT(IPAIR)
          call cputim(tt2)
          if(rank.eq.0)ttup = ttup + (tt2-tt1)*60.
          GO TO 100
      END IF
*
*       Perform KS prediction of U, UDOT & H.
      CALL KSPRED(IPAIR,I1,I,BODYIN,UI,UIDOT,XI,VI)
*
*       Obtain the perturbing force & derivative.
      CALL KSPERT(I1,NNB0,XI,VI,FP,FD)
*
*       Save old radial velocity & relative perturbation and set new GAMMA.
      RDOT = TDOT2(IPAIR)
*     G0 = GAMMA(IPAIR)
      GI = SQRT(FP(1)**2 + FP(2)**2 + FP(3)**2)*R(IPAIR)**2*BODYIN
      GAMMA(IPAIR) = GI
*
*       Apply the Hermite corrector.
      CALL KSCORR(IPAIR,UI,UIDOT,FP,FD,TD2,TDOT4,TDOT5,TDOT6)
*       Increase regularization time-step counter and update the time.
      NSTEPU = NSTEPU + 1
      T0(I1) = TIME
*
*       Define useful scalars.
      RI = R(IPAIR)
      HI = H(IPAIR)
*
*       Initialize termination indicator and check for large perturbation.
      IQ = .FALSE.
*     Reduce the criterion from 0.25 to 0.1 to reduce the energy error
      IF (GI.GT.0.10) GO TO 2
      IF (GI.LT.0.03) THEN
          JCOMP = 0
          GO TO 20
      END IF
      CALL FLYBY(I,ITERM)
      IF (ITERM.EQ.0.AND.KSTAR(I).LT.0) THEN
          IQ = .TRUE.
      END IF
      IF (ITERM.EQ.1) THEN
*       Delay chain regularization search until near end of block-step.
          IF (KZ(15).GT.0.AND.TIME + STEP(I1).GT.TBLOCK) THEN
              CALL IMPACT(I)
              IF (IPHASE.GT.0) GO TO 100
          END IF
      ELSE IF (ITERM.EQ.2) THEN
          IQ = .TRUE.
          GO TO 20
      ELSE
          GO TO 20
      END IF
*
*       Find the dominant body for large perturbations.
    2 S = 4.0*STEP(I)
      FMAX = BODY(I)/RI**2
*       Initialize JCOMP for prediction and optional diagnostics in KSTERM.
      JCOMP = 0
      DO 10 L = 2,NNB0+1
          J = LIST(L,I1)
*       Only search bodies within four times of the c.m. time-step.
          IF (STEP(J).GT.S) GO TO 10
*       Compare strong perturber and either component with current pair.
          DO 5 K = I1,I2
              RIJ2 = (X(1,J) - X(1,K))**2 + (X(2,J) - X(2,K))**2 +
     &                                      (X(3,J) - X(3,K))**2
              IF (BODY(J) + BODY(K).GT.RIJ2*FMAX) JCOMP = J
    5     CONTINUE
   10 CONTINUE
*
*       Set termination if strong perturber <= N forms dominant pair.
      IF (JCOMP.GT.0.OR.GI.GT.1.0) THEN
*       Check optional binary search.
*         IF (KZ(4).GT.0) THEN
*             DGAM = GI - G0
*             K = KZ(4)
*             CALL EVOLVE(IPAIR,K)
*         END IF
*       Terminate the binary when close particle is KS pair
         IF (JCOMP.GT.N) IQ = .TRUE.
         IF (JCOMP.LE.N.OR.GI.GT.1.0) IQ = .TRUE.
      END IF
*
*       Check termination of hyperbolic encounter (R > R0 or R > 2*RMIN).
   20 IF (HI.GT.0.0D0.AND.NAME(I).GT.0) THEN
          IF ((RI.GT.R0(IPAIR).AND.GI.GT.GMAX).OR.RI.GT.2.0*RMIN.OR.
     &        (GI.GT.0.5.AND.TD2.GT.0.0)) THEN
*       Skip termination delay in case of velocity kick (cf. routine KSTERM).
              IF (HI.LT.100.0.OR.GI.GT.0.1.OR.RI.GT.5.0*RMIN) THEN
                  IQ = .TRUE.
              END IF
          END IF
      END IF
*
*       Choose basic regularized step using binding energy or lower limit.
      IF (ABS(HI).GT.ECLOSE) THEN
          W1 = 0.5/ABS(HI)
      ELSE
          W1 = R0(IPAIR)*BODYIN
          W2 = 0.5/ABS(HI)
          W1 = MIN(W1,W2)
          IF (RI.GT.R0(IPAIR)) W1 = W1*R0(IPAIR)/RI
*       Maximum square step for soft binaries & weak hyperbolic pairs.
          IF (HI.LT.0.0D0) THEN
*       Include case of hard binary with massive components or merger.
              W2 = -0.5/HI
              IF (NAME(I).LT.0) THEN
                  W1 = RI*BODYIN
              END IF
              W1 = MIN(W2,W1)
          END IF
      END IF
*
*       Include perturbation factor in predicted step.
      IF (GI.LT.0.0005) THEN
*       Use second-order expansion of cube root for small perturbations.
          W3 = 333.3*GI
          W2 = SQRT(W1)/(1.0 + W3*(1.0 - W3))
      ELSE
          W3 = 1.0 + 1000.0*GI
          W2 = SQRT(W1)/W3**0.3333
      END IF
*
*       Form new regularized step (include inertial factor).
      DTU = ETAU*W2
      DTU = MIN(1.2*DTAU(IPAIR),DTU)
*
*       Include convergence criterion DH = H'*DTU + H''*DTU**2/2 = 0.001*|H|.
      IF (GI.GT.1.0D-04) THEN
          DH = 1.0E-03*MAX(ABS(H(IPAIR)),ECLOSE)
          XF = 2.0*DH/ABS(HDOT2(IPAIR))
          YF = HDOT(IPAIR)/HDOT2(IPAIR)
          DTU1 = SQRT(XF + YF**2) - ABS(YF)
          DTU = MIN(DTU1,DTU)
      END IF
*
*       Check pericentre step reduction for perturbed spiral.
      IF (KSTAR(I).EQ.-2.AND.TD2.LT.0.0) THEN
          SEMI = -0.5*BODY(I)/HI
          IF (RI.LT.SEMI) THEN
*       Predict radial velocity for step DTU (note scaled coefficients).
              RD = ((ONE3*TDOT5*DTU + TDOT4)*DTU +
     &                                TDOT3(IPAIR))*DTU + 2.0*TD2
*       Adopt pericentre step with 1% safety factor (small TDOT4 is OK).
              IF (RD.GT.0.0) THEN
                  A2 = 0.5*TDOT3(IPAIR)/TDOT4
                  DTU1 = SQRT(A2**2 - 2.0*TD2/TDOT4) - A2
                  DTU1 = 1.01*MAX(DTU1,1.0D-10)
                  DTU = MIN(DTU1,DTU)
              END IF
          END IF
      END IF
*
*       Reset reference energy and generate new Stumpff coefficients.
      H0(IPAIR) = H(IPAIR)
   30 Z = -0.5D0*H(IPAIR)*DTU**2
      CALL STUMPF(IPAIR,Z)
      Z5 = SF(6,IPAIR)
      Z6 = SF(7,IPAIR)
      DT12 = ONE12*DTU*Z6
*
*       Convert to physical time units modified by Stumpff coefficients.
      STEP(I1) = (((((TDOT6*DT12 + TDOT5*Z5)*0.2*DTU + 0.5D0*TDOT4)*DTU
     &                     + TDOT3(IPAIR))*ONE6*DTU + TD2)*DTU + RI)*DTU
*
*       Ensure that regularized step is smaller than the c.m. step.
      IF (STEP(I1).GT.STEP(I).AND.HI.LT.0) THEN
          DTU = 0.5D0*DTU
          GO TO 30
      END IF
*
      DTAU(IPAIR) = DTU
*
*       GR braking for compact object binaries RSp 2019/2022
      SEMI = -0.5*BODY(I)/HI
      ECC2 = (1.0-R(IPAIR)/SEMI)**2+TDOT2(IPAIR)**2/(SEMI*BODY(I))
      ECC = SQRT(ECC2)
      QPERI = SEMI*(1.0D0 - ECC)
        LBRAKE = KZ273.EQ.3.AND.
     &    (KSTAR(I1).GE.10.AND.KSTAR(I1).LE.14).AND.
     &    (KSTAR(I2).GE.10.AND.KSTAR(I2).LE.14).AND.
     &    (KSTAR(I2).GE.10.AND.KSTAR(I2).LE.14).AND.ECC.GT.0.D0
* JFNS Adding Hyperbolic-friendly checks
*     &    HI.LT.0.D0.AND.ECC.GT.0.D0

        IF (LBRAKE) THEN
*       GR breaking for compact obj. define new binary type March 2019
           A_EIN = 3.0*TWOPI*BODY(I)/(SEMI*CL2*(1-ECC2))
           TORB = TWOPI*SQRT(SEMI**3/BODY(I))
           RSCHW = 2.0*BODY(I)/CL2
           RES = 0
*
*          IF(rank.eq.0.AND.A_EIN.GT.GMIN)WRITE(6,666)
*    &   RES,TTOT,STEP(I1),I,IPAIR,LIST(1,I1),
*    &   NAME(I1),NAME(I2),NAME(I),KSTAR(I1),KSTAR(I2),KSTAR(I),
*    &   BODY(I1)*ZMBAR,BODY(I2)*ZMBAR,ECC,SEMI,QPERI,RSCHW,
*    &   H(IPAIR),GAMMA(IPAIR),A_EIN,TORB
*666  FORMAT(1X,' GR KSINT1 RES T STEP',I3,1P,2E13.5,' I IP NPERT',
*    &   I10,2I6,' NM1,2,S=',3I10,' KW1,2,S=',3I4,' M1,2[M*]',2E13.5,
*    &   ' e,a,QP,RS[NB]=',4E13.5,' H, GAMMA=',2E13.5,
*    &   ' A_EIN, TORB=',2E13.5)
*
*       Special binary type -25 for GR shrinking binary
*
           DTGW(IPAIR) = STEP(I1)
           CALL GW_DECISION(SEMI,BODY(I1),BODY(I2),
     &         CLIGHT,ECC,DTGW(IPAIR),RES,TGR,KMIN)
*
           IF(RES.EQ.1.AND.GAMMA(IPAIR).LT.1.D-1) THEN
              KSTAR(I) = -25
              CALL KSTIDE(IPAIR,QPERI)
      if(rank.eq.0)WRITE(6,665)
     &   RES,KMIN,TTOT,DTGW(IPAIR),STEP(I1),I,IPAIR,LIST(1,I1),
     &   NAME(I1),NAME(I2),NAME(I),KSTAR(I1),KSTAR(I2),KSTAR(I),
     &   BODY(I1)*ZMBAR,BODY(I2)*ZMBAR,ECC,SEMI,QPERI,RSCHW,
     &   H(IPAIR),GAMMA(IPAIR),A_EIN,TORB,TGR
 665  FORMAT(1X,' GR KSINT2 RES KMIN T DTGW STEP',2I3,1P,3E13.5,
     &   ' I IP NPERT',
     &   I10,2I6,' NM1,2,S=',3I10,' KW1,2,S=',3I4,' M1,2[M*]',2E13.5,
     &   ' e,a,QP,RS[NB]=',4E13.5,' H, GAMMA=',2E13.5,
     &   ' A_EIN, TORB, TGR(PM)=',3E13.5)
*       Prepare coal flag if PERI < 25 R_SCHW
            SEPMRG = 2.5D1*RSCHW
               IF(DABS(QPERI).LT.SEPMRG.OR.TGR.LT.TORB) THEN
               if(rank.eq.0) PRINT *,' GR KSINT COLL: QP SEPMRG C ',
     &         ' RSCH ECC SEMI ',QPERI,SEPMRG,CLIGHT,RSCHW,ECC,SEMI
                  IPHASE = -1
                  GO TO 100
               END IF
           END IF
        END IF
*       End 2nd GR treatment
*
*       See whether the KS slow-down procedure is activated.
      IMOD = KSLOW(IPAIR)
      ZMOD = 0
      IF (IMOD.GT.1) THEN
          ZMOD = FLOAT(ISLOW(IMOD))
          STEP(I1) = ZMOD*STEP(I1)
      END IF
*
*       Check diagnostic print option.
      IF (KZ(10).GE.3.and.rank.eq.0) THEN
          WRITE (6,40)  IPAIR, TIME+TOFF, H(IPAIR), RI, DTAU(IPAIR),
     &                  GI, STEP(I1), LIST(1,I1), IMOD
   40     FORMAT (3X,'KS MOTION',I6,2F10.4,1P,4E11.3,2I4)
      END IF
*
*       Employ special termination criterion in merger case.
      IF (NAME(I).LT.0) THEN
*       Terminate if apocentre perturbation > 0.25 (R > SEMI) or GI > 0.25.
          IF (HI.LT.0.0) THEN
              SEMI = -0.5*BODY(I)/HI
*              ECC2 = (1.0 - RI/SEMI)**2 + TDOT2(IPAIR)**2/(BODY(I)*SEMI)
*              A0 = SEMI*(1.0 + SQRT(ECC2))/RI
*       Replace eccentricity calculation with typical value.
              A0 = 1.5*SEMI/RI
              GA = GI*A0*A0*A0
              IF (GA.GT.0.25.AND.RI.GT.SEMI) IQ = .TRUE.
*       Terminate wide orbits if perturber number is relatively large.
              IF (RI.GT.20*RMIN.AND.NNB0.GT.0.8*LIST(1,I)) IQ = .TRUE.
*              IF (GI.GT.0.1.AND.RI.GT.RMIN) IQ = .TRUE.
              IF (GI.GT.0.25) IQ = .TRUE.
              IF (MIN(BODY(I1),BODY(I2)).LT.0.05*BODYM) THEN
                  IF (GI.GT.2.0D-04) IQ = .TRUE.
              END IF
          ELSE
              IF (TD2.GT.0.0.AND.(GI.GT.GMAX.OR.RI.GT.RMIN)) IQ = .TRUE.
          END IF
          IF (.NOT.IQ) GO TO 60
      END IF
*
*     For massive black hole ks, try to avoid terminated with large seperation
      IF(KZ(24).EQ.1.AND.BODY(I)/BODYM.GT.200.AND.RI.GT.10.0*RMIN) THEN
         IQ = .true.
      END IF

*       Delay termination until end of block for large perturbations.
      IF (IQ) THEN
          DTR = TBLOCK - TIME
          IF (DTR.LT.STEP(I1)) GO TO 90
      END IF
*
*       Check standard termination criterion (suppress on IQ = .true.).
*     IF (RI.GT.R0(IPAIR)) THEN
      IF (RI.GT.R0(IPAIR).AND.RI.GT.2.0*RMIN.AND..NOT.IQ) THEN
*       See whether termination can be delayed for sufficient perturbers.
          IF (NNB0.LT.0.80*LIST(1,I).AND.GI.LT.0.1) GO TO 60
*
*       See whether termination can be delayed for intermediate energies.
c$$$          IF (RI.GT.RMIN) THEN
c$$$              A3 = RMIN*ABS(HI)*BODYIN
c$$$              GIMAX = A3*A3*A3
c$$$              IF (GI.LT.GIMAX) GO TO 60
*       Check updating of R0 for newly hardened binary orbit.
          IF (HI.LT.-ECLOSE) THEN
             SEMI = -0.5*BODY(I)/HI
             R0(IPAIR) = MAX(RMIN,2.0D0*SEMI) 
             GO TO 70
          END IF
c$$$          END IF
*
*         IF (KZ(4).GT.0.AND.GI.GT.GPRINT(1)) THEN
*             DGAM = GI - G0
*             K = KZ(4)
*             DO 55 L = 2,K
*                 IF (GI.LT.GPRINT(L)) THEN
*                     CALL EVOLVE(IPAIR,L-1)
*                     GO TO 90
*                 END IF
*  55         CONTINUE
*             CALL EVOLVE(IPAIR,K)
*         END IF
          GO TO 90
      END IF
*
*       End integration cycle for hyperbolic motion.
   60 IF (HI.GE.0.0D0) THEN
          IF (RDOT*TD2.LT.0.0D0) THEN
*       Determine pericentre for hyperbolic two-body motion.
              SEMI = -0.5D0*BODY(I)/HI
              ECC2 = (1.0-RI/SEMI)**2+TDOT2(IPAIR)**2/(SEMI*BODY(I))
              QPERI = SEMI*(1.0D0 - SQRT(ECC2))
              DMIN2 = MIN(DMIN2,QPERI)
*
*       Check optional tidal interaction or stellar collision.
              IF (KZ(19).GE.3.AND.KSTAR(I).LT.10) THEN
                  VINF = SQRT(2.0*HI)*VSTAR
                  KS1 = KSTAR(I1)
                  KS2 = KSTAR(I2)
                  RX = MAX(RADIUS(I1),RADIUS(I2))
*       Determine maximum periastron factor for capture (VINF in km/sec).
                  IF (KZ(27).LE.2) THEN
                      RFAC = RPMAX2(RADIUS(I1),RADIUS(I2),BODY(I1),
     &                              BODY(I2),KS1,KS2,VINF)
                      RCAP = RFAC*RX
                  ELSE
                      DV = SQRT(2.0*HI)
*       Note that Quinlan & Shapiro function returns actual distance.
                      RCAP = RPMAX(BODY(I1),BODY(I2),VSTAR,DV,QPERI)
                  END IF
                  IF (QPERI.LT.5.0*RX) THEN
                      if(rank.eq.0)
     &                WRITE (54,54)  TTOT, NAME(I1), NAME(I2), KS1,
     &                               KS2, VINF, RCAP*SU, RX*SU, QPERI*SU
   54                 FORMAT ('CLOSE   Time[NB] NAME(I1) NAME(I2) ',
     &                     'K*(I1) K*(I2) VINF[km/s] RCAP[R*] RX[R*] ',
     &                     'PERI[R*] ',1P,E26.17,0P,2I2,2I4,4F12.5)
                  END IF
                  IF (QPERI.LT.RCAP) THEN
                      J1 = I1
                      IF (RADIUS(I2).GT.RADIUS(I1)) J1 = I2
                      FAC = 0.5*BODY(I)/BODY(J1)
*       Adopt collision criterion of Kochanek (Ap.J. 385, 604, 1992).
                      IF (KZ(27).LE.2) THEN
                          RCOLL = 1.7*FAC**0.3333*RADIUS(J1)
                      ELSE
                          RCOLL = 6.0*BODY(I)/CLIGHT**2
                      END IF
                      RI2 = 0.0
                      VI2 = 0.0
                      DO 61 K = 1,3
                          RI2 = RI2 + (X(K,I) - RDENS(K))**2
                          VI2 = VI2 + XDOT(K,I)**2
   61                 CONTINUE
                      if(rank.eq.0)then
                      WRITE (55,58)  TTOT, IPAIR, NAME(I1), NAME(I2),
     &                        KS1, KS2, KSTAR(I), VINF,
     &                        SQRT(ECC2), HI, R(IPAIR), SEMI,
     &                        QPERI, BODY(I1), BODY(I2),
     &                        BODY(I)*ZMBAR,
     &                        SQRT(RI2)/RC, SQRT(VI2)*VSTAR,
     &                        RHOD, RADIUS(I1)*SU, RADIUS(I2)*SU,
     &                        RCAP, RADIUS(J1)/QPERI, RCOLL/QPERI
   58                 FORMAT ('RPMAX:  Time[NB] IPAIR NAME(I1) ',
     &                     'NAME(I2) K*(I1) K*(I2) K*(ICM) VINF[km/s] ',
     &                     'ECC H[NB] R12[NB] SEMI[NB] PERI[NB] ',
     &                     'M(I1)[NB] M(I2)[NB] M(ICM)[M*] RI[RC] ',
     &                     'VI[km/s] RHOD RS(I1)[R*] RS(I2)[R*] ',
     &                     'RCAP[NB] RX/PERI RCOLL/PERI',1P,E25.17,0P,
     &                     3I12,3I4,2F12.5,1P,7E16.7,0P,8F12.6)
                      end if
                      CALL FLUSH(55)
                      IF (QPERI.LT.RCOLL) THEN
c$$$*       Obtain KS variables at pericentre before merging into one body.
c$$$                          CALL KSPERI(IPAIR)
c$$$                          KSPAIR = IPAIR
c$$$                          IQCOLL = -2
c$$$                          CALL CMBODY(2)
                         IPHASE = -1
                      ELSE IF (KSTAR(I).GE.0.AND.KZ(27).GT.0) THEN
                         CALL KSTIDE(IPAIR,QPERI)
                      END IF
                  END IF
*       Check options for artificial collisions.
              ELSE IF (KZ(27).EQ.-1) THEN
                  RFAC = 2.0
                  IF (QPERI.LT.RFAC*MAX(RADIUS(I1),RADIUS(I2))) THEN
                      J1 = I1
                      IF (RADIUS(I2).GT.RADIUS(I1)) J1 = I2
                      FAC = 0.5*BODY(I)/BODY(J1)
*       Adopt collision criterion of Kochanek (Ap.J. 385, 604, 1992).
                      RCOLL = 1.7*FAC**0.3333*RADIUS(J1)
                      IF (QPERI.LT.RCOLL) THEN
                          CALL TOUCH(IPAIR,I1,I2,RCOLL)
                      END IF
                  END IF
              END IF
          END IF
          GO TO 100
      END IF
*
*       Check perturbation threshold (H < 0 & GAMMA > GMAX).
*     IF (KZ(4).EQ.0.OR.G0.LT.GMAX) GO TO 70
*
*     K = KZ(4)
*     DO 65 L = 1,K
*         IF ((G0 - GPRINT(L))*(GI - GPRINT(L)).LE.0.0) THEN
*             IF (L.EQ.1) THEN
*                 W1 = -0.5*BODY(I)/HI
*                 W2 = W1*BODYIN
*                 TK = TWOPI*W1*SQRT(W2)
*             END IF
*
*       Estimate smallest permitted output interval at new level.
*             DTCRIT = TK*ORBITS(L)
*             IF (TIME - TLASTB(L).LT.DTCRIT) GO TO 70
*             DGAM = GI - G0
*             CALL EVOLVE(IPAIR,L)
*             GO TO 70
*         END IF
*  65 CONTINUE
*
*       Check for partial reflection during approach (NB! only IMOD = 1).
*  70 IF (GI.LT.GMIN.AND.TD2.LT.0.0D0) THEN
*       Skip apocentre position itself.
*         IF (RDOT.LT.0.0D0.AND.IMOD.EQ.1) THEN
*             IF (KZ(25).GT.0) CALL FREEZE(IPAIR)
*             GO TO 100
*         END IF
*     END IF
*
*       Determine new perturbers for binary at apocentre turning point.
   70 IF (RDOT*TD2.GE.0.0D0) GO TO 100
      SEMI = -0.5D0*BODY(I)/HI
*
*       Check minimum two-body separation just after pericentre.
      IF (RDOT.LT.0.0D0) THEN
*       Obtain pericentre by Mikkola's algorithm (GAMMA < 0.001).
          IF (GI.LT.0.001) THEN
              CALL PERI(UI,UIDOT,RI,BODY(I1),BODY(I2),QPERI)
          ELSE
              QPERI = RI
          END IF
          DMIN2 = MIN(DMIN2,QPERI)
*
*       Check optional tidal interaction or stellar collision (skip merger).
          IF (KZ(19).GE.3.AND.KSTAR(I).LE.10.AND.NAME(I).GT.0) THEN
              RFAC = 5.0
              IF (KZ(27).LE.2) THEN
                  IF (KZ(27).EQ.1) RFAC = 4.0
                  RX = RFAC*MAX(RADIUS(I1),RADIUS(I2))
              ELSE
                  RX = RPMIN(BODY(I1),BODY(I2),VSTAR,HI,QPERI)
              END IF
              IF (QPERI.LT.RX) THEN
                  J1 = I1
                  IF (RADIUS(I2).GT.RADIUS(I1)) J1 = I2
                  FAC = 0.5*BODY(I)/BODY(J1)
*       Adopt collision criterion of Kochanek (Ap.J. 385, 604, 1992).
                  IF (KZ(27).LE.2) THEN
                      RCOLL = 1.7*FAC**0.3333*RADIUS(J1)
                  ELSE
                      RCOLL = 6.0*BODY(I)/CLIGHT**2
                  END IF
                  IF (QPERI.LT.RCOLL) THEN
c$$$*       Obtain KS variables at pericentre before merging into one body.
c$$$                      CALL KSPERI(IPAIR)
c$$$                      KSPAIR = IPAIR
c$$$                      IQCOLL = -2
c$$$                      CALL CMBODY(2)
                     IPHASE = -1
                  ELSE IF (KSTAR(I).GE.0) THEN
*       Distinguish between sequential, standard and GR circularization.
                      IF (KZ(27).EQ.1) THEN
                          ICIRC = 1
                          TC = 0.0
                      ELSE IF (KZ(27).EQ.2) THEN
                          ECC2 = (1.0 - RI/SEMI)**2 +
     &                                  TDOT2(IPAIR)**2/(SEMI*BODY(I))
                          ECC = SQRT(ECC2)
                          ICIRC = 0
                          CALL TCIRC(QPERI,ECC,I1,I2,ICIRC,TC)
                      ELSE
                          ICIRC = 1
                          TC = 0.0
                      END IF
                      IF (KSTAR(I).GE.10) ICIRC = 0
*       Skip tidal effects for circularization time above 100 Myr (07/08).
                      IF (ICIRC.GT.0.AND.KZ(27).GT.0.AND.
     &                    TC.LT.100.0) THEN
                          CALL KSTIDE(IPAIR,QPERI)
                      END IF
                  END IF
              END IF
*       Check for perturbed spiral or chaos case (skip collision).
              IF (KSTAR(I).EQ.-2.AND.IPHASE.EQ.0) THEN
                  CALL SPIRAL(IPAIR)
              ELSE IF (KSTAR(I).EQ.-1.AND.IPHASE.EQ.0) THEN
                  CALL KSTIDE(IPAIR,QPERI)
              END IF
*       Check options for artificial collisions.
          ELSE IF (KZ(27).EQ.-1) THEN
              RFAC = 2.0
              IF (QPERI.LT.RFAC*MAX(RADIUS(I1),RADIUS(I2))) THEN
                  J1 = I1
                  IF (RADIUS(I2).GT.RADIUS(I1)) J1 = I2
                  FAC = 0.5*BODY(I)/BODY(J1)
*       Adopt collision criterion of Kochanek (Ap.J. 385, 604, 1992).
                  RCOLL = 1.7*FAC**0.3333*RADIUS(J1)
                  IF (QPERI.LT.RCOLL) THEN
                      CALL TOUCH(IPAIR,I1,I2,RCOLL)
                  END IF
              END IF
          END IF
          GO TO 100
      END IF
*
*       Save maximum separation of persistent binary.
      RMAX = MAX(RMAX,RI)
*     ks MPI communicate rmax
*      call ksparmpi(K_store,K_real8,K_RMAX,0,0,RMAX)
*     --03/05/14 20:34-lwang-debug--------------------------------------*
***** Note:------------------------------------------------------------**
c$$$      print*,rank,'rmax',rmax
*     --03/05/14 20:34-lwang-end----------------------------------------*
*
*       Check binary reference radius or merger stability criterion.
      IF (NAME(I).GT.0) THEN
*       Update termination length scale in case of initial soft binary.
          EB = BODY(I1)*BODY(I2)*HI*BODYIN
          IF (EB.LT.EBH) R0(IPAIR) = MAX(RMIN,2.0*SEMI)
      ELSE 
          ECC2 = (1.0-RI/SEMI)**2+TDOT2(IPAIR)**2/(SEMI*BODY(I))
          ECC = SQRT(ECC2)
          RP = SEMI*(1.0 - ECC)*(1.0 - 2.0*GI)
*       Find merger index.
          IM = 0
          DO 72 K = 1,NMERGE
              IF (NAMEM(K).EQ.NAME(I)) IM = K
   72     CONTINUE
*       Exclude inner planets from the general stability test.
          IF (MIN(BODY(I1),BODY(I2)).LT.0.05*BODYM) THEN
              IF (RP.LT.R0(IPAIR)) GO TO 90
          END IF
*       Assess the stability inside critical pericentre (safety factor 1.04).
          IF (RP.LT.1.04*R0(IPAIR)) THEN
              EOUT = ECC
*       Increase tolerance near sensitive stability boundary (RM 10/2008).
              IF (EOUT.GT.0.90) THEN
                  DE = 0.5*(1.0 - EOUT)
                  DE = MIN(DE,0.01D0)
*       Add extra amount 0.011 to avoid switching.
                  IF (ECC.GT.0.9) DE = DE + 0.011
                  EOUT = EOUT - DE
              END IF
*       Note: assessment needs to use same eccentricity as for acceptance.
              CALL ASSESS(IPAIR,IM,EOUT,SEMI,ITERM)
              IF (ITERM.GT.0) THEN
                  INSTAB = INSTAB + 1
                  GO TO 90
              END IF
          END IF
*       Check possible eccentricity modulation or t_circ update.
          IF (IM.GT.0.AND.(TIME.GT.TMDIS(IM).OR.
     &        TMDIS(IM).GT.1.0D+06)) THEN
              IF (KZ(27).EQ.2) THEN
                  CALL ECCMOD(I,ITERM)
                  IF (ITERM.GT.0) THEN
*                     if(rank.eq.0)
*    &                WRITE (6,76)  RP, R0(IPAIR)
*  76                 FORMAT (' ECCMOD TERM    RP R0 ',1P,2E11.3)
                      GO TO 90
                  END IF
*       Consider both inner and possible outer circularizing binary.
                  DO 78 K = 1,NCHAOS
                      IF (NAMEC(K).EQ.NZERO - NAMEM(IM).AND.
     &                    KSTARM(IM).EQ.-2) THEN
*       Update unperturbed binary if T - TOSC > 10 Myr (cf. IMPACT & DECIDE).
                          IF ((TIME - TOSC(K))*TSTAR.GT.10.0) GO TO 90
                      END IF
                      IF (NAMEC(K).EQ.NAMEG(IM).AND.
     &                    KSTARM(IM).EQ.-2) THEN
                          IF ((TIME - TOSC(K))*TSTAR.GT.10.0) GO TO 90
                      END IF
*       Note: perturbed binary is treated if pericentre before next IMPACT.
   78             CONTINUE
              END IF
          END IF
      END IF
*
*       Produce diagnostics for any circularizing perturbed binary.
      IF (KSTAR(I).EQ.-2.AND.GI.GT.0.01) THEN
          ECC = RI/SEMI - 1.0
          QPS = SEMI*(1.0 - ECC)/MAX(RADIUS(I1),RADIUS(I2))
          ZM = BODY(I1)/BODY(I2)
          if(rank.eq.0)
     &    WRITE (21,80)  TTOT, NAME(I1), NAME(I2), KSTAR(I1), KSTAR(I2),
     &                   LIST(1,I1), QPS, ZM, GI, ECC, SEMI
   80     FORMAT (' PERT SPIRAL    T NAM K* NP QP/S M1/M2 G E A ',
     &                             F11.4,2I6,3I3,2F5.1,2F8.4,1P,E11.3)
          CALL FLUSH(21)
      END IF
*
*       See whether KS slow-down procedure should be (re)-checked (no Chaos).
      IF (KZ(26).GT.0.AND.KSTAR(I).GE.0) THEN
          KMOD = INT(RANGE*GMIN/MAX(GI,1.0D-10))
          IF (KMOD.GT.1.OR.IMOD.GT.1) THEN
              CALL KSMOD(IPAIR,KMOD)
              IF (KMOD.LT.0) GO TO 100
          END IF
      END IF
*
*       Set approximate value of next period with perturbation included.
      TK = TWOPI*SEMI*SQRT(SEMI*BODYIN)*(1.0 + GI)
      IF (IMOD.GT.1) THEN
          TK = ZMOD*TK
      END IF
*
*       Use old perturber list if next apocentre is before the c.m. step.
      IF (TIME + TK.LT.T0(I) + STEP(I)) THEN
          GO TO 100
      END IF
*
*       Select new perturbers (J = N adopted for unperturbed Chaos).
      CALL KSLIST(IPAIR)
*
*       Check rectification of chaotic spiral at start of unperturbed motion.
      IF (KSTAR(I).EQ.-2.AND.LIST(1,I1).EQ.0) THEN
          DMR = 0.D0
          CALL CHRECT(IPAIR,DMR)
          IF (IPHASE.LT.0) GO TO 100
      ELSE
* ADDED BY MAS - 08 NOV 2021 - M.A.S. Manuel Arca Sedda
         IF(ECC2 .LT. 0.0 .OR. ECC .GT. 1.0 .OR. SEMI.LT.0.0)THEN
         IF(RANK.EQ.0) WRITE(*,*)' t=',time,
     &  ' KSINT bef KSRECT IPAIR, I12, N12, M12, ECC2, ECC, SEMI H R ',
     &     IPAIR,I1,I2,NAME(I1),NAME(I2),BODY(I1)*ZMBAR,BODY(I2)*ZMBAR,
     &     ECC2,ECC,SEMI,H(IPAIR),R(IPAIR),' watch e or semi ...'
         ENDIF
         CALL KSRECT(IPAIR)
      END IF
*
*       Check optional search criterion for multiple encounter or merger.
      IF (KZ(15).GT.0.AND.STEP(I).LT.DTMIN) THEN
          CALL IMPACT(I)
      END IF
      GO TO 100
*
*       Terminate regularization of current pair (IPAIR set in KSPAIR).
   90 KSPAIR = IPAIR
*       Set indicator for calling KSTERM in MAIN (permits phase overlay).
      IPHASE = 2
*       Check case of hierarchical binary.
      IF (NAME(I).LT.0) IPHASE = 7
*
 100  RETURN
*
      END
*
      SUBROUTINE GW_DECISION(SEMI,M1,M2,CLIGHT,ECC,DT,RES,TGR,KMIN)
*
*     Decide if you want to integrate or not  
      INTEGER RES,KMIN
      REAL*8 SEMI,M1,M2,CLIGHT,ECC,DT,DE(5),TGR,DTX
      REAL*8 ECCNEW,SEMNEW,ECCN,SEMN
      REAL*8 ttgr1,ttgr2
      LOGICAL LSANE,COMP
      include 'timing.h'
*
      call cputim(ttgr1)
      CALL TIDES3(SEMI,M1,M2,ECC,CLIGHT,DT,DE)
      call cputim(ttgr2)
      if(rank.eq.0)tttides3 = tttides3 + (ttgr2-ttgr1)*60.
      if(rank.eq.0)itides3 = itides3 + 1
*
      RES=0
	  KMIN=0
      ECCN = ECC-DE(4)
      SEMN = SEMI-DE(3)
	  
* JFNS Added differentiation between hyperbolic & elliptical 
	  IF (ECC.GT.0.D0.AND.ECC.LT.1.D0.AND.SEMI.GT.0.D0) THEN
*	  
*      PRINT*,' 0 GW_DEC: M1/2 KMIN DT DE ',M1,M2,KMIN,DT,DE
*      PRINT*,' 0 ECCN, SEMN,ECC,SEMI ',ECCN, SEMN,ECC,SEMI
		DTX = DT
		  IF(ECCN.LT.0.D0.OR.ECCN.GT.1.D0.OR.SEMN.LT.0.D0)THEN
			 DE(1:5) = 0.D0
			 DO K = 1,64
			 DTX=DTX/2.D0
			 CALL TIDES3(SEMI,M1,M2,ECC,CLIGHT,DTX,DE)
			 ECCN = ECC-DE(4)
			 SEMN = SEMI-DE(3)
				IF(ECCN.GT.0.D0.AND.ECCN.LT.1.D0.AND.SEMN.GT.0.D0)THEN
				   KMIN = K
				   GOTO 50
				END IF
			 END DO
		  END IF	  
	  ELSE IF (ECC.GT.1.D0.AND.SEMI.LT.0.D0) THEN
		  IF(ECCN.LT.1.D0)THEN
			 DE(1:5) = 0.D0
			 DO K = 1,64
			 DTX=DTX/2.D0
			 CALL TIDES3(SEMI,M1,M2,ECC,CLIGHT,DTX,DE)
			 ECCN = ECC-DE(4)
			 SEMN = SEMI-DE(3)
				IF(ECCN.GT.1.D0.AND.SEMN.LT.0.D0)THEN
				   KMIN = K
				   GOTO 50
				END IF
			 END DO
		  END IF	  
	  END IF
*
 50   CONTINUE
*
      ECCNEW = ECCN
      SEMNEW = SEMN
      DTOLD = DT
      DT = DTX
      TGR = DABS(DT*SEMI/DE(3))
	  
* JFNS Added hyperbolic case
*      LSANE = ECCNEW.GT.0.D0.AND.ECCNEW.LT.1.D0.AND.
*          SEMNEW.GT.0.D0
	  LSANE = ECCNEW.GT.0.D0
*
	  IF (ECC.GT.1.0D0) THEN
	  COMP = DABS(DE(3)/SEMI).GT.1.0D-4.OR.(DE(4)/ECC).GT.1.0D-4
	  ELSE
	  LSANE = LSANE.AND.SEMNEW.GT.0.D0
	  COMP = DABS(DE(3)/SEMI).GT.1.0D-4.OR.(DE(4)/ECC).GT.1.0D-4
	  END IF
	  LSANE = LSANE.AND.COMP
*	  
*    IF(LSANE.AND.(DE(4)/ECC).GT.1.0D-4.OR.(DE(3)/SEMI).GT.1.0D-4) THEN
*        do not bypass the GW emission effect
*
	  IF(LSANE) RES=1 
	  	  
*
********************************************************	  
*      PRINT*,' GW_DEC: M1/2 KMIN DT/old DE ',M1,M2,KMIN,DT,DTOLD,DE
*      PRINT*,' ECCNEW, SEMNEW,ECC,SEMI ',ECCNEW, SEMNEW,ECC,SEMI

*
      RETURN 
   
      END
