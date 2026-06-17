[GlobalParams]
  displacements = 'disp_x disp_y'
[]

[Mesh]
  [fmg]
    type = FileMeshGenerator
    file = Friction.e
  []
  patch_update_strategy = iteration   # re-find contact faces during sliding
  displacements = 'disp_x disp_y'     # required for displaced-mesh contact
  coord_type = RZ                     # axisymmetric (belongs in Mesh, not Problem)
  rz_coord_axis = Y                   # symmetry axis = Y (z); X = radial (r)
  # NOTE (open issue): if tablet_outer / tablet_top / tablet_bottom share the
  # top-outer and bottom-outer CORNER NODES, those nodes are members of two
  # mortar secondary surfaces at once -> over-constrained -> stick-slip residual
  # blowups. This is fixed in mesh generation (drop the shared corner node from
  # one sideset of each adjacent pair), not in this file.
[]

[Physics/SolidMechanics/QuasiStatic]
  # Tablet: large compaction -> FINITE strain + DPC plasticity.
  [tablet]
    strain = FINITE
    add_variables = true        # creates disp_x/disp_y globally (only declared once)
    # Rashid/Taylor rotation (the default) throws the C1/C3_test sqrt error under large
    # strain increments. EigenSolution uses exact polar decomposition (R = F*U^-1,
    # U = sqrt(F^T F)) which has no such guard and is robust to distorted increments.
    decomposition_method = EigenSolution
    generate_output = 'stress_xx stress_yy stress_zz vonmises_stress hydrostatic_stress'
    block = 'tablet'
  []
  # Punches & wall: BC-driven, pure translation, no rotation -> SMALL strain.
  # This removes the finite-strain rotation-tensor (Rashid) calc that was failing.
  [platens]
    strain = SMALL
    add_variables = true        # also create/extend disp vars onto the platen blocks (1,3,4)
    block = 'lower_punch upper_punch die_wall'
  []
[]

[UserObjects]
  # Hardening objects MUST be declared before 'dp' references them
  [coh]
    type = SolidMechanicsHardeningConstant
    value = 1.1886
  []
  [phi]
    type = SolidMechanicsHardeningConstant
    value = 40
    convert_to_radians = true   # 40 deg; 70 deg made the DP cone near-singular
  []
  [psi]
    type = SolidMechanicsHardeningConstant
    value = 5
    convert_to_radians = true   # 5 deg dilation
  []
  [ts]
    type = SolidMechanicsHardeningConstant
    value = 0.2249             # tensile cap, MPa
  []
  [cs]
    type = SolidMechanicsHardeningConstant
    value = 36.1395            # compressive cap = p_b, MPa
  []
  [dp]
    type = SolidMechanicsPlasticDruckerPrager
    mc_cohesion = coh
    mc_friction_angle = phi
    mc_dilation_angle = psi
    mc_interpolation_scheme = outer_tip
    yield_function_tolerance = 1e-5
    internal_constraint_tolerance = 1e-6
  []
[]

[Materials]
  [elasticity_tablet]
    type = ComputeIsotropicElasticityTensor
    block = tablet
    youngs_modulus = 3497.60
    poissons_ratio = 0.1268
  []
  [capped_dp]
    type = CappedDruckerPragerStressUpdate
    block = tablet
    DP_model = dp
    tensile_strength = ts
    compressive_strength = cs
    tip_smoother = 0.05         # ~4% of cohesion (1.1886); large values cause return-map instability
    smoothing_tol = 0.05
    yield_function_tol = 1e-5
    max_NR_iterations = 1000    # return map needs more internal iterations (ref uses 1000)
  []
  [stress_tablet]
    type = ComputeMultipleInelasticStress
    block = tablet
    inelastic_models = capped_dp
    # NOTE: false avoids the Rashid sqrt path, but with strain = FINITE this skips
    # proper stress rotation -> stresses may be wrong under large compaction.
    # Since decomposition_method = EigenSolution is already used, test = true in
    # isolation; if it stays stable, switch it on for correct finite-strain stress.
    perform_finite_strain_rotations = false
  []

  [elasticity_rigid]
    type = ComputeIsotropicElasticityTensor
    block = 'lower_punch upper_punch die_wall'
    youngs_modulus = 2.1e5
    poissons_ratio = 0.3
  []
  [stress_rigid]
    type = ComputeLinearElasticStress    # small-strain stress; NO rotation tensor -> cannot hit Rashid sqrt error
    block = 'lower_punch upper_punch die_wall'
  []
