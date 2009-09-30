!> \file
!> $Id: DarcyExample.f90 20 2009-05-28 20:22:52Z cpb $
!> \author Christian Michler
!> \brief This is an example program to solve a Darcy equation using openCMISS calls.
!>
!> \section LICENSE
!>
!> Version: MPL 1.1/GPL 2.0/LGPL 2.1
!>
!> The contents of this file are subject to the Mozilla Public License
!> Version 1.1 (the "License"); you may not use this file except in
!> compliance with the License. You may obtain a copy of the License at
!> http://www.mozilla.org/MPL/
!>
!> Software distributed under the License is distributed on an "AS IS"
!> basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
!> License for the specific language governing rights and limitations
!> under the License.
!>
!> The Original Code is OpenCMISS
!>
!> The Initial Developer of the Original Code is University of Auckland,
!> Auckland, New Zealand and University of Oxford, Oxford, United
!> Kingdom. Portions created by the University of Auckland and University
!> of Oxford are Copyright (C) 2007 by the University of Auckland and
!> the University of Oxford. All Rights Reserved.
!>
!> Contributor(s):
!>
!> Alternatively, the contents of this file may be used under the terms of
!> either the GNU General Public License Version 2 or later (the "GPL"), or
!> the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
!> in which case the provisions of the GPL or the LGPL are applicable instead
!> of those above. If you wish to allow use of your version of this file only
!> under the terms of either the GPL or the LGPL, and not to allow others to
!> use your version of this file under the terms of the MPL, indicate your
!> decision by deleting the provisions above and replace them with the notice
!> and other provisions required by the GPL or the LGPL. If you do not delete
!> the provisions above, a recipient may use your version of this file under
!> the terms of any one of the MPL, the GPL or the LGPL.
!>

!> \example examples/FluidMechanics/Darcy/src/DarcyExample.f90
!! Example program to solve a Darcy equation using openCMISS calls.
!<

! ! 
! !  This example considers Darcy flow with a venous compartment modelled
! !  by a sink term.
! !  Reference: G.E. Rossi, Numerical Simulation of Perfusion in the Beating Heart,
! !  M.Sc. Thesis, Politecnico di Milano, 2007 (Chapter 6)
! ! 

!> Main program
PROGRAM DARCYEXAMPLE

  USE BASE_ROUTINES
  USE BASIS_ROUTINES
  USE BOUNDARY_CONDITIONS_ROUTINES
  USE CMISS
  USE CMISS_MPI
  USE COMP_ENVIRONMENT
  USE CONSTANTS
  USE CONTROL_LOOP_ROUTINES
  USE COORDINATE_ROUTINES
!   USE DISTRIBUTED_MATRIX_VECTOR
  USE DOMAIN_MAPPINGS
  USE EQUATIONS_ROUTINES
  USE EQUATIONS_SET_CONSTANTS
  USE EQUATIONS_SET_ROUTINES
  USE FIELD_ROUTINES
  USE FIELD_IO_ROUTINES
  USE INPUT_OUTPUT
  USE ISO_VARYING_STRING
  USE KINDS
!   USE LISTS
  USE MESH_ROUTINES
  USE MPI
  USE NODE_ROUTINES
  USE PROBLEM_CONSTANTS
  USE PROBLEM_ROUTINES
  USE REGION_ROUTINES
  USE SOLVER_ROUTINES
  USE TIMER
  USE TYPES

#ifdef WIN32
  USE IFQWIN
#endif

  USE FLUID_MECHANICS_IO_ROUTINES


!---------------
  IMPLICIT NONE
!---------------

  !Program types
  
  TYPE(BOUNDARY_CONDITIONS_TYPE), POINTER :: BOUNDARY_CONDITIONS
  TYPE(COORDINATE_SYSTEM_TYPE), POINTER :: COORDINATE_SYSTEM
  TYPE(MESH_TYPE), POINTER :: MESH
  TYPE(DECOMPOSITION_TYPE), POINTER :: DECOMPOSITION
  TYPE(EQUATIONS_TYPE), POINTER :: EQUATIONS
  TYPE(EQUATIONS_SET_TYPE), POINTER :: EQUATIONS_SET
  TYPE(FIELD_TYPE), POINTER :: GEOMETRIC_FIELD, DEPENDENT_FIELD, MATERIALS_FIELD
  TYPE(PROBLEM_TYPE), POINTER :: PROBLEM
  TYPE(REGION_TYPE), POINTER :: REGION, WORLD_REGION
  TYPE(SOLVER_TYPE), POINTER :: SOLVER
  TYPE(SOLVER_EQUATIONS_TYPE), POINTER :: SOLVER_EQUATIONS
  TYPE(BASIS_TYPE), POINTER :: BASIS_M, BASIS_V, BASIS_P
  TYPE(MESH_ELEMENTS_TYPE), POINTER :: MESH_ELEMENTS_M, MESH_ELEMENTS_V, MESH_ELEMENTS_P
  TYPE(NODES_TYPE), POINTER :: NODES
  TYPE(VARYING_STRING) :: LOCAL_ERROR    

  !Program variables

  INTEGER(INTG) :: NUMBER_OF_DOMAINS
  INTEGER(INTG) :: NUMBER_COMPUTATIONAL_NODES
  INTEGER(INTG) :: MY_COMPUTATIONAL_NODE_NUMBER
  INTEGER(INTG) :: MPI_IERROR
  INTEGER(INTG) :: EQUATIONS_SET_INDEX

  REAL(SP) :: START_USER_TIME(1),STOP_USER_TIME(1),START_SYSTEM_TIME(1),STOP_SYSTEM_TIME(1)

  LOGICAL :: EXPORT_FIELD
  TYPE(VARYING_STRING) :: FILE,METHOD

  INTEGER(INTG) :: ERR
  TYPE(VARYING_STRING) :: ERROR

  INTEGER(INTG) :: DIAG_LEVEL_LIST(5)
  CHARACTER(LEN=MAXSTRLEN) :: DIAG_ROUTINE_LIST(1),TIMING_ROUTINE_LIST(1)

  !User types
  TYPE(EXPORT_CONTAINER):: CM

  !User variables
  INTEGER:: MESH_NUMBER_OF_COMPONENTS
  INTEGER:: DECOMPOSITION_USER_NUMBER
  INTEGER:: REGION_USER_NUMBER
  INTEGER:: COORDINATE_USER_NUMBER
  INTEGER:: GEOMETRIC_FIELD_USER_NUMBER
  INTEGER:: DEPENDENT_FIELD_USER_NUMBER
  INTEGER:: MATERIALS_FIELD_USER_NUMBER
  INTEGER:: X_DIRECTION, Y_DIRECTION, Z_DIRECTION
  INTEGER:: k, l, i, j
  INTEGER:: dummy
  INTEGER:: QDR
  INTEGER:: NUMBER_DOF_CONDITIONS

  INTEGER, ALLOCATABLE, DIMENSION(:):: BC_INLET_NODES
  INTEGER, ALLOCATABLE, DIMENSION(:):: BC_WALL_NODES
  INTEGER, ALLOCATABLE, DIMENSION(:):: DOF_INDICES
  INTEGER, ALLOCATABLE, DIMENSION(:):: DOF_CONDITION
  REAL(DP), ALLOCATABLE, DIMENSION(:):: DOF_VALUES 

  DOUBLE PRECISION:: DIVERGENCE_TOLERANCE, RELATIVE_TOLERANCE, ABSOLUTE_TOLERANCE
  INTEGER:: MAXIMUM_ITERATIONS, GMRES_RESTART

  DOUBLE PRECISION:: FACT
  DOUBLE PRECISION:: COORD_X, COORD_Y, COORD_Z
  DOUBLE PRECISION:: ARG_X, ARG_Y, ARG_Z
  DOUBLE PRECISION:: DENSITY

