# Mortar Frictional Contact Instability in a 2D Axisymmetric Die Compaction Model

## Summary

I'm hitting a **mortar frictional contact instability** in a 2D axisymmetric (RZ) die compaction model. The nonlinear solve runs cleanly for several steps and then begins to diverge repeatedly, which I believe is driven by the contact behavior rather than the bulk material response. I'd appreciate help diagnosing what's causing the divergence and how to fix it.

## Setup

A deformable block sits between three rigid blocks, coupled through three mortar contact pairs:

| Contact Pair | Type | Friction |
|--------------|------|----------|
| `tablet_outer` ↔ `wall_inner` | Coulomb | friction_coefficient = 0.1 |
| `tablet_top` ↔ `up_bottom` | Frictionless | — |
| `tablet_bottom` ↔ `lp_top` | Frictionless | — |

The upper punch drives `disp_y`:

- **Loading:** 0 → −2 over t = 0–10
- **Unloading:** −2 → 0 over t = 10–20

The deformable block uses a `CappedDruckerPrager` material (background context — the divergence does not appear to originate here).

## Problem

The solve does **not** fail on the first step. It runs cleanly for several steps, then the nonlinear solve begins failing repeatedly. `IterationAdaptiveDT` cuts the timestep back each time, but once the timestep is already at `dtmin` the run aborts with the following error:

```
*** ERROR ***
/mnt/d/Sandip_G/Moose/DPC Trial/Moose try/Friction/Friction.i:266.3:
The following occurred in the TimeStepper 'IterationAdaptiveDT' of type IterationAdaptiveDT.

Solve failed and timestep already at dtmin, cannot continue!
```

The stack trace points into the contact module:

```
5: IterationAdaptiveDT::computeFailedDT()
6: TimeStepper::computeStep()
7: TransientBase::execute()
8: MooseApp::executeExecutioner()
9: MooseApp::run()
10: .../moose/modules/contact/contact-opt
```

The failures appear tied to the contact iterations rather than the bulk material response.

## Relevant Contact Settings

- `formulation = mortar` on all three pairs
- `c_normal` not set (defaults to 1e6); `c_tangential = 1.0` on the wall (Coulomb) pair
- `tangential_tolerance = 0.05` on the wall pair
- `tension_release = -1`

## Executioner

- `solve_type = NEWTON`, full SMP, `-pc_type lu`, `line_search = none`
- `automatic_scaling = true` (stiffness contrast: deformable block E ~3500 vs platens E 2.1e5)
- `IterationAdaptiveDT`, `dtmin = 1e-6`, `nl_rel_tol = 1e-6`

## Question

Has anyone run into similar mortar contact divergence in axisymmetric compaction, and what helped stabilize it?