[]

[Contact]
  # Side wall = Coulomb friction (mu=0.1); both punches frictionless.
  # mortar formulation: avoids penalty contact-state cycling that caused residual oscillation.
  [tablet_wall]
    primary = wall_inner
    secondary = tablet_outer
    model = coulomb              # frictional side wall (tablet_outer <-> wall_inner)
    formulation = mortar
    friction_coefficient = 0.1
    # Balanced NCP coefficients. Previously c_tangential = 1.0 vs c_normal default
    # 1e6 -> the tangential (stick/slip) complementarity was numerically swamped,
    # causing erratic active-set flips. Set EQUAL and explicit. These are TUNING
    # parameters, not physical constants: if the normal solve is over-stiff, lower
    # BOTH together (e.g. 1e4) keeping them equal. Sweep if convergence is poor.
    c_normal = 1e6
    c_tangential = 1e6
    tangential_tolerance = 0.05
    # OPEN QUESTION (your GitHub Q2): tension_release behaviour under the mortar
    # formulation during the unloading phase is unverified. Left at -1 for now.
    tension_release = -1
  []
  [upper_tablet]
    primary = up_bottom
    secondary = tablet_top
    model = frictionless
    formulation = mortar
    c_normal = 1e6               # explicit (matches default) for clarity
    tension_release = -1
  []
  [lower_tablet]
    primary = lp_top
    secondary = tablet_bottom
    model = frictionless
    formulation = mortar
    c_normal = 1e6               # explicit (matches default) for clarity
    tension_release = -1
  []
[]

[BCs]
  [tablet_axis]
    type = DirichletBC
    variable = disp_x
    boundary = tablet_axis
    value = 0
  []
  [wall_fix_x]
    type = DirichletBC
    variable = disp_x
    boundary = die_wall_all
    value = 0
  []
  [wall_fix_y]
    type = DirichletBC
    variable = disp_y
    boundary = die_wall_all
    value = 0
  []
  [lp_fix_x]
    type = DirichletBC
    variable = disp_x
    boundary = lower_punch_all
    value = 0
  []
  [lp_fix_y]
    type = DirichletBC
    variable = disp_y
    boundary = lower_punch_all
    value = 0                # lower punch fully fixed (anvil); no ejection
  []
  [up_fix_x]
    type = DirichletBC
    variable = disp_x
    boundary = upper_punch_all
    value = 0
  []
  [up_move_y]
    type = FunctionDirichletBC
    variable = disp_y
    boundary = upper_punch_all
    function = upper_punch_z
  []
[]

[Functions]
  # Upper punch: compaction (0 -> -2 mm by t=10), then unloading (-2 -> 0 by t=20). No ejection.
  [upper_punch_z]
    type = PiecewiseLinear
    x = '0   10   20'
    y = '0   -2    0'
  []
[]

[Preconditioning]
  [smp]
    type = SMP
    full = true
  []
[]

[Executioner]
  type = Transient
  solve_type = NEWTON
  automatic_scaling = true   # critical: tablet E=3497 vs platens E=2.1e5 (60x) needs variable scaling
  petsc_options_iname = '-pc_type -pc_factor_shift_type'
  petsc_options_value = 'lu      NONZERO'
  line_search = none
  nl_rel_tol = 1e-6
  nl_abs_tol = 1e-7
  nl_max_its = 50            # increased from 30; needed for contact+plasticity coupled iterations
  l_max_its = 100
  start_time = 0.0
  end_time = 20.0
  dtmin = 1e-6               # lowered from 1e-4; allows deeper bisection before abort
  [TimeStepper]
    type = IterationAdaptiveDT
    dt = 0.01                # initial dt (smaller than before for stable contact entry)
    optimal_iterations = 6   # target NR iterations per step
    iteration_window = 2
    growth_factor = 1.5
    cutback_factor = 0.5
  []
[]

[Outputs]
  exodus = true
  print_linear_residuals = false
  [console]
    type = Console
    max_rows = 5
  []
[]