#ifdef WIN32
  !Quickwin type
  LOGICAL :: QUICKWIN_STATUS=.FALSE.
  TYPE(WINDOWCONFIG) :: QUICKWIN_WINDOW_CONFIG
#endif

#ifdef WIN32
  !Initialise QuickWin
  QUICKWIN_WINDOW_CONFIG%TITLE="General Output" !Window title
  QUICKWIN_WINDOW_CONFIG%NUMTEXTROWS=-1 !Max possible number of rows
  QUICKWIN_WINDOW_CONFIG%MODE=QWIN$SCROLLDOWN
  !Set the window parameters
  QUICKWIN_STATUS=SETWINDOWCONFIG(QUICKWIN_WINDOW_CONFIG)
  !If attempt fails set with system estimated values
  IF(.NOT.QUICKWIN_STATUS) QUICKWIN_STATUS=SETWINDOWCONFIG(QUICKWIN_WINDOW_CONFIG)
#endif


!-----------------------------------
! Read problem-specific parameters 
!-----------------------------------

  CALL FLUID_MECHANICS_IO_READ_DARCY_PARAMS

  IF( DARCY%DEBUG ) THEN
    OPEN(UNIT=73, FILE='./output/Debug_Darcy.txt', STATUS='unknown')  ! debug output

    WRITE(73,*)'Read Darcy parameters as follows:'

    write(73,*)'TESTCASE: ',DARCY%TESTCASE

    write(73,*)'STAB: ',DARCY%STAB
    write(73,*)'ANALYTIC: ',DARCY%ANALYTIC
    write(73,*)'DEBUG: ',DARCY%DEBUG

    write(73,*)'LENGTH: ',DARCY%LENGTH
    write(73,*)'GEOM_TOL: ',DARCY%GEOM_TOL
    write(73,*)'X1: ',DARCY%X1
    write(73,*)'X2: ',DARCY%X2
    write(73,*)'Y1: ',DARCY%Y1
    write(73,*)'Y2: ',DARCY%Y2
    write(73,*)'Z1: ',DARCY%Z1
    write(73,*)'Z2: ',DARCY%Z2
    write(73,*)'PERM: ',DARCY%PERM
    write(73,*)'VIS: ',DARCY%VIS
    write(73,*)'PERM_OVER_VIS: ',DARCY%PERM_OVER_VIS
    write(73,*)'P_SINK: ',DARCY%P_SINK

    write(73,*)'BC_NUMBER_OF_WALL_NODES: ',DARCY%BC_NUMBER_OF_WALL_NODES
    write(73,*)'NUMBER_OF_BCS: ',DARCY%NUMBER_OF_BCS
    write(73,*)' '
  END IF


!---------------------------------------------------------
! Import cmHeart information - Adopted from Seb. Krittian 
!---------------------------------------------------------

  !Read node, element and basis information from cmheart input file
  !Receive CM container for adjusting OpenCMISS calls
  CALL FLUID_MECHANICS_IO_READ_CMHEART(CM,ERR,ERROR,*999)


