# RAGU V2 Formula Changes

## Overview

RAGU V2 (`Ragu_v_two.ipynb`) updates four scoring components and introduces consistent KMX unit normalization. The goal is to decouple components, eliminate nonlinearities that cause Jensen gap issues, and replace approximations with measured values.

## Formula Summary

### Unit Loss (UL)

**Old:** Hardcoded constant `0.5`.

**New:** Derived from model score and loan term.

```
UL = 0.9 - (model_score - 125) * 0.027 - (72 - term) / 240
```

- `model_score`: amt-financed-weighted average of `cd_model_score` per vintage-LOB
- `term`: amt-financed-weighted average of `con_term` (loan term in months) per vintage-LOB

### Gross Loss Impact

**Old:**

```
gross_loss_impact = (1 - loss_multiplier) * 0.5 / 0.02
```

**New:**

```
gross_loss_impact = (1 - loss_multiplier) * UL / 0.027
```

- Uses actual UL instead of 0.5 constant
- Conversion factor updated from 0.02 to 0.027

### Recovery Impact

**Old (V1):**

```
recovery_impact = ULS * 0.5 * R * (R/B - 1)
```

Where `ULS = model_score + gross_loss_impact` (coupled to gross loss), `B` = per-LOB baseline.

**V2 intermediate (baseline-dependent, superseded):**

```
recovery_impact = UL * F * (R - B) * 100
```

**Current (baseline-free):**

```
recovery_impact = UL * F * R / 0.027
```

- Per-LOB recovery baselines removed; neutral point is R = 0 (no recovery)
- Uses `/ 0.027` conversion factor matching gross loss for economic consistency: $1 lost = $1 recovered in RAGU points
- `F` = find rate (0.75), scales by repo success rate
- `UL` weights recovery by default probability, decoupled from gross loss
- Linear in R, no Jensen gap
- Structural symmetry with GL: both follow `[adjustment_factor] * UL / 0.027`
  - GL: `(1 - loss_multiplier)`, neutral at `loss_mult = 1`
  - Recovery: `F * R`, neutral at `R = 0`

### LTV Impact

**Old (nonlinear):**

```
ltv_impact = (baseline_ltv / actual_ltv - 1) * 17
```

**New (linear):**

```
ltv_impact = (baseline_ltv - actual_ltv) * 17
```

- Linear deviation eliminates Jensen gap for LTV
- Each 1% (0.01) LTV move produces exactly 0.17 score points

### APR Impact

Unchanged.

```
apr_impact = (baseline_apr - actual_apr) / 0.01 * 0.7
```

### RAGU Score

**Old (expanded multiplicative):**

```
ragu_score = (1 - 0.5 * R) * ULS + 0.5 * R * ULS * (R/B) + ltv_impact + apr_impact
```

**New (pure additive):**

```
ragu_score = model_score + gross_loss_impact + recovery_impact + ltv_impact + apr_impact
```

### KMX Rescaling

**Old:** `/ 0.65` applied only to `ltv_mult` and `apr_mult`, leaving gross loss and recovery in mixed units.

**New:** `* 0.65` applied to all components uniformly. Model score receives an additional `+ 50` offset to keep KMX scores in the familiar ~140 range.

```
ms_original_kmx     = model_score * 0.65 + 50
gross_loss_kmx      = gross_loss_impact * 0.65
recovery_kmx        = recovery_impact * 0.65
ltv_kmx             = ltv_impact * 0.65
apr_kmx             = apr_impact * 0.65
ragu_score_kmx      = ms_original_kmx + gross_loss_kmx + recovery_kmx + ltv_kmx + apr_kmx
```

## Data Changes

- Added `cd.con_term` to ULA query (`vintage_level_ula_query_v2.txt`)
- New cache key: `cache/ula_v2.pkl`

## Output Files

- `barebones_ragu_v2.xlsx`
- `all_df_v2.csv`
- `sandbox.ragu_v2_monthend_current` (Redshift)
- `sandbox.ragu_v2_monthend` (Redshift historical)

## Design Decisions

1. **Per-LOB baselines retained for LTV and APR** only; recovery baselines removed for consistency with gross loss (which has no baseline)
2. **Top-down aggregation retained** (aggregate then score) to isolate formula impact before switching to individual-level scoring with Jensen correction
3. **Conversion factor** updated from 0.02 to 0.027 based on updated calibration
4. **Find rate** set to 0.75 as a constant (not per-account)