!-----------------
! Intialise cmiss
!-----------------

  NULLIFY(WORLD_REGION)
  CALL CMISS_INITIALISE(WORLD_REGION,ERR,ERROR,*999)
  
  !Set all diganostic levels on for testing
  DIAG_LEVEL_LIST(1)=1
  DIAG_LEVEL_LIST(2)=2
  DIAG_LEVEL_LIST(3)=3
  DIAG_LEVEL_LIST(4)=4
  DIAG_LEVEL_LIST(5)=5
  DIAG_ROUTINE_LIST(1)="SOLUTION_MAPPING_CALCULATE"
  !CALL DIAGNOSTICS_SET_ON(ALL_DIAG_TYPE,DIAG_LEVEL_LIST,"DarcyExample",DIAG_ROUTINE_LIST,ERR,ERROR,*999)
  !CALL DIAGNOSTICS_SET_ON(ALL_DIAG_TYPE,DIAG_LEVEL_LIST,"",DIAG_ROUTINE_LIST,ERR,ERROR,*999)
  !CALL DIAGNOSTICS_SET_ON(IN_DIAG_TYPE,DIAG_LEVEL_LIST,"",DIAG_ROUTINE_LIST,ERR,ERROR,*999)
  !CALL DIAGNOSTICS_SET_ON(IN_DIAG_TYPE,DIAG_LEVEL_LIST,"",DIAG_ROUTINE_LIST,ERR,ERROR,*999)

  TIMING_ROUTINE_LIST(1)="PROBLEM_FINITE_ELEMENT_CALCULATE"
  !CALL TIMING_SET_ON(IN_TIMING_TYPE,.TRUE.,"",TIMING_ROUTINE_LIST,ERR,ERROR,*999)
  
  !Calculate the start times
  CALL CPU_TIMER(USER_CPU,START_USER_TIME,ERR,ERROR,*999)
  CALL CPU_TIMER(SYSTEM_CPU,START_SYSTEM_TIME,ERR,ERROR,*999)
  
  !Get the number of computational nodes
  NUMBER_COMPUTATIONAL_NODES=COMPUTATIONAL_NODES_NUMBER_GET(ERR,ERROR)
  IF(ERR/=0) GOTO 999
  !Get my computational node number
  MY_COMPUTATIONAL_NODE_NUMBER=COMPUTATIONAL_NODE_NUMBER_GET(ERR,ERROR)
  IF(ERR/=0) GOTO 999


  !--------------------------------------------------
  ! Start the creation of a new RC coordinate system
  !--------------------------------------------------

  NULLIFY(COORDINATE_SYSTEM)
  COORDINATE_USER_NUMBER = 1
  CALL COORDINATE_SYSTEM_CREATE_START(COORDINATE_USER_NUMBER,COORDINATE_SYSTEM,ERR,ERROR,*999)
    CALL COORDINATE_SYSTEM_DIMENSION_SET(COORDINATE_SYSTEM,CM%D,ERR,ERROR,*999)
  CALL COORDINATE_SYSTEM_CREATE_FINISH(COORDINATE_SYSTEM,ERR,ERROR,*999)


  !----------------------------------
  ! Start the creation of the region
  !----------------------------------

  NULLIFY(REGION)
  REGION_USER_NUMBER = 1
  CALL REGION_CREATE_START(REGION_USER_NUMBER,WORLD_REGION,REGION,ERR,ERROR,*999)
    CALL REGION_COORDINATE_SYSTEM_SET(REGION,COORDINATE_SYSTEM,ERR,ERROR,*999)
  CALL REGION_CREATE_FINISH(REGION,ERR,ERROR,*999)

  !---------------------------------------------------------------
  ! Start the creation of a basis
  ! for geometry (mesh), Darcy flow velocity and pressure
  !---------------------------------------------------------------

  QDR = 4  !order of quadrature, uniform between mesh, velocity and pressure

  ! Geometry (mesh) basis
  NULLIFY(BASIS_M)
  CALL BASIS_CREATE_START(CM%ID_M,BASIS_M,ERR,ERROR,*999)  
    CALL BASIS_TYPE_SET(BASIS_M,CM%IT_T,ERR,ERROR,*999)
    CALL BASIS_NUMBER_OF_XI_SET(BASIS_M,CM%D,ERR,ERROR,*999)
    IF(CM%D==2) THEN
      CALL BASIS_INTERPOLATION_XI_SET(BASIS_M,(/CM%IT_M,CM%IT_M/),ERR,ERROR,*999)
      CALL BASIS_QUADRATURE_NUMBER_OF_GAUSS_XI_SET(BASIS_M,(/QDR,QDR/),ERR,ERROR,*999)
    ELSE IF(CM%D==3) THEN
      CALL BASIS_INTERPOLATION_XI_SET(BASIS_M,(/CM%IT_M,CM%IT_M,CM%IT_M/),ERR,ERROR,*999)
      CALL BASIS_QUADRATURE_NUMBER_OF_GAUSS_XI_SET(BASIS_M,(/QDR,QDR,QDR/),ERR,ERROR,*999)
    ELSE
      GOTO 999
    ENDIF
  CALL BASIS_CREATE_FINISH(BASIS_M,ERR,ERROR,*999)

  ! Velocity basis
  NULLIFY(BASIS_V)
  CALL BASIS_CREATE_START(CM%ID_V,BASIS_V,ERR,ERROR,*999)  
    CALL BASIS_TYPE_SET(BASIS_V,CM%IT_T,ERR,ERROR,*999)
    CALL BASIS_NUMBER_OF_XI_SET(BASIS_V,CM%D,ERR,ERROR,*999)
    IF(CM%D==2) THEN
      CALL BASIS_INTERPOLATION_XI_SET(BASIS_V,(/CM%IT_V,CM%IT_V/),ERR,ERROR,*999)
      CALL BASIS_QUADRATURE_NUMBER_OF_GAUSS_XI_SET(BASIS_V,(/QDR,QDR/),ERR,ERROR,*999)
    ELSE IF(CM%D==3) THEN
      CALL BASIS_INTERPOLATION_XI_SET(BASIS_V,(/CM%IT_V,CM%IT_V,CM%IT_V/),ERR,ERROR,*999)
      CALL BASIS_QUADRATURE_NUMBER_OF_GAUSS_XI_SET(BASIS_V,(/QDR,QDR,QDR/),ERR,ERROR,*999)
    ELSE
      GOTO 999
    ENDIF
  CALL BASIS_CREATE_FINISH(BASIS_V,ERR,ERROR,*999)

  ! Pressure basis
  NULLIFY(BASIS_P)
  CALL BASIS_CREATE_START(CM%ID_P,BASIS_P,ERR,ERROR,*999)  
    CALL BASIS_TYPE_SET(BASIS_P,CM%IT_T,ERR,ERROR,*999)
    CALL BASIS_NUMBER_OF_XI_SET(BASIS_P,CM%D,ERR,ERROR,*999)
    IF(CM%D==2) THEN
      CALL BASIS_INTERPOLATION_XI_SET(BASIS_P,(/CM%IT_P,CM%IT_P/),ERR,ERROR,*999)
      CALL BASIS_QUADRATURE_NUMBER_OF_GAUSS_XI_SET(BASIS_P,(/QDR,QDR/),ERR,ERROR,*999)
    ELSE IF(CM%D==3) THEN
      CALL BASIS_INTERPOLATION_XI_SET(BASIS_P,(/CM%IT_P,CM%IT_P,CM%IT_P/),ERR,ERROR,*999)
      CALL BASIS_QUADRATURE_NUMBER_OF_GAUSS_XI_SET(BASIS_P,(/QDR,QDR,QDR/),ERR,ERROR,*999)
    ELSE
      GOTO 999
    ENDIF
  CALL BASIS_CREATE_FINISH(BASIS_P,ERR,ERROR,*999)


    !------------------------------------------------------------------------------------
    ! Create a mesh with components for interpolating geometry, velocity and pressure
    !------------------------------------------------------------------------------------

    MESH_NUMBER_OF_COMPONENTS = 3

    NULLIFY(NODES)
    !Define number of nodes (CM%N_T)
    CALL NODES_CREATE_START(REGION,CM%N_T,NODES,ERR,ERROR,*999)
    CALL NODES_CREATE_FINISH(NODES,ERR,ERROR,*999)

    NULLIFY(MESH)
    ! Define 2D/3D (CM%D) mesh
    CALL MESH_CREATE_START(1,REGION,CM%D,MESH,ERR,ERROR,*999)
      ! Set number of elements (CM%E_T)
      CALL MESH_NUMBER_OF_ELEMENTS_SET(MESH,CM%E_T,ERR,ERROR,*999)
      ! Set number of mesh components
      CALL MESH_NUMBER_OF_COMPONENTS_SET(MESH,MESH_NUMBER_OF_COMPONENTS,ERR,ERROR,*999)

      ! Specify geometrical mesh component (CM%ID_M)
      NULLIFY(MESH_ELEMENTS_M)
      CALL MESH_TOPOLOGY_ELEMENTS_CREATE_START(MESH,CM%ID_M,BASIS_M,MESH_ELEMENTS_M,ERR,ERROR,*999)
        ! Define mesh topology (MESH_ELEMENTS_M) using all elements' (CM%E_T) associations (CM%M(k,1:CM%EN_M))
        DO k=1,CM%E_T
          CALL MESH_TOPOLOGY_ELEMENTS_ELEMENT_NODES_SET(k,MESH_ELEMENTS_M, &
            & CM%M(k,1:CM%EN_M),ERR,ERROR,*999)
        END DO
      CALL MESH_TOPOLOGY_ELEMENTS_CREATE_FINISH(MESH_ELEMENTS_M,ERR,ERROR,*999)

      ! Specify velocity mesh component (CM%ID_V)
      NULLIFY(MESH_ELEMENTS_V)
      CALL MESH_TOPOLOGY_ELEMENTS_CREATE_START(MESH,CM%ID_V,BASIS_V,MESH_ELEMENTS_V,ERR,ERROR,*999)
        !Define mesh topology (MESH_ELEMENTS_V) using all elements' (CM%E_T) associations (CM%V(k,1:CM%EN_V))
        DO k=1,CM%E_T
          CALL MESH_TOPOLOGY_ELEMENTS_ELEMENT_NODES_SET(k,MESH_ELEMENTS_V, &
            & CM%V(k,1:CM%EN_V),ERR,ERROR,*999)
        END DO
      CALL MESH_TOPOLOGY_ELEMENTS_CREATE_FINISH(MESH_ELEMENTS_V,ERR,ERROR,*999)

      ! Specify pressure mesh component (CM%ID_P)
      NULLIFY(MESH_ELEMENTS_P)
      CALL MESH_TOPOLOGY_ELEMENTS_CREATE_START(MESH,CM%ID_P,BASIS_P,MESH_ELEMENTS_P,ERR,ERROR,*999)
        !Define mesh topology (MESH_ELEMENTS_P) using all elements' (CM%E_T) associations (CM%P(k,1:CM%EN_P))
        DO k=1,CM%E_T
          CALL MESH_TOPOLOGY_ELEMENTS_ELEMENT_NODES_SET(k,MESH_ELEMENTS_P, &
            & CM%P(k,1:CM%EN_P),ERR,ERROR,*999)
        END DO
      CALL MESH_TOPOLOGY_ELEMENTS_CREATE_FINISH(MESH_ELEMENTS_P,ERR,ERROR,*999)

    CALL MESH_CREATE_FINISH(MESH,ERR,ERROR,*999)

    !------------------------
    ! Create a decomposition
    !------------------------

    NULLIFY(DECOMPOSITION)

    DECOMPOSITION_USER_NUMBER = 1
    NUMBER_OF_DOMAINS = NUMBER_COMPUTATIONAL_NODES

    CALL DECOMPOSITION_CREATE_START(DECOMPOSITION_USER_NUMBER,MESH,DECOMPOSITION,ERR,ERROR,*999)
      !Set the decomposition to be a general decomposition with the specified number of domains
      CALL DECOMPOSITION_TYPE_SET(DECOMPOSITION,DECOMPOSITION_CALCULATED_TYPE,ERR,ERROR,*999)
      CALL DECOMPOSITION_NUMBER_OF_DOMAINS_SET(DECOMPOSITION,NUMBER_OF_DOMAINS,ERR,ERROR,*999)
    CALL DECOMPOSITION_CREATE_FINISH(DECOMPOSITION,ERR,ERROR,*999)

    !-----------------------------------------------------------
    ! Create a geometric field on the region
    !-----------------------------------------------------------

    NULLIFY(GEOMETRIC_FIELD)

    GEOMETRIC_FIELD_USER_NUMBER = 1
    X_DIRECTION = 1
    Y_DIRECTION = 2
    Z_DIRECTION = 3

    CALL FIELD_CREATE_START(GEOMETRIC_FIELD_USER_NUMBER,REGION,GEOMETRIC_FIELD,ERR,ERROR,*999)
      CALL FIELD_TYPE_SET(GEOMETRIC_FIELD,FIELD_GEOMETRIC_TYPE,ERR,ERROR,*999)
      CALL FIELD_MESH_DECOMPOSITION_SET(GEOMETRIC_FIELD,DECOMPOSITION,ERR,ERROR,*999)
      CALL FIELD_SCALING_TYPE_SET(GEOMETRIC_FIELD,FIELD_NO_SCALING,ERR,ERROR,*999)
      CALL FIELD_COMPONENT_MESH_COMPONENT_SET(GEOMETRIC_FIELD,FIELD_U_VARIABLE_TYPE,X_DIRECTION,CM%ID_M,ERR,ERROR,*999)
      CALL FIELD_COMPONENT_MESH_COMPONENT_SET(GEOMETRIC_FIELD,FIELD_U_VARIABLE_TYPE,Y_DIRECTION,CM%ID_M,ERR,ERROR,*999)
      IF(CM%D==3) THEN
	CALL FIELD_COMPONENT_MESH_COMPONENT_SET(GEOMETRIC_FIELD,FIELD_U_VARIABLE_TYPE,Z_DIRECTION,CM%ID_M,ERR,ERROR,*999)
      ENDIF
    CALL FIELD_CREATE_FINISH(GEOMETRIC_FIELD,ERR,ERROR,*999)
       
    ! Set geometric field parameters CM%N(k,l) and update
    DO k = 1, CM%N_M
      DO l = 1, CM%D
	CALL FIELD_PARAMETER_SET_UPDATE_NODE(GEOMETRIC_FIELD, FIELD_U_VARIABLE_TYPE, FIELD_VALUES_SET_TYPE, &
	  & CM%ID_M, k, l, CM%N(k,l), ERR, ERROR, *999)
	  ! Why 'CM%ID_M' in place for DERIVATIVE_NUMBER ?
      END DO
    END DO
    CALL FIELD_PARAMETER_SET_UPDATE_START(GEOMETRIC_FIELD, FIELD_U_VARIABLE_TYPE, FIELD_VALUES_SET_TYPE, ERR, ERROR, *999)
    CALL FIELD_PARAMETER_SET_UPDATE_FINISH(GEOMETRIC_FIELD, FIELD_U_VARIABLE_TYPE, FIELD_VALUES_SET_TYPE, ERR, ERROR, *999)


  !==========================
  ! Create the equations_set
  !==========================

  NULLIFY(EQUATIONS_SET)

  CALL EQUATIONS_SET_CREATE_START(1,REGION,GEOMETRIC_FIELD,EQUATIONS_SET,ERR,ERROR,*999)
    CALL EQUATIONS_SET_SPECIFICATION_SET(EQUATIONS_SET,EQUATIONS_SET_FLUID_MECHANICS_CLASS,EQUATIONS_SET_DARCY_EQUATION_TYPE, &
      & EQUATIONS_SET_STANDARD_DARCY_SUBTYPE,ERR,ERROR,*999)
  CALL EQUATIONS_SET_CREATE_FINISH(EQUATIONS_SET,ERR,ERROR,*999)

  !----------------------------------------------------
  ! Create the equations_set dependent_field_variables
  !----------------------------------------------------

  NULLIFY(DEPENDENT_FIELD)

  DEPENDENT_FIELD_USER_NUMBER = 2

  CALL EQUATIONS_SET_DEPENDENT_CREATE_START(EQUATIONS_SET,DEPENDENT_FIELD_USER_NUMBER,DEPENDENT_FIELD, &
    & ERR,ERROR,*999)
  CALL EQUATIONS_SET_DEPENDENT_CREATE_FINISH(EQUATIONS_SET,ERR,ERROR,*999)


  !--------------------------------------------------------
  ! Initialise the equations_set dependent_field_variables
  !--------------------------------------------------------

  CALL FIELD_COMPONENT_VALUES_INITIALISE(DEPENDENT_FIELD,FIELD_U_VARIABLE_TYPE,&
    & FIELD_VALUES_SET_TYPE,1,0.0_DP,ERR,ERROR,*999)
  CALL FIELD_COMPONENT_VALUES_INITIALISE(DEPENDENT_FIELD,FIELD_U_VARIABLE_TYPE,&
    & FIELD_VALUES_SET_TYPE,2,0.0_DP,ERR,ERROR,*999)
      IF(CM%D==3) THEN
  CALL FIELD_COMPONENT_VALUES_INITIALISE(DEPENDENT_FIELD,FIELD_U_VARIABLE_TYPE,&
    & FIELD_VALUES_SET_TYPE,3,0.0_DP,ERR,ERROR,*999)
      END IF

  !----------------------------------------------------
  ! Create the equations_set materials_field_variables
  !----------------------------------------------------

  NULLIFY(MATERIALS_FIELD)

  MATERIALS_FIELD_USER_NUMBER = 3

  CALL EQUATIONS_SET_MATERIALS_CREATE_START(EQUATIONS_SET,MATERIALS_FIELD_USER_NUMBER,MATERIALS_FIELD, &
    & ERR, ERROR, *999)
  CALL EQUATIONS_SET_MATERIALS_CREATE_FINISH(EQUATIONS_SET,ERR,ERROR,*999)

  CALL FIELD_COMPONENT_VALUES_INITIALISE(MATERIALS_FIELD,FIELD_U_VARIABLE_TYPE,&
    & FIELD_VALUES_SET_TYPE,1,DARCY%PERM_OVER_VIS,ERR,ERROR,*999)

  DENSITY = 0.0_DP  ! not used, but for conformity with fluid_mechanics_IO_routines

  CALL FIELD_COMPONENT_VALUES_INITIALISE(MATERIALS_FIELD,FIELD_U_VARIABLE_TYPE,&
    & FIELD_VALUES_SET_TYPE,2,DENSITY,ERR,ERROR,*999)



  !------------------------------------
  ! Create the equations_set equations
  !------------------------------------

  NULLIFY(EQUATIONS)

  CALL EQUATIONS_SET_EQUATIONS_CREATE_START(EQUATIONS_SET,EQUATIONS,ERR,ERROR,*999)
    !Set the equations matrices sparsity type
    CALL EQUATIONS_SPARSITY_TYPE_SET(EQUATIONS,EQUATIONS_SPARSE_MATRICES,ERR,ERROR,*999)
!     CALL EQUATIONS_OUTPUT_TYPE_SET(EQUATIONS,EQUATIONS_ELEMENT_MATRIX_OUTPUT,ERR,ERROR,*999)
    !CALL EQUATIONS_OUTPUT_TYPE_SET(EQUATIONS,EQUATIONS_TIMING_OUTPUT,ERR,ERROR,*999)
    !CALL EQUATIONS_OUTPUT_TYPE_SET(EQUATIONS,EQUATIONS_MATRIX_OUTPUT,ERR,ERROR,*999)
  CALL EQUATIONS_SET_EQUATIONS_CREATE_FINISH(EQUATIONS_SET,ERR,ERROR,*999) 


  !--------------------------------
  ! Define the boundary_conditions
  !--------------------------------

  ALLOCATE(BC_WALL_NODES(DARCY%BC_NUMBER_OF_WALL_NODES))

  IF( DARCY%DEBUG ) THEN
    write(73,*)'Determining wall nodes: '
  END IF

  IF( CM%D==2 ) THEN
    i = 0
    DO j=1,CM%N_M
      COORD_X = CM%N( j, 1 )
      COORD_Y = CM%N( j, 2 )

      IF( (ABS(COORD_X-DARCY%X1) < DARCY%GEOM_TOL) .OR. &
        & (ABS(COORD_X-DARCY%X2) < DARCY%GEOM_TOL) .OR. &
        & (ABS(COORD_Y-DARCY%Y1) < DARCY%GEOM_TOL) .OR. &
        & (ABS(COORD_Y-DARCY%Y2) < DARCY%GEOM_TOL) ) THEN

          i = i + 1
          BC_WALL_NODES(i) = j

          IF( DARCY%DEBUG ) THEN
            write(73,*)'i, WALL_NODE, COORD_X, COORD_Y = ',i, j, COORD_X, COORD_Y
          END IF

      END IF
    END DO
  ELSE IF( CM%D==3 ) THEN
    i = 0
    DO j=1,CM%N_M
      COORD_X = CM%N( j, 1 )
      COORD_Y = CM%N( j, 2 )
      COORD_Z = CM%N( j, 3 )

      IF( (ABS(COORD_X-DARCY%X1) < DARCY%GEOM_TOL) .OR. &
        & (ABS(COORD_X-DARCY%X2) < DARCY%GEOM_TOL) .OR. &
        & (ABS(COORD_Y-DARCY%Y1) < DARCY%GEOM_TOL) .OR. &
        & (ABS(COORD_Y-DARCY%Y2) < DARCY%GEOM_TOL) .OR. &
        & (ABS(COORD_Z-DARCY%Z1) < DARCY%GEOM_TOL) .OR. &
        & (ABS(COORD_Z-DARCY%Z2) < DARCY%GEOM_TOL) ) THEN

          i = i + 1
          BC_WALL_NODES(i) = j

          IF( DARCY%DEBUG ) THEN
            write(73,*)'i, WALL_NODE, COORD_X, COORD_Y, COORD_Z = ',i, j, COORD_X, COORD_Y, COORD_Z
          END IF

      END IF
    END DO
  END IF

!   NUMBER_DOF_CONDITIONS = DARCY%NUMBER_OF_BCS
!   !BCs on normal velocity only
  NUMBER_DOF_CONDITIONS = DARCY%NUMBER_OF_BCS + DARCY%BC_NUMBER_OF_WALL_NODES
  !BCs on normal velocity + BCs on pressure

  ALLOCATE(DOF_INDICES( NUMBER_DOF_CONDITIONS ))
  ALLOCATE(DOF_CONDITION( NUMBER_DOF_CONDITIONS ))
  ALLOCATE(DOF_VALUES( NUMBER_DOF_CONDITIONS ))

  DOF_CONDITION = BOUNDARY_CONDITION_FIXED

  IF( CM%D==2 ) THEN
    dummy = 0
    DO j=1,DARCY%BC_NUMBER_OF_WALL_NODES
      COORD_X = CM%N( BC_WALL_NODES(j) ,1)
      COORD_Y = CM%N( BC_WALL_NODES(j) ,2)
      !
      ARG_X = 2.0_DP * PI * COORD_X / DARCY%LENGTH
      ARG_Y = 2.0_DP * PI * COORD_Y / DARCY%LENGTH 

      FACT = - DARCY%PERM_OVER_VIS * 2.0_DP * PI / DARCY%LENGTH

      IF( (ABS(COORD_X-DARCY%X1) < DARCY%GEOM_TOL) .OR. (ABS(COORD_X-DARCY%X2) < DARCY%GEOM_TOL) ) THEN
        !x-velocity
        dummy = dummy + 1
        i = 1
        DOF_INDICES( dummy ) = BC_WALL_NODES(j) + (i-1) * CM%N_V
        DOF_VALUES( dummy ) = FACT  * ( 9.0_DP * COS( ARG_X ) )
      END IF
      !
      IF( (ABS(COORD_Y-DARCY%Y1) < DARCY%GEOM_TOL) .OR. (ABS(COORD_Y-DARCY%Y2) < DARCY%GEOM_TOL) ) THEN
        !y-velocity
        dummy = dummy + 1
        i = 2
        DOF_INDICES( dummy ) = BC_WALL_NODES(j) + (i-1) * CM%N_V
        DOF_VALUES( dummy ) = FACT  * ( 1.0_DP * SIN( ARG_Y ) )
      END IF
      !
      IF( (ABS(COORD_X-DARCY%X1) < DARCY%GEOM_TOL) .OR. (ABS(COORD_X-DARCY%X2) < DARCY%GEOM_TOL) .OR. &
        & (ABS(COORD_Y-DARCY%Y1) < DARCY%GEOM_TOL) .OR. (ABS(COORD_Y-DARCY%Y2) < DARCY%GEOM_TOL) ) THEN
        !pressure
        dummy = dummy + 1
        i = 3
        DOF_INDICES( dummy ) = BC_WALL_NODES(j) + (i-1) * CM%N_V
        DOF_VALUES( dummy ) = 9.0_DP * SIN( ARG_X ) - 1.0_DP * COS( ARG_Y ) + DARCY%P_SINK
      END IF
    END DO
  ELSE IF( CM%D==3 ) THEN
    dummy = 0
    DO j=1,DARCY%BC_NUMBER_OF_WALL_NODES
      COORD_X = CM%N( BC_WALL_NODES(j) ,1)
      COORD_Y = CM%N( BC_WALL_NODES(j) ,2)
      COORD_Z = CM%N( BC_WALL_NODES(j) ,3)
      !
      ARG_X = 2.0_DP * PI * COORD_X / DARCY%LENGTH
      ARG_Y = 2.0_DP * PI * COORD_Y / DARCY%LENGTH 
      ARG_Z = 2.0_DP * PI * COORD_Z / DARCY%LENGTH

      FACT = - DARCY%PERM_OVER_VIS * 2.0_DP * PI / DARCY%LENGTH

      IF( (ABS(COORD_X-DARCY%X1) < DARCY%GEOM_TOL) .OR. (ABS(COORD_X-DARCY%X2) < DARCY%GEOM_TOL) ) THEN
        !x-velocity
        dummy = dummy + 1
        i = 1
        DOF_INDICES( dummy ) = BC_WALL_NODES(j) + (i-1) * CM%N_V
        DOF_VALUES( dummy ) = FACT  * ( 9.0_DP * COS( ARG_X ) )
      END IF
      !
      IF( (ABS(COORD_Y-DARCY%Y1) < DARCY%GEOM_TOL) .OR. (ABS(COORD_Y-DARCY%Y2) < DARCY%GEOM_TOL) ) THEN
        !y-velocity
        dummy = dummy + 1
        i = 2
        DOF_INDICES( dummy ) = BC_WALL_NODES(j) + (i-1) * CM%N_V
        DOF_VALUES( dummy ) = FACT  * ( 1.0_DP * SIN( ARG_Y ) )
      END IF
      !
      IF( (ABS(COORD_Z-DARCY%Z1) < DARCY%GEOM_TOL) .OR. (ABS(COORD_Z-DARCY%Z2) < DARCY%GEOM_TOL) ) THEN
        !z-velocity
        dummy = dummy + 1
        i = 3
        DOF_INDICES( dummy ) = BC_WALL_NODES(j) + (i-1) * CM%N_V
        DOF_VALUES( dummy ) = FACT  * (-3.0_DP * SIN( ARG_Z ) )
      END IF
      !
      IF( (ABS(COORD_X-DARCY%X1) < DARCY%GEOM_TOL) .OR. (ABS(COORD_X-DARCY%X2) < DARCY%GEOM_TOL) .OR. &
        & (ABS(COORD_Y-DARCY%Y1) < DARCY%GEOM_TOL) .OR. (ABS(COORD_Y-DARCY%Y2) < DARCY%GEOM_TOL) .OR. &
        & (ABS(COORD_Z-DARCY%Z1) < DARCY%GEOM_TOL) .OR. (ABS(COORD_Z-DARCY%Z2) < DARCY%GEOM_TOL) ) THEN
        !pressure
        dummy = dummy + 1
        i = 4
        DOF_INDICES( dummy ) = BC_WALL_NODES(j) + (i-1) * CM%N_V
        DOF_VALUES( dummy ) = 9.0_DP * SIN( ARG_X ) - 1.0_DP * COS( ARG_Y ) &
          &                 + 3.0_DP * COS( ARG_Z ) + DARCY%P_SINK
      END IF
    END DO
  END IF


  !----------------------------------------------
  ! Create the equations_set boundary_conditions
  !----------------------------------------------

  NULLIFY(BOUNDARY_CONDITIONS)

  CALL EQUATIONS_SET_BOUNDARY_CONDITIONS_CREATE_START(EQUATIONS_SET,BOUNDARY_CONDITIONS,ERR,ERROR,*999)
    CALL BOUNDARY_CONDITIONS_SET_LOCAL_DOF(BOUNDARY_CONDITIONS,FIELD_U_VARIABLE_TYPE,DOF_INDICES, &
      & DOF_CONDITION,DOF_VALUES,ERR,ERROR,*999)
  CALL EQUATIONS_SET_BOUNDARY_CONDITIONS_CREATE_FINISH(EQUATIONS_SET,ERR,ERROR,*999)


  !====================
  ! Create the problem
  !====================

  NULLIFY(PROBLEM)

  CALL PROBLEM_CREATE_START(1,PROBLEM,ERR,ERROR,*999)
    CALL PROBLEM_SPECIFICATION_SET(PROBLEM,PROBLEM_FLUID_MECHANICS_CLASS,PROBLEM_DARCY_EQUATION_TYPE, &
      & PROBLEM_STANDARD_DARCY_SUBTYPE,ERR,ERROR,*999)
  CALL PROBLEM_CREATE_FINISH(PROBLEM,ERR,ERROR,*999)


  !---------------------------------
  ! Create the problem control loop
  !---------------------------------

  CALL PROBLEM_CONTROL_LOOP_CREATE_START(PROBLEM,ERR,ERROR,*999)
  CALL PROBLEM_CONTROL_LOOP_CREATE_FINISH(PROBLEM,ERR,ERROR,*999)


  !-------------------------------------------
  ! Start the creation of the problem solvers
  !-------------------------------------------

  NULLIFY(SOLVER)

  RELATIVE_TOLERANCE   = 1.0E-14_DP !default 1.0E-05
  ABSOLUTE_TOLERANCE   = 1.0E-14_DP !default 1.0E-10
  DIVERGENCE_TOLERANCE = 1.0E+05_DP !default 1.0E+05
  MAXIMUM_ITERATIONS   = 1.0E+04    !default 1.0E+05
  GMRES_RESTART        = 300        !default 30

  CALL PROBLEM_SOLVERS_CREATE_START(PROBLEM,ERR,ERROR,*999)
    CALL PROBLEM_SOLVER_GET(PROBLEM,CONTROL_LOOP_NODE,1,SOLVER,ERR,ERROR,*999)
    CALL SOLVER_OUTPUT_TYPE_SET(SOLVER,SOLVER_MATRIX_OUTPUT,ERR,ERROR,*999)
    CALL SOLVER_LINEAR_ITERATIVE_RELATIVE_TOLERANCE_SET(SOLVER,RELATIVE_TOLERANCE,ERR,ERROR,*999)
    CALL SOLVER_LINEAR_ITERATIVE_ABSOLUTE_TOLERANCE_SET(SOLVER,ABSOLUTE_TOLERANCE,ERR,ERROR,*999)
    CALL SOLVER_LINEAR_ITERATIVE_DIVERGENCE_TOLERANCE_SET(SOLVER,DIVERGENCE_TOLERANCE,ERR,ERROR,*999)
    CALL SOLVER_LINEAR_ITERATIVE_MAXIMUM_ITERATIONS_SET(SOLVER,MAXIMUM_ITERATIONS,ERR,ERROR,*999)
    CALL SOLVER_LINEAR_ITERATIVE_GMRES_RESTART_SET(SOLVER,GMRES_RESTART,ERR,ERROR,*999)
  CALL PROBLEM_SOLVERS_CREATE_FINISH(PROBLEM,ERR,ERROR,*999)


  !-------------------------------------
  ! Create the problem solver equations
  !-------------------------------------

  NULLIFY(SOLVER)
  NULLIFY(SOLVER_EQUATIONS)
  CALL PROBLEM_SOLVER_EQUATIONS_CREATE_START(PROBLEM,ERR,ERROR,*999)
    CALL PROBLEM_SOLVER_GET(PROBLEM,CONTROL_LOOP_NODE,1,SOLVER,ERR,ERROR,*999)
    CALL SOLVER_SOLVER_EQUATIONS_GET(SOLVER,SOLVER_EQUATIONS,ERR,ERROR,*999)
    CALL SOLVER_EQUATIONS_SPARSITY_TYPE_SET(SOLVER_EQUATIONS,SOLVER_SPARSE_MATRICES,ERR,ERROR,*999)
    CALL SOLVER_EQUATIONS_EQUATIONS_SET_ADD(SOLVER_EQUATIONS,EQUATIONS_SET,EQUATIONS_SET_INDEX,ERR,ERROR,*999)
  CALL PROBLEM_SOLVER_EQUATIONS_CREATE_FINISH(PROBLEM,ERR,ERROR,*999)


  IF( DARCY%DEBUG ) CLOSE(73)  !close file for debug output


  !===================
  ! Solve the problem
  !===================

  CALL PROBLEM_SOLVE(PROBLEM,ERR,ERROR,*999)
  WRITE(*,*)'Problem solved.'


  !=========
  ! Output
  !=========

!    FILE="DarcyExample"
   FILE="cmgui"
   METHOD="FORTRAN"

   EXPORT_FIELD=.TRUE.
   IF(EXPORT_FIELD) THEN
     WRITE(*,*)'Now export fields...'
    CALL FLUID_MECHANICS_IO_WRITE_CMGUI(REGION,FILE,ERR,ERROR,*999)
     WRITE(*,*)'All fields exported...'
!     CALL FIELD_IO_NODES_EXPORT(REGION%FIELDS, FILE, METHOD, ERR,ERROR,*999)  
!     CALL FIELD_IO_ELEMENTS_EXPORT(REGION%FIELDS, FILE, METHOD, ERR,ERROR,*999)
   ENDIF
  
  !Output timing summary
  !CALL TIMING_SUMMARY_OUTPUT(ERR,ERROR,*999)

  !Calculate the stop times and write out the elapsed user and system times
  CALL CPU_TIMER(USER_CPU,STOP_USER_TIME,ERR,ERROR,*999)
  CALL CPU_TIMER(SYSTEM_CPU,STOP_SYSTEM_TIME,ERR,ERROR,*999)

  CALL WRITE_STRING_TWO_VALUE(GENERAL_OUTPUT_TYPE,"User time = ",STOP_USER_TIME(1)-START_USER_TIME(1),", System time = ", &
    & STOP_SYSTEM_TIME(1)-START_SYSTEM_TIME(1),ERR,ERROR,*999)
  
!   CALL CMISS_FINALISE(ERR,ERROR,*999)

  WRITE(*,'(A)') "Program successfully completed."

  STOP
999 CALL CMISS_WRITE_ERROR(ERR,ERROR)
  STOP
  
END PROGRAM DARCYEXAMPLE
