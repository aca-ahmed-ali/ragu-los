# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- **ste_date_cutoff_diagnostic.ipynb**: New diagnostic notebook to identify why STE RAGU postintegration data stops at the week of August 9, 2026
  - Cell 1: Redshift connection setup and helper functions
  - Cell 2: Source table freshness check (weekly row counts >= 2026-07-01) for `los_deal_current_fact`, `sfs_booked_contracts_scd`, `sfs_deal_detail_scd`, `rds_rec_model_originations`, and `date_dim`
  - Cell 3: Full ULA query weekly row counts to detect where counts drop to zero
  - Cell 4: Recovery query weekly row counts (primary suspect: `sandbox.rds_rec_model_originations` batch refresh lag)
  - Cell 5: STE weekly query row counts (`ste_ragu_weekly.txt` pipeline)
  - Cell 6: Join-level isolation progressively building the ULA query from base table through each join to pinpoint the bottleneck
  - Cell 7: Cached pickle file analysis (max dates, weekly counts, last-modified timestamps)
  - Cell 8: Summary report with pass/fail status for each component relative to August 9 cutoff
  - Cell 9: Python-side scoring gate analysis - reproduces postintegration pipeline on cached data and checks each `return None` exit point in `get_ragu_score()` per vintage (bbvalue population, recovery multiplier match rates)
  - Cell 10: Deep-dive NULL column analysis for the last 6 weeks - shows pre-cap vs post-cap row counts, `total_income` NULL rates (NaN dropped by `<= 200000` filter), `bbvalue` population, and recovery match rates per vintage

- **depreciation_extreme_buckets.ipynb**: New notebook for extreme depreciation bucket analysis
  - Introspects `sandbox.rds_rec_model_originations` schema to discover all available vehicle columns
  - Dynamically selects vehicle-related columns (make, model year, fuel type, body type, etc.)
  - Buckets contracts into Low (<20%) and High (>25%) depreciation based on `pred_depr_rate_std_current`
  - Per-attribute frequency tables and descriptive statistics for each extreme bucket
  - Side-by-side comparison pivot showing attribute distributions across both buckets
  - LOB breakdown within each extreme depreciation bucket

- **pool_ragu.ipynb**: New pool-level RAGU scoring notebook
  - Computes aggregate RAGU scores for specific pools of accounts defined in `ragu_pool.csv`
  - Three pools loaded from CSV columns (each column is a separate pool of account numbers)
  - No date/vintage filtering: all loans scored regardless of booking date, combined into a single aggregate per pool
  - Per-LOB baselines applied naturally: loans in different LOBs receive their respective LOB baselines (AN, FRN, STG, FLD, ENT, KMX)
  - Rolled-up combined pool score via amt-financed-weighted average across LOBs
  - Same V1 RAGU formula as `bareboned_ragu_new.ipynb`: unit_loss_score, gross_loss_impact, recovery_impact, ltv_impact, apr_impact
  - SQL account filter injected via `{min_book_date}` substitution for efficient per-pool data retrieval
  - Pool-specific pickle cache (`cache/pool_ula.pkl`, `cache/pool_recovery.pkl`) to avoid collision with main RAGU caches
  - Excel export (`pool_ragu.xlsx`) with per-LOB detail and Combined rollup row for each pool
  - Inline display of results with full metric breakdown per pool

- **ste_ragu_v3_production.ipynb**: New STE-specific V3 production notebook
  - Hybrid approach: V3 GL/Recovery computed per account (individual-first), then aggregated; MS/LTV/APR from SFS dual-path override (`ste_ragu_weekly.txt`)
  - V3 formula: `UL = 0.9 - (MS-125)*0.027` (con_term defaults to 72; not available in STE ULA query), `GL = (1-LM)*UL/0.027`, `Recovery = UL*F*R*100`
  - Purely additive RAGU: `MS + GL + Recovery + LTV + APR` (higher score = lower expected loss)
  - Monthly aggregation only, starting October 2025 (`START_DATE = '2025-10-01'`)
  - Single LOB (STE), no rollup groups; control room incorporates into POS/nonKMX at merge time
  - STE-specific flags: PTI threshold at 0.2, ent_flag=False, mcy_low_mileage_flag=False, student_loan_flag=0
  - No DLA (pricing_scalar=1.0), no KMX rescaling
  - STE caps: bbltv <= 10, pti <= 0.6, total_income <= 200k
  - Uses `ste_ragu_temptables.txt`, `ste_ragu_ula.txt`, `ste_ragu_recovery.txt`, `ste_ragu_weekly.txt`
  - Shared cache: `cache/ste_ula_v1.pkl`, `cache/ste_recovery_v1.pkl`, `cache/ste_weekly_v1.pkl`
  - Excel export (`ste_ragu_v3_production.xlsx`) contains aggregated vintage-month data only

- **ragu_v3_production.ipynb**: New production output notebook for RAGU V3 quarterly/monthly numbers
  - Applies V3 formula at the individual account level, then aggregates via amt_financed-weighted average (individual-first approach)
  - Granularity toggle: `granularity = 'q'` (quarterly) or `'m'` (monthly) in Cell 1
  - V3 formula per account: UL = `0.9 - (MS-125)*0.027 - (72-term)/240`, GL = `(1-LM)*UL/0.027`, Recovery = `UL*F*R*100`, LTV = `LTV_COEF*(B-actual)`, APR = `(B-actual)/0.01*APR_MULT`
  - Purely additive RAGU: `MS + GL + Recovery + LTV + APR` (higher score = lower expected loss)
  - KMX rescaling applied per account: impacts scaled by 0.65, model score offset by 50
  - Population-aware aggregation: model_score and GL use full population, LTV/APR use bbvalue-populated, recovery/RAGU use fully-scored subset
  - Rollup groups: Franchise Independent, nonKMX, POS (weighted average by amt_financed)
  - Excel export (`ragu_v3_production.xlsx`) contains aggregated vintage-LOB data only -- no individual loan rows
  - Optional MMI market adjustment (`MMI_ENABLED`): applies 24-month-lagged Manheim price change as post-scoring overlay using auto-derived coefficient (38.31 RAGU pts per 1.0 pct change)
  - Uses `vintage_level_ula_query_v2.txt` (with `con_term`) and shared cache (`cache/ula_v2.pkl`, `cache/dla_v1.pkl`, `cache/new_recovery_v1.pkl`)
  - Separated from `ragu_v3_validated.ipynb` to keep validation and production concerns isolated

### Changed
- **ragu_v3_validated.ipynb**: Refactored formula to use score-dependent unit loss (UL) instead of constant GL multiplier
  - GL impact: `(1 - LM) * UL / 0.027` replaces `(1 - LM) * 16.51`; UL = `0.9 - (MS-125)*0.027 - (72-term)/240`
  - Recovery impact: `UL * F * R * 100` replaces `F * R * 16.51`
  - LTV impact: single blended coefficient `LTV_COEF * (baseline - actual)` replaces decomposed `F * beta_ltv * (baseline - actual) * GL_mult`
  - APR impact unchanged
  - Added `con_term` to vintage-LOB weighted averages for dynamic UL computation
  - Added `SCENARIOS` config dict with LOO-derived min/max coefficient sets (APR, LTV, F)
  - Added sensitivity re-scoring loop (Cell 15): scores all vintages under 7 coefficient scenarios
  - Added sensitivity visualization (Cell 16): R-squared, slope, and score-shift comparison across scenarios
  - Added UL_TO_MS anchor sensitivity (Cell 17): stress-tests the 0.027 MS-to-UL conversion factor across 0.024-0.031 range

### Added
- **vintage_sensitivity_analysis.ipynb**: Leave-one-out vintage year sensitivity analysis for RAGU V3 coefficients
  - Tests stability of GL multiplier (16.51), APR multiplier (0.8223), find rate F (0.75), and beta_ltv (0.0903) under vintage year exclusion
  - Five scenarios: full sample (2020-2023), exclude 2020, exclude 2021, exclude 2022, exclude 2023
  - Gross loss OLS: `gross_loss_pct ~ model_score + loss_multiplier + apr` re-estimated per scenario
  - Recovery/LTV OLS: `recovery_pct ~ R + LTV` (chargeoffs with LTV in [100%, 200%)) re-estimated per scenario
  - Out-of-sample R-squared evaluation on the held-out vintage year
  - Coefficient stability metrics (CV, max deviation from full-sample) with interpretation
  - Grouped bar chart visualization of coefficient stability across scenarios

### Added
- **ste_ragu_individual.ipynb**: New STE individual-level RAGU notebook
  - Computes account-level RAGU scores for the STE LOB using `ste_ragu_ula.txt`, `ste_ragu_recovery.txt`, and `ste_ragu_weekly.txt`
  - SFS override at individual level: joins SFS contract chain data on `account_number` to replace model_score, LTV, and APR with loan-level SFS-sourced values (`con_risk_model_score`, `bbltv`, `con_apr`); ULA values retained as fallback for unmatched loans
  - Impact bounds applied at individual level: gross_loss [-20, 10], recovery [-10, 20], LTV [-15, 15], APR [-10, 10]
  - Full Jensen's correction framework (adj_prop, adj_contrib, adj_exact) for recovery and LTV impacts
  - Population-aware aggregation to vintage-LOB level with `ragu_score` (bounded) and `ragu_score_agg` (exact-adjusted)
  - Aggregate Excel export to `ste_ragu_individual.xlsx` (no individual loan sheet due to dataset size)
  - Sandbox upload to `sandbox.gl_ragu_individual_ste` with batch insert (weekly granularity only)
  - Default granularity: weekly ('w'); STE-specific caps (bbltv <= 10, pti <= 0.6, income <= 200k)
  - Uses distinct pickle cache (`cache/ste_indiv_*.pkl`) to avoid collision with aggregate STE notebook

### Changed
- **ltv_heuristic_validation.ipynb**: Revamped to analyze recovery performance (gross loss minus CNL) instead of raw CNL rates
  - SQL query now pulls `gross_loss_ragu` instead of `ragu_score` from `sandbox.gl_ragu_individual`
  - Actuals query now pulls both `gross_loss_amt` and `net_loss_amt` from `edwnpi.svc_master_monthend`
  - Rows: LTV by 2% bands from 130% to 170% (replaces LTV quintiles)
  - Columns: `gross_loss_ragu` deciles (10 buckets, replaces `ragu_score` quintiles)
  - Values: Recovery rate = (gross_loss - CNL) / proceeds, isolating the recovery portion of loss
  - Added mirror loan count table with same row/column structure
  - Simplified to single combined non-KMX table (removed per-LOB breakdown)
  - Regression cell adapted to regress recovery rate on LTV within each gross_loss_ragu decile
  - Added Excel export (`ltv_heuristic_validation.xlsx`) with Recovery Rate and Loan Count sheets

### Added
- **lob_permutations_ragu.ipynb**: New LOB permutations RAGU notebook for exploring alternative line-of-business combinations
  - Scores FRN-Franchise (franchise dealers only), FLD, and STG individually
  - Two rollup groups: FRN-Franchise + FLD + STG (all three), and FRN-Franchise + STG
  - FRN-Franchise determination uses a separate inline SQL query with regex-based fallback on `doing_business_as_name` against known car brand names when `dealer_type_name` is NULL
  - Model scores computed per-segment from each segment's own population (not shared across LOBs)
  - Configurable multi-granularity support (quarterly, monthly, weekly) defaulting to quarterly
  - Uses existing `vintage_level_ula_query.txt`, `new_dll_query.txt`, `new_recovery_queryt.txt` with no modifications
  - Separate pickle cache (`cache/perm_*.pkl`) to avoid conflicts with other notebooks
  - Excel export to `lob_permutations_ragu.xlsx` with one sheet per granularity

### Added
- **pos_gl_attribution.ipynb**: New POS-level gross loss attribution notebook
  - Combines KMX and non-KMX (AN, FRN, STG, FLD, ENT) adjustment-level attributions into a single POS view
  - Uses amt-financed-weighted roll-up of per-LOB log-ratio attributions (mathematically exact, sums to POS GLI)
  - Avoids the need for a synthetic POS-level multiplier entirely
  - Idempotent design: all DataFrames constructed fresh, no appending, cache writes are atomic overwrites
  - `run_every_query` switch: `True` forces fresh SQL execution; `False` loads from shared `cache/` pickles
  - Reuses same data sources as `nonkmx_gl_diagnostics.ipynb` and `kmx_mtns_ragu.ipynb` (`cache/ula_v1.pkl`, `cache/dla_v1.pkl`, `cache/new_recovery_v1.pkl`)
  - KMX adjustments (33 steps) and non-KMX adjustments (18 steps) kept as separate row labels, reordered adjacently by conceptual group
  - Single "Population Weighting / Mixing" residual row captures the bridge between equal-weighted diagnostic multipliers and amt-financed-weighted RAGU GLI
  - Per-LOB attribution sheets included alongside the POS roll-up sheet in `pos_gl_attribution.xlsx`
  - Time-comparable: same methodology and weighting every vintage; LOB mix shifts reflected naturally

### Added
- **ltv_heuristic_validation.ipynb**: New notebook to validate the LTV multiplier heuristic (expected=17) in the RAGU V1 formula
  - Pulls `sandbox.gl_ragu_individual` (full `ragu_score`) and actual CNL data (`net_loss_amt`) from `edwnpi.svc_master_monthend`
  - Segments by full RAGU score quintiles and LTV quintiles, per LOB (non-KMX only: AN, ENT, FLD, FRN, STG)
  - Computes dollar-weighted actual CNL rates per (RAGU quintile x LTV quintile) cell
  - Derives implied LTV multiplier via regression of CNL on 1/LTV within each risk tier for comparison against expected multiplier of 17

### Changed
- **ragu_individual.ipynb**: Added `ragu_score` column to `sandbox.gl_ragu_individual` sandbox upload (DDL, INSERT, column selection)

### Changed
- **bareboned_ragu_new.ipynb**: Expanded KMX state-level adjustments in `get_ula_multiplier_kmx`
  - Removed `state_counter_adj` block (1.012x multiplier for non-LA/GA/TXCA states with model score < 150)
  - Expanded `txca_flag` to include FL and CO (now covers TX, CA, FL, CO)
  - Added Illinois (IL) adjustment: 1.2x multiplier following Louisiana pattern (`1 + 0.2 * illinois_flag`)
  - Added Mississippi (MS) adjustment: 1.25x multiplier following Louisiana pattern (`1 + 0.25 * mississippi_flag`)
  - New flags added to data-prep cell: `illinois_flag` (state == 'IL'), `mississippi_flag` (state == 'MS')

### Added
- **model_mix_distribution.ipynb**: New notebook showing monthly percent of booked loans by `risk_model_name` and `risk_model_version`
  - Queries `edwnpi.los_deal_current_fact` joined with `edwnpi.dealer_rollup_scd_current` from 2020-01-01 onward
  - Two separate crosstab tables: KMX (Mountain models) and nonKMX (Franchise models and legacy names)
  - Each table shows row-normalized percentages per month with a `total_loans` column for absolute counts
  - Weighted average model score (`con_risk_model_score`, weighted by `amt_financed`) shown per model label per month, with an overall weighted average column
  - Pickle caching via `cache/model_mix_v1.pkl` for offline re-runs

### Added
- **ragu_v_two_individual.ipynb**: New notebook applying RAGU V2 formulas at the individual loan level
  - Scores each account individually using V2 formulas, then aggregates via amt_financed-weighted average
  - V2 unit loss: `UL = 0.9 - (MS - 125)*0.027 - (72 - term)/240` per account (uses `con_term` from V2 ULA query)
  - V2 gross loss: `(1 - loss_multiplier) * UL / 0.027` per account
  - V2 recovery: baseline-free `UL * F * R / 0.027` per account (no per-LOB recovery baselines)
  - V2 linear LTV: `(baseline - actual) * 17` per account (no Jensen gap)
  - Single universal baseline for all LOBs: LTV=1.5, APR=0.24
  - Uniform KMX rescaling: `* 0.65` on all components, `+ 50` on model score, applied per account
  - No Jensen correction needed: all V2 formulas are linear, so `E[f(x)] = f(E[x])` by construction
  - Vintage-LOB aggregation with POS, nonKMX, and Franchise Independent rollups
  - Exports: `barebones_ragu_v2_individual.xlsx` (individual + aggregate sheets), `all_df_v2_individual.csv` (aggregated scores only), Redshift `sandbox.ragu_v2_individual_monthend_current` / `sandbox.ragu_v2_individual_monthend` (aggregated), `sandbox.ragu_v2_ind` (account-level)

### Added
- **apr_heuristic_validation.ipynb**: New notebook to validate the 0.7 APR multiplier heuristic in the RAGU gross loss formula
  - Pulls `sandbox.gl_ragu_individual` and actual chargeoff data from `edwnpi.svc_master_monthend`
  - Segments by gross_loss_ragu quintiles and APR bands, separately for KMX and non-KMX
  - Computes dollar-weighted actual gross loss rates per (quintile x APR band) cell
  - Derives implied APR multiplier via regression within each risk tier for comparison against expected 0.7 (non-KMX) and 1.077 (KMX)

### Fixed
- **Ragu_v_two.ipynb**: Fixed `MemoryError` in `run_sql` when loading large query results (~2.1M rows) by reading in chunks of 200k rows via `pd.read_sql_query(chunksize=200_000)` and concatenating, instead of materializing the entire result set at once

### Added
- **Ragu_v_two.ipynb**: RAGU V2 notebook with updated scoring formulas
  - New unit loss formula: `UL = 0.9 - (MS - 125)*0.027 - (72 - term)/240` replaces hardcoded 0.5
  - New gross loss impact: `(1 - loss_multiplier) * UL / 0.027` with measured UL and updated conversion factor
  - New recovery impact: `UL * F * (R/B - 1) / 0.027` decoupled from gross loss, uses find rate (F=0.75) instead of double-counting R
  - Linear LTV impact: `(baseline - actual) * 17` replaces nonlinear `1/LTV` form, eliminating Jensen gap
  - Pure additive RAGU score: `MS + GL + Rec + LTV + APR` replaces expanded multiplicative blend
  - Consistent KMX rescaling: `* 0.65` on all components (+ 50 offset on model score) replaces partial `/ 0.65` on LTV/APR only
- **vintage_level_ula_query_v2.txt**: ULA query with `cd.con_term` added for dynamic unit loss calculation
- **documentation/plan/ragu-v2-formula-changes.md**: Full documentation of V2 formula derivations and design decisions

### Added
- **co_timing_all_variations.ipynb**: Notebook to generate CSV of charge-off timing for all FRN4 input combinations
  - Covers every combination of model_version (franchise4.0, franchise4.1), LOB (AN, ENT, FLD, FRN, STG, STE, MCY), term group (36, 48, 60, 72), and tag (0-15)
  - Produces 896-row CSV (`co_timing_all_variations.csv`) with columns: model_version, lob, term, tag, charge_off_month, pay_off_month, total_loss_month
  - Logic ported from `co_mapping_init` (`get_scenario_timing_frn_4`); ORL excluded per design

### Changed
- **ragu_individual.ipynb: Per-metric population-aware aggregation and full-portfolio model score**
  - Removed `bbvalue > 0` hard filter so ALL accounts contribute to `model_score` and `gross_loss_impact` weighted averages
  - Updated `weighted_average_and_sum` to use per-metric denominators: each metric's denominator only includes `amt_financed` from accounts where that metric is not NaN
  - Guarded `ltv` computation with `bbvalue > 0` check (NaN for accounts without bbvalue)
  - `apr_impact` computed independently for all accounts (no bbvalue guard -- APR is available regardless of bbvalue)
  - Added `ltv` and `apr` to individual output columns and aggregated metrics for side-by-side comparison
  - Added `Weighted LTV` and `Weighted APR` rows to `METRIC_ROWS` in Excel export
  - Added population breakdown diagnostics (total / bbvalue>0 / scored counts and amt_financed)

### Added
- **ragu_individual.ipynb: Jensen's inequality redistribution at the individual level**
  - Added second-order variance/covariance correction for `recovery_impact` and `ltv_impact` nonlinearity
  - Correction is computed at the vintage-LOB group level and redistributed back to individual accounts
  - Two redistribution strategies provided as separate columns:
    - `recovery_impact_adj_prop` / `ltv_impact_adj_prop`: proportional scaling (uniform ratio)
    - `recovery_impact_adj_contrib` / `ltv_impact_adj_contrib`: contribution-based (correction proportional to each account's contribution to the nonlinearity)
  - Raw `recovery_impact` and `ltv_impact` remain untouched as the primary per-account values
  - Added `recovery_multiplier` and `unit_loss_score` to individual output for diagnostic transparency
  - Adjusted columns propagate through vintage-LOB aggregation and rollups

- **APR weighting now uses full population in `ste_ragu_postintegration.ipynb`**
  - `get_ragu_score()`: APR weighted average computed over all accounts (`mix_df`) instead of only BB-populated accounts (`bb_populated_df`)
  - LTV, loss_multiplier, and bbvalue remain restricted to BB-populated accounts
  - Aligns APR calculation with tzero.ipynb methodology
- **Commented out `amt_financed <= 75000` filter from STE-only notebooks** (for testing)
  - `ste_ragu_postintegration.ipynb`: Commented out in both ULA and dual-path filtered data
  - `STE_gl_diagnostics.ipynb`: Commented out in both ULA and dual-path filtered data
- **Added `bbltv <= 10.0` filter to STE notebooks** (previously had no bbltv cap)
  - `ste_ragu_postintegration.ipynb`: Added to both ULA path and dual-path (`ste_filtered`)
  - `STE_gl_diagnostics.ipynb`: Added to both ULA path and dual-path (`ste_filtered`)
- **BBLTV cap raised from <= 4.0 to <= 10.0** across all RAGU and GL diagnostic notebooks
  - `bareboned_ragu_new.ipynb`: 3 filter conditions updated (ula_df_total, weekly_df, raw_ula)
  - `nonkmx_gl_diagnostics.ipynb`: 1 filter condition updated (ula_df_total)
  - `kmx_mtns_ragu.ipynb`: 1 filter condition updated (ula_df_total)
  - `weekly.ipynb`: 2 filter conditions updated (active filter + commented-out line)
  - `weekly copy.ipynb`: 2 filter conditions updated (active filter + commented-out line)

### Added
- **control_room.ipynb**: Centralized orchestration notebook for all RAGU pipelines
  - Single configuration cell with all dates, granularity, LOBs, baselines, model parameters, and boolean flags
  - Pre-flight checks: Redshift connectivity, cache freshness report, Excel lock detection, parameter validation
  - Two execution modes: `PARALLEL_ALL=False` (safe group ordering A->B->C) or `PARALLEL_ALL=True` (all notebooks at once)
  - Per-notebook toggle flags (`RUN_DIAGNOSTIC`, `RUN_BAREBONED_RAGU`, `RUN_STE_RAGU`, `RUN_NONKMX_GL_DIAGNOSTICS`, `RUN_STE_GL_DIAGNOSTICS`, `RUN_KMX_MTNS_RAGU`)
  - Shared query/upload flags (`RUN_EVERY_QUERY`, `UPDATE_TABLES`, `RUN_SANDBOX`, `RUN_HISTORICAL`)
  - Parallel execution within groups via `ThreadPoolExecutor`, error isolation per notebook
  - Summary dashboard with status, runtime, and error reporting
  - Output archiving to `control_room_runs/{timestamp}/` for audit

### Changed
- **All 6 notebooks**: Added papermill `parameters` cell tag to config cells for control room integration
  - `ragu_diagnostic.ipynb`: Cell 1 tagged; 3 progress markers added
  - `bareboned_ragu_new.ipynb`: Cell 0 tagged; 4 progress markers added
  - `ste_ragu_postintegration.ipynb`: Cell 0 tagged; 4 progress markers added
  - `STE_gl_diagnostics.ipynb`: Cell 0 tagged; 3 progress markers added
  - `nonkmx_gl_diagnostics.ipynb`: Cell 0 tagged; 3 progress markers added
  - `kmx_mtns_ragu.ipynb`: Cell 1 tagged; 3 progress markers added; `run_from_pickle` normalized to derive from `run_every_query`
  - All notebooks remain fully standalone -- the parameters tag is metadata-only and invisible to normal Jupyter execution
  - Progress `[PROGRESS]` print statements added at natural boundaries (data fetch, scoring, export) for control room tracking

### Added
- **STE_gl_diagnostics.ipynb**: New STE gross loss attribution diagnostic notebook
  - Mirrors `nonkmx_gl_diagnostics.ipynb` 9-cell structure adapted for STE LOB
  - Uses STE-specific data sources (`ste_ragu_ula.txt`, `ste_ragu_recovery.txt`) and cache (`cache/ste_ula_v1.pkl`, `cache/ste_recovery_v1.pkl`)
  - No DLA (pricing_scalar = 1.0); LOB relabeled from STG to STE
  - STE-specific flag thresholds (high_pti > 0.2, student_loan_flag = 0, mcy_low_mileage = False, ent_flag = False)
  - GL-only focus: no dual-path override (ms_original, LTV, APR from ULA data for attribution consistency)
  - Per-LOB log-based attribution decomposition with Excel export (`STE_gl_diagnostics.xlsx`)

### Fixed
- **kmx_mtns_ragu.ipynb**: Fixed attribution gross loss mismatch where `build_attribution_df` TOTAL did not match the actual RAGU score's `gross_loss_impact`
  - Root cause: the diagnostic loop recomputed `gross_loss_impact = 25 * (1 - wtd_mult)` from its own call to `get_ula_multiplier_kmx_diag`, which diverged from the production `get_ula_multiplier_kmx` result used by `get_ragu_score`
  - Fix: `build_attribution_df` and `build_output_df` now source `gross_loss_impact` directly from `results_by_model` (the output of `get_ragu_score`), ensuring the attribution decomposes the exact same value that appears in the RAGU score decomposition
  - Added `ragu_gli_dict` parameter to both functions; built from `results_by_model` per MTN model before the diagnostic loop

### Added
- **nonkmx_gl_diagnostics.ipynb**: New nonKMX gross loss attribution diagnostic notebook
  - Mirrors `kmx_mtns_ragu.ipynb` structure but iterates over nonKMX LOBs (AN, FRN, STG, FLD, ENT) instead of MTN models
  - Configurable granularity (`'w'`/`'m'`/`'q'`) matching `bareboned_ragu_new.ipynb` pattern
  - Reuses `cache/` pickles from `bareboned_ragu_new.ipynb` (ula_v1, dla_v1, new_recovery_v1)
  - Per-LOB log-based attribution decomposition with step labels matching `get_ula_multiplier_nonkmx_diag`
  - Excel export (`nonkmx_gl_diagnostics.xlsx`) with per-LOB Mult Steps, Flags, and Attribution sheets

### Changed
- **ste_ragu_postintegration.ipynb**: Restructured to mirror `bareboned_ragu_new.ipynb` cell layout (CELL 1 through CELL 12) for control-room integration readiness
  - **CELL 1**: Consolidated all configuration into a single cell; `LOBS=['STE']` (relabeled from STG to avoid collision with bareboned's STG LOB); `PRICING_SCALAR=1.0` (no DLA); `USE_STE_METRICS=True` (mandatory dual-path)
  - **CELL 2**: Imports and derived config matching bareboned pattern (date_col, period range, min_date_sql)
  - **CELL 3**: Utility functions copied from bareboned plus `_ste_weighted_avg` for the dual-path metric aggregation
  - **CELL 4**: ULA multiplier functions (`get_ula_multiplier_nonkmx`, `get_ula_multiplier_kmx`) from bareboned; removed legacy `auc_pred`
  - **CELL 5**: Data fetch via `cached_sql` for `ste_ragu_temptables.txt`, `ste_ragu_ula.txt`, `ste_ragu_recovery.txt`, and `ste_ragu_weekly.txt` (replaces old `'ste_query copy'` reference); no DLA query
  - **CELL 6**: Period assignment, date-window filter, LOB relabel (STG to STE), STE caps (amt_financed <= 75000, pti <= 0.6, income <= 200000)
  - **CELL 7**: Flag construction with STE-specific thresholds (high_pti at 0.2, student_loan_flag forced to 0, pricing_scalar = 1.0); ms_df build; mandatory `ste_metrics_df` dual-path build from `ste_ragu_weekly.txt`
  - **CELL 8**: `get_ragu_score` with mandatory `ste_metrics_df` override for MS/LTV/APR (gross loss and recovery remain from ULA path)
  - **CELL 8b**: Rollup aggregation placeholder (empty for single-LOB STE; control room handles cross-notebook rollups)
  - **CELL 9**: Unified Excel export matching `barebones_ragu.xlsx` format (metric grid per vintage, sheet named by granularity)
  - **CELL 10**: CSV output (`ste_all_df.csv`) and optional Redshift upload
  - **CELL 11**: Diagnostic comparison of RAGU output vs STE weekly metrics
  - **CELL 12**: Summary statistics and flag rate diagnostics
  - Removed: 49-cell scattered layout, `breaaaaaaak` stop-cell, duplicate imports, legacy Excel workbook manipulation cells (30-46), `auc_pred` function, `open_tl_flag` chained assignment bug

### Added
- **ragu_diagnostic.ipynb**: Parallel sandbox table updater (Cells 8-11) gated by the `update_tables` flag
  - **Cell 8**: Update configuration with `update_tables` flag (default `False`), `UPDATE_PLAN` list of the 6 user-owned tables (5 DDL + 1 stored procedure), `TEMPTABLES_PATH` pointer, and `UPDATE_MAX_WORKERS=3` tuned for heavy DDL sharing the `edwnpi.los_deal_current_fact` fact table
  - **Cell 9**: Parser that reads `ragu_temptables` as text, extracts each table's `SELECT INTO` body via regex anchored on its fully-qualified `DROP TABLE IF EXISTS` and `select top N *` markers, and rewrites the `INTO <table>` clause to target a `<table>_new` staging name; statement builder expands each DDL entry into 10 fine-grained steps (`drop_staging`, `build_new`, `gate_count`, `begin`, `drop_old`, `rename_curr_old` (skipped on first run via `pg_catalog.pg_tables` existence check), `rename_new_curr`, `commit`, `grant`, `drop_old_final`); parallel dispatch via `ThreadPoolExecutor(max_workers=3)` with per-step error attribution
  - **Cell 10**: Post-update moderate integrity probe reusing Cell 3's `check_table()` on only the 6 updated tables in parallel; joins update results with probe results and computes `post_key_null_pct` from `post_total_rows` and `post_non_null_key_rows`
  - **Cell 11**: Color-coded update verdict with step-level status attribution (`BUILD_FAILED`, `GATE_FAILED`, `SWAP_FAILED`, `GRANT_FAILED`, `CLEANUP_WARNING`, `UPDATE_SUCCESS_BUT_EMPTY`, `UPDATE_SUCCESS_BUT_STALE`, `POST_PROBE_ERROR`, `PROC_FAILED`, `UPDATE_OK`) and top-level `UPDATE BLOCKED` / `UPDATE WARNINGS` / `ALL UPDATES CLEAR` verdict
- **ragu_diagnostic.ipynb**: Added `sandbox.temp_blackbook_values_ragu` to `TABLES_TO_CHECK` (keyed on `account_number`, uses `ACCT_FRESHNESS` template, `used_by="ULA / Recovery"`) and to `STALENESS_THRESHOLDS` (7 days) so it now receives the same diagnostic coverage as the other 5 user-owned sandbox tables

### Changed
- **kmx_mtns_ragu.ipynb**: Migrated the pickle cache layer to the same per-table pattern as `bareboned_ragu_new.ipynb` so `run_from_pickle = True` reliably skips every SQL call
  - **Utilities cell**: Added `cached_sql(filename, pickle_name, sub_list=None, connection=None, force_refresh=False)` helper matching the signature used in `bareboned_ragu_new.ipynb`
  - **Data fetch cell**: Replaced the ad-hoc `if run_from_pickle: get_pickle(...) else: run_sql(...)` block (which read the fragile 3-tuple `(ula_df_total, rra_df_total, dla_df)_unrefined_pickle` that collides with `revamped_ragu.ipynb`'s different 3-tuple schema) with three independent per-table caches under `cache/`:
    - `cache/ula_kmx_v1.pkl` -- KMX-filtered ULA (this notebook passes `AND dru.riskdealergroup = 'KMX'` via `sub_list`, so the cached DataFrame is a KMX subset of rows, a different population than `cache/ula_v1.pkl` used by `bareboned_ragu_new.ipynb`; kept as a separate schema-tagged file to prevent cross-notebook contamination)
    - `cache/dla_v1.pkl` and `cache/new_recovery_v1.pkl` -- same queries and schemas as in `bareboned_ragu_new.ipynb`, so both notebooks now share these two caches
  - A single Redshift connection is opened only when at least one of the three pickles is missing or `run_from_pickle=False`; if all three pickles exist and `run_from_pickle=True`, the run is fully offline
  - **Migration note**: The legacy `new_recovery_pickle` and the shared `(ula_df_total, rra_df_total, dla_df)_unrefined_pickle` files remain on disk but are no longer read or written by this notebook; the first run with `run_from_pickle=False` repopulates `cache/*.pkl`, after which `run_from_pickle=True` runs fully offline
- **bareboned_ragu_new.ipynb**: Rebuilt the pickle cache layer so `run_every_query = False` reliably skips every SQL call
  - **Cell 3 (utilities)**: Added `cached_sql(filename, pickle_name, sub_list=None, connection=None, force_refresh=False)` helper that returns the pickled DataFrame when present and not forced, otherwise runs the SQL query, stores the result to pickle, and returns the DataFrame; missing pickle silently falls through to SQL so a deleted cache file self-heals on next run
  - **Cell 5 (data fetch)**: Replaced the monolithic 3-tuple pickle (`(ula_df_total, rra_df_total, dla_df)_unrefined_pickle`, which collided with `revamped_ragu.ipynb` writing a different 3-tuple schema to the same filename) with four independent per-table caches under `cache/` with `_v1` schema tags: `cache/ms_v1.pkl`, `cache/ula_v1.pkl`, `cache/dla_v1.pkl`, `cache/new_recovery_v1.pkl`; a single Redshift connection is opened only when at least one of the ULA/DLA/new_recovery pickles is missing or `run_every_query=True`; removed the dead local `run_query = False` override that made the original `if run_query or run_every_query` gate confusing
  - **Cell 7 (flag creation)**: Removed the dead `store_pickle(ula_df_total, '(ula_df_total, rra_df_total)_refined_pickle')` write; nothing read the refined pickle so the 40 MB file was accumulating on every run for no downstream consumer
  - **Cell 11 (weekly comparison)**: Replaced the unconditional `run_sql('weekly_query')` call with `cached_sql('weekly_query', 'cache/weekly_v1.pkl', force_refresh=run_every_query)`; previously this cell hit Redshift on every run regardless of the `run_every_query` flag, which was the actual failure source when users set `run_every_query=False` and expected a fully offline run
  - **Cell 12 (dropna diagnostic)**: Changed the raw ULA reload from the old 3-tuple unpack (`raw_ula, _, _ = get_pickle('(ula_df_total, rra_df_total, dla_df)_unrefined_pickle')`) to `get_pickle('cache/ula_v1.pkl')`, matching the new cache layout and eliminating the silent tuple-position-corruption risk
  - **Migration note**: The legacy `(ula_df_total, rra_df_total, dla_df)_unrefined_pickle` and `(ula_df_total, rra_df_total)_refined_pickle` files remain on disk but are no longer read or written; the first run with `run_every_query=True` repopulates `cache/*.pkl`, after which `run_every_query=False` runs fully offline
- **ragu_diagnostic.ipynb**: Refresh pattern for user-owned sandbox tables now uses staging + atomic rename instead of the raw `DROP` then `SELECT INTO` pattern in `ragu_temptables`; the public table name is always queryable because data is built under `<table>_new`, gated on `COUNT(*) > 0`, then swapped into place by renaming the current table to `<table>_old` and the staging table to the public name inside a single uncommitted pyodbc transaction that commits only after both renames succeed (so if the second rename fails, both are rolled back and the public name retains its old data). First-run (no prior table) is handled via a `pg_catalog.pg_tables` lookup that skips the first `ALTER TABLE ... RENAME` conditionally. The inline `SELECT TOP 1 *` verifications from the source file are superseded by a stronger moderate integrity probe (row count, key-column null rate, max `application_received_date` via join) that runs after all updates complete

### Fixed
- **kmx_mtns_ragu.ipynb**: Fixed KMX attribution gross loss impact mismatch with actual RAGU result
  - The attribution cell computed `wtd_mult` on a different population than `get_ragu_score`: used `dropna(subset='bbvalue')` (includes bbvalue=0 rows), skipped the recovery merge, and skipped account-level deduplication
  - Aligned `wtd_mult` computation to mirror `get_ragu_score` exactly: merge with `new_recovery` (left join), deduplicate by `account_number` (keep='first'), and filter to `bbvalue.notna() & (bbvalue > 0)`
  - Attribution `TOTAL (check)` now matches the actual `gross_loss_impact` from `get_ragu_score`
- **ragu_diagnostic.ipynb** (Cell 9): Atomic swap was not actually atomic. The step sequence sent explicit `BEGIN;` and `COMMIT;` SQL statements but the Python loop called `conn.commit()` after each non-`begin` step, terminating the Redshift transaction between the two `ALTER TABLE ... RENAME` statements. This meant a failure between `rename_curr_old` and `rename_new_curr` would leave the database with the current table renamed to `_old` and nothing at the public name, breaking downstream queries. Fix: removed the decorative `begin` and `commit` SQL steps (they relied on `autocommit=True` semantics that pyodbc does not use here), and flagged `rename_curr_old` with `defer_commit=True` so it stays in an open transaction until `rename_new_curr` commits them together. On any error between the two renames, the except block's `conn.rollback()` now correctly reverts both

### Fixed
- **kmx_mtns_ragu.ipynb**: Added `AND dru.riskdealergroup = 'KMX'` SQL filter to the `run_sql` call for `vintage_level_ula_query.txt` via the `sub_list` substitution parameter; the query was returning all LOBs (~3.8M rows) causing a MemoryError during pandas DataFrame conversion, when only KMX rows are needed by this notebook
- **vintage_level_ula_query.txt**: Replaced stale `sandbox.kmx_los_new_sp` as sole source of `pull_type` with `COALESCE(kmx.app_type, lkat.app_type)`, prioritizing the current `sandbox.kmx_approvals` table (fresh through 2026-04-20) over the outdated `kmx_los_new_sp` (NO_FRESHNESS status per diagnostic)
- **bareboned_ragu_new.ipynb**: Updated `soft_pull_flag` derivation to accept both `'softpull'` and `'prequal'` values via `.isin()`, since `sandbox.kmx_approvals` uses `'prequal'` for soft-pull applications

### Added
- **ragu_diagnostic.ipynb**: New parallel SQL discovery and diagnostic notebook
  - Probes all 15 Redshift tables used by `bareboned_ragu_new.ipynb` in parallel via `concurrent.futures.ThreadPoolExecutor`
  - Two-pass probe per table: Pass 1 checks existence, row count, null-key rate, and fetches sample rows (no joins); Pass 2 checks data freshness via own date column or join-based query back to `los_deal_current_fact`
  - Sandbox/temp tables submitted first for early failure detection; stable `edwnpi.*` tables last
  - Query execution timeout (`conn.timeout`) prevents indefinitely hanging probes
  - Separate `error` and `freshness_error` fields distinguish "table is down" from "table is up but join target is down"
  - Sample data viewer displays `SELECT TOP N *` for each table with column inventory
  - Query file existence check for all 4 `.txt` SQL files
  - Summary DataFrame with raw metrics (no hardcoded thresholds) for discovery before building guardrails
  - Phase 2 guardrails cell (Cell 7): status labels (OK, DOWN, EMPTY, STALE, NO_FRESHNESS, FRESHNESS_ERROR), per-table staleness thresholds (3 days for edwnpi date-bearing tables, 7 days for sandbox tables), color-coded styled DataFrame, and top-level BLOCKED/WARNINGS/ALL CLEAR verdict
  - Pass 2 enhanced with `recent_rows` count within the 90-day date window for volume-drop detection
  - Suppressed pandas SQLAlchemy `UserWarning` noise during parallel probe
  - Full freshness coverage for all 16 tables: added `DEALER_NUM_FRESHNESS` and `DEALER_ID_FRESHNESS` join templates for dealer-keyed tables (`dealer_rollup_scd_current`, `crm_dealer_dim`, `dealer_attributes_pivot`, `nonkmx_dealer_loss_data`); set `date_dim` to use its own `calendar_date` column directly; all 16 tables now have staleness thresholds in the guardrails cell

### Fixed
- **ragu_diagnostic.ipynb**: Changed all 6 join-based freshness query templates from `MAX(cd.book_date)` to `MAX(cd.application_received_date)`; `book_date` can post-date a sandbox table's last refresh (a deal applied April 15 may book April 20), making stale tables appear fresh; `application_received_date` correctly reflects the last date the sandbox table has coverage for

### Fixed
- **kmx_mtns_ragu.ipynb**: Aligned `get_ula_multiplier_kmx` with `bareboned_ragu_new.ipynb` to resolve significant RAGU score discrepancies
  - Added missing `+ ula_df.secured_credit_flag * 0.295` coefficient in the MTN 3.0 soft-pull block; previously the secured+narrowed path applied a multiplier of 1.0 instead of 1.295
  - Added missing fraud adjustment step (`*= 1 + (ula_df.fraud_adjustment - 1)`) for all MTN models (3.0, 3.1, 3.2, 4.1); applied after soft pull and before clip, matching the reference
  - Removed three sub-MS decline rules (`sub130msflag * 0.2`, `sub140msflag * 0.15`, `sub135msflag * 0.2`) and corresponding flag derivations that do not exist in the reference
  - All changes mirrored in `get_ula_multiplier_kmx_diag`
- **kmx_mtns_ragu.ipynb**: Changed MTN 4.1 model score transform (`142 + (score - 142) * 1.5`) from copy-based to in-place on `ula_df_total`, matching the reference; previously score-based masks (TX/CA, state counter) in `get_ula_multiplier_kmx` used untransformed scores for 4.1 loans
- **kmx_mtns_ragu.ipynb**: Removed spurious `ula_df_total[ula_df_total.bbvalue > 0]` filter that excluded null/zero BB loans before RAGU processing; the reference handles BB filtering inside `get_ragu_score`
- **kmx_mtns_ragu.ipynb**: Updated `rebuild_ms_df` to skip the MTN 4.1 transform (now applied upstream in-place) to prevent double application

### Changed
- **kmx_mtns_ragu.ipynb**: Aligned with `bareboned_ragu_new.ipynb` for full diagnostic parity
  - **Dynamic granularity**: Replaced hardcoded monthly vintage loop with `pd.to_period`-based period assignment supporting weekly (`app_date`), monthly (`book_date`), and quarterly (`book_date`) via `granularity` config
  - **Removed RRA dependency**: Eliminated `rra_df_total`, `vintage_level_rra_query.txt`, `auc_pred` function, and all RRA processing; recovery merged directly from `new_recovery`
  - **Removed legacy MS query**: Eliminated `postmodern_ms_query.txt` and `use_legacy_ms_query` flag; `ms_df` now derived from ULA data with MTN 4.1 score transformation
  - **New RAGU decomposition**: `get_ragu_score` now uses additive decomposition (`gross_loss_impact`, `recovery_impact`, `ltv_impact`, `apr_impact`) matching `bareboned_ragu_new.ipynb`, replacing `ms_gla`/`ms_exclude_ltv`/`only_recovery_ragu`/`ms_100_ltv`
  - **Added APR adjustment**: APR impact included in RAGU score using baseline from `BASELINES` config
  - **Centralized config**: `BASELINES`, `MODEL_PARAMS`, `DATE_COL_MAP`, `PERIOD_FREQ_MAP` replace scattered hardcoded values
  - **Removed nonKMX flags**: Stripped `dealer_filter_a/b`, `ent_fld_flag`, `small_amt_financed_flag`, `high_mileage_vehicle_flag`, and 15+ other nonKMX-only flags that are never used by `get_ula_multiplier_kmx`
  - **Added weekly-matching filters**: `amt_financed <= 75000`, `pti <= 0.6`, `bbltv <= 4.0`, `total_income <= 200000` matching `bareboned_ragu_new.ipynb`
  - **Removed dead utility functions**: `vintage_to_float`, `float_to_vintage`, `excel_cell_to_index`, `overwrite_values`; added `format_vintage`
  - **Vintage-from-data iteration**: Main loop iterates `ula_df_total['vintage'].unique()` instead of hardcoded year/month ranges

### Fixed
- **kmx_mtns_ragu.ipynb**: Fixed `driver_flag` AttributeError caused by stale rra-to-ula merge pattern
  - ULA query now returns `job_company` directly; `driver_flag` is computed on `ula_df_total` (matching `bareboned_ragu_new.ipynb`) instead of merging from `rra_df_total`
  - Separate `driver_flag` computation retained on `rra_df_total` for the RRA recovery model (`coef_driver`)
  - Deduplication block updated: `driver_flag` aggregated and `job_company` dropped on both `ula_df_total` and `rra_df_total` independently
- **kmx_mtns_ragu.ipynb**: Fixed `open_tl_flag` using assignment (`=`) instead of comparison (`==`)
  - `ula_df_total['open_tl_flag'] = ula_df_total.open_tl = 0` overwrote the `open_tl` column to 0 and set the flag to 0 for all rows
  - Changed to `ula_df_total['open_tl_flag'] = ula_df_total.open_tl == 0` (matching `bareboned_ragu_new.ipynb`)
- **kmx_mtns_ragu.ipynb**: Fixed `kmx_toyho_flag` operator precedence bug
  - `cd_model_score>=130 & make.isin(...)` evaluated as `cd_model_score >= (130 & make.isin(...))` due to `&` binding tighter than `>=`
  - Added parentheses: `(cd_model_score >= 130) & make.isin(...)` (matching `bareboned_ragu_new.ipynb`)

### Changed
- **vintage_level_ula_query.txt / bareboned_ragu_new.ipynb**: Pre-aggregated employment table in SQL to eliminate row fan-out
  - Added `employment_agg` CTE that groups `sandbox.temp_employment_type_ragu` by `account_number`, producing `seasonal_flag` and `waiter_flag` columns via `MAX(CASE WHEN ...)`
  - Replaced direct `LEFT JOIN sandbox.temp_employment_type_ragu` with `LEFT JOIN employment_agg`, ensuring one row per account from the query
  - Removed Python-side employment dedup block (drop_duplicates, groupby employment_type_code, inner merge) that non-deterministically shifted LTV/APR/model_score weighted averages
  - Employment flags now read directly from SQL integer columns and converted to boolean in Python

### Changed
- **vintage_level_ula_query.txt**: Aligned LOB assignment with `weekly_query`
  - Changed from `CASE WHEN previous_riskdealergroup = '' THEN riskdealergroup ELSE previous_riskdealergroup END` to `dru.riskdealergroup`
  - Ensures accounts that have been reclassified to a different dealer group use their current LOB, matching weekly pipeline behavior
  - Resolves LTV and APR discrepancies observed in AN, FRN, STG, and FLD LOBs

### Changed
- **bareboned_ragu_new.ipynb**: Rewrote DLA merge to fix current-quarter coverage gap
  - Replaced swap-merge-swap pattern (mutating `book_vintage` on 800K+ rows twice) with a two-pass merge: explicit vintage match first, then `"current"` DLA as fallback for vintages newer than the last explicit vintage
  - Vintages beyond the last explicit DLA vintage (e.g., `2026 Q2`) now receive the `"current"` dealer-level adjustment instead of silently defaulting to neutral (1.0)
  - Old vintages without an explicit DLA row correctly default to neutral (1.0), preserving the principle that dealer risk is vintage-specific
  - Removed `DLA_CURRENT_QUARTER` config constant (no longer needed; the cutoff is derived from the DLA data itself)

### Changed
- **bareboned_ragu_new.ipynb**: Simplified `upload_ragu_historical` for first-run safety
  - Replaced temp-table demotion pattern (`CREATE TEMP TABLE _prev_current` / `DELETE` / re-`INSERT` / `DROP`) with a single `UPDATE ... SET current_version_flag = 0 WHERE current_version_flag = 1`
  - Removed `ALTER TABLE ADD COLUMN current_version_flag` try/except block (column is already in the `CREATE TABLE IF NOT EXISTS` definition)
  - Function now handles both fresh table creation and subsequent monthly appends with the same code path

### Changed
- **bareboned_ragu_new.ipynb**: Aligned model_score, LTV, and APR with weekly pipeline
  - Model score now derived from `vintage_level_ula_query.txt` (`cd_model_score`) instead of separate `postmodern_ms_query.txt`, ensuring all three metrics come from a single data source
  - MTN 4.1 model score transformation (`142 + (raw - 142) * 1.5`) applied directly to `ula_df_total.cd_model_score`
  - Added Python-side filters matching `weekly.ipynb`: `amt_financed <= 75000`, `pti <= 0.6`, `bbltv <= 4.0` (with MCY/null exemptions), `total_income <= 200000`
  - Recovery merge changed from INNER to LEFT join; model_score, LTV, and APR weighted averages now use the full population, while recovery uses only recovery-populated rows
  - `ms_df` computation moved from Cell 6 to end of Cell 7 (after filters and dedup)

### Changed
- **weekly.ipynb**: Changed `bbltv 2weighted` formula from `bbltv > 1` filter to `bbltv.notnull()`, including all bb-populated deals in the weighted LTV average instead of only those with LTV above 1.0
- **weekly_query**: Added `COALESCE(allbb.bb_value, cd.blackbook_history_adj_wholesale_amt)` for KMX bb_value, matching `vintage_level_ula_query.txt` logic so KMX deals without a rollup bb_value fall back to the LOS system value

### Added
- **bareboned_ragu_new.ipynb**: Comparison cell (Cell 11) for validating RAGU vs weekly pipeline
  - Runs `weekly_query` inline and applies identical filters and weighted-average logic as `weekly.ipynb`
  - Displays side-by-side comparison of model_score, bbltv, and apr per LOB and vintage with difference columns and MAE summary

### Added
- **ragu_individual.ipynb**: New account-level RAGU score notebook
  - Computes RAGU scores per account using each account's own `cd_model_score` instead of vintage-LOB weighted average from `ms_df`
  - Eliminates `postmodern_ms_query.txt` dependency entirely; all inputs come from `ula_df_total` and `new_recovery`
  - MTN 4.1 model score translation (`142 + (raw - 142) * 1.5`) applied directly to `ula_df_total.cd_model_score`
  - Fully vectorized computation (no vintage-by-vintage loop)
  - Output columns: `account_number`, `lob`, `vintage`, `model_score`, `gross_loss_impact`, `recovery_impact`, `ltv_impact`, `apr_impact`, `ragu_score`, `amt_financed`
  - Vintage-LOB aggregation via `weighted_average_and_sum` produces exact match to account-level weighted averages by construction
  - Includes POS and nonKMX rollup groups
  - Additive decomposition verification: `ragu_score = model_score + gross_loss + recovery + ltv + apr` at all levels
- **bareboned_ragu.ipynb**: POS and nonKMX rollup aggregation
  - New `ROLLUP_GROUPS` config dict defines POS (all 6 LOBs) and nonKMX (AN, FRN, STG, FLD, ENT)
  - Rollup computed via `weighted_average_and_sum` on individual LOB results, weighted by `amt_financed`
  - All RAGU decomposition components (Model Score, Gross Loss, Recovery, LTV, APR) remain additive at the rollup level
  - Rollup rows appended to `all_df` and included in Excel export, CSV output, and Redshift upload
- **bareboned_ragu.ipynb**: Historical RAGU monthend table (`sandbox.ragu_monthend`)
  - Appends current-table rows into historical table each run with `current_version_flag = 1`
  - Previous month's flag demoted to `0` via temp-table DELETE + re-INSERT (avoids slow Redshift UPDATE)
  - `CREATE TABLE IF NOT EXISTS` on first run; `ALTER TABLE ADD COLUMN` fallback for tables missing the flag column
  - `DELETE WHERE month_run = '{current}'` ensures idempotent re-runs within the same month
  - Controlled by independent `run_historical` toggle (separate from `run_sandbox`)
- **bareboned_ragu.ipynb**: Vintage filter on Redshift upload excludes current-month vintages (low contract counts produce unreliable scores)
- **bareboned_ragu.ipynb**: `month_run` format changed from `YYYY-MM` to `YYYY MNN` to match vintage format

### Changed
- **bareboned_ragu.ipynb**: Added MTN 4.1 model score translation before `ms_df` aggregation
  - Added KMX-specific `mtn_model` CASE expression to `postmodern_ms_query.txt` (matching `vintage_level_ula_query.txt` logic) so non-KMX LOBs are never tagged as MTN 4.1
  - Translation formula `142 + (raw - 142) * 1.5` applied in-place on `all_original_model_scores` before the `groupby` weighted average into `ms_df`
  - Gross loss adjustments (ULA multiplier logic) continue to use raw `cd_model_score` from `ula_df_total`, unaffected by this change
- **kmx_mtns_ragu.ipynb**: Added MTN 4.1 model score translation in `rebuild_ms_df`
  - MTN 4.1 scores are on a compressed scale relative to MTN 3.x; the formula `142 + (raw - 142) * 1.5` maps them to the normal scale
  - Translation is applied at the loan level inside `rebuild_ms_df` before the amount-financed weighted average, so the vintage-level `model_score` (and all downstream RAGU components) use the translated score
  - Gross loss adjustments (ULA multiplier logic) continue to use the raw `cd_model_score` for all threshold comparisons (state counter, TX/CA tiers, sub130/sub135/sub140 flags, etc.), preserving calibration
  - Affects both per-MTN-model runs and the "All KMX" combined run

### Added
- **kmx_mtns_ragu.ipynb**: New KMX-specific RAGU notebook that computes per-MTN-model scores
  - Loops through MTN models 3.0, 3.1, 3.2, and 4.1, computing RAGU scores for each model independently
  - Includes an "All KMX" combined run for verification against `ragu general cursor.ipynb`
  - Monthly granularity, August 2025+ vintages
  - Supports both pickle-based and SQL-based data loading
  - Per-model ms_df recomputation ensures accurate weighted-average model scores per subset
  - Full RAGU decomposition output (Contract MS, GLA, Recovery Adj, LTV Adj, RAGU Score) per model
  - Per-model and combined KMX diagnostics via `get_ula_multiplier_kmx_diag`
  - Excel export to `new_kmx_models.xlsx` with separate sheets per MTN model plus diagnostics
  - LTV adjustment computed in-notebook: `(1.59 / ltv - 1) / 0.10 * 1.7 / 0.65` with 159% baseline LTV
  - RAGU Score = ms_exclude_ltv + ltv_adjustment (previously LTV was computed only in Excel)

### Changed
- **bareboned_ragu.ipynb**: Added APR adjustment as a new RAGU score component
  - Weighted APR computed per vintage per LOB via `weighted_average_and_sum`
  - Baselines: 25% for AN, STG, FRN, KMX; 23.5% for FLD, ENT
  - Formula: `(baseline_apr - weighted_apr) / 0.01 * 0.7` (non-KMX) or `* 0.7 / 0.65` (KMX)
  - `apr_impact` added to RAGU score, Excel export (`METRIC_ROWS`), and CSV/display output
- **kmx_mtns_ragu.ipynb**: Switched granularity from weekly to monthly and start date from 2026 to August 2025
  - Vintage format changed from `YYYY-WW` (weekly) to `YYYY MNN` (monthly)
  - `start_year` set to 2025, vintage filter now `>= '2025 M08'`
  - Loop iterates months 1-12 per year instead of weeks 1-52
  - `max_week` replaced with `max_month` for current-year boundary

### Fixed
- **ragu general cursor.ipynb**: Aligned `get_ula_multiplier_kmx_diag` with production `get_ula_multiplier_kmx`
  - Commented out Fraud adjustment (step 12) which does not exist in production KMX; marked TBD for future decision
  - Aligned MTN 3.0 Soft pull formula (step 11) to match production parenthesization and removed extra `secured_credit_flag * 0.295` term
  - Added three Low MS decline rules (sub130, sub140, sub135) as steps 29a/29b/29c, matching production logic for MTN 3.0/3.1/3.2/4.1

### Removed
- **bareboned_ragu.ipynb**: Removed `rra_df_total` and `vintage_level_rra_query.txt` dependency entirely
  - RRA was only used as a passthrough to merge `new_recovery` multipliers onto ULA accounts; recovery is now merged directly from `new_recovery`
  - `driver_flag` (gig-economy employer regex) moved from RRA to ULA by adding `pb_primary_employer AS job_company` to `vintage_level_ula_query.txt`
  - `get_ragu_score` signature simplified: removed `rra_df_total` parameter, recovery merge is now `ula_df.merge(new_recovery, on='account_number', how='inner')`
  - Eliminated the `con_date` vs `book_date` mismatch that was the root cause of NaN dilution in recovery
  - RRA SQL query, period assignment, date filtering, Core LOB filter, pickle storage, and all print statements removed
  - Existing pickle filenames retained for backward compatibility (file names only, no RRA data stored)

### Fixed
- **bareboned_ragu.ipynb**: Fixed NaN dilution in recovery weighted average
  - `con_date` (used by `new_recovery`) and `book_date` (used by `rra_df_total`) differ for many accounts, causing unmatched accounts to carry NaN `recovery_multiplier` after the left merge
  - NaN values in the numerator of `weighted_average_and_sum` were skipped by `sum()`, but the denominator included all `amt_financed`, systematically deflating the weighted average recovery multiplier
  - Effect was most severe in boundary quarters (e.g., 2020Q1) where accounts near quarter edges had `con_date` in a different period than `book_date`
  - Fix: changed `dropna(subset='bbvalue')` to `dropna(subset=['bbvalue', 'recovery_multiplier'])` to exclude accounts without valid recovery data from both numerator and denominator

### Changed
- **ragu general cursor.ipynb**: Diagnostic cells now support weekly and monthly granularity
  - Added `DIAG_START_DATE` and `DIAG_END_DATE` configuration parameters (default start: 2025-09-01)
  - Replaced hardcoded quarterly vintage builder with granularity-aware builder using `pd.period_range` / `pd.date_range`
  - Vintage format matches the existing convention per granularity: `"YYYY QN"` (quarterly), `"YYYY MNN"` (monthly), `"YYYY-WW"` (weekly)
  - End date defaults to `max_quarter`/`max_month`/`max_week` when `DIAG_END_DATE` is `None`

### Fixed
- **ragu general cursor.ipynb**: Fixed `loss_multiplier` initialization in `get_ula_multiplier_nonkmx_diag` from `1` (int) to `1.0` (float), preventing `LossySetitemError` on pandas 2.x when float results are written back into the column

### Changed
- **bareboned_ragu.ipynb**: Restored original recovery calculation path to match `cursor_ragu.xlsx` output
  - Reintroduced `rra_df_total` as an intermediary in `get_ragu_score`: `rra_df` is filtered by vintage+LOB, left-merged with `new_recovery` on `account_number`, then inner-merged with `ula_df`.
  - Restored `recovery_unadjusted_multiplier` assignment from `rra_df['recovery_multiplier']` (index-aligned) to replicate the original notebook's behavior exactly.
  - `rra_df_total` restored to `get_ragu_score` function signature and call site.

### Changed
- **bareboned_ragu.ipynb**: Slimmed config cell and removed dead code
  - Moved inline-only constants out of Cell 0: `PRICING_CHANGE_DATE`, `STUDENT_LOANS_CUTOFF_DATE`, `THEFT_RISK_START_DATE`, `FRNI_PENALTY`, `FRNI_BENEFIT`, `LTV_IMPACT_MULTIPLIER`, `LTV_IMPACT_MULTIPLIER_KMX`, `EXCEL_OUTPUT`, `EXCEL_SHEET_MAP`
  - Stripped `BASELINES` to only `ltv` and `new_recovery_unadjusted` (removed `recovery_unadjusted`, `recovery_100_ltv`, `recovery`)
  - Deleted all dead RRA processing: `yob`, `impound_prob`, `car_make`, `car_class_only`, `fuel_type`, `car_lux`, `car_japanese`, `mileage`, `r_mmi`
  - Deleted dead `car_age_orig` and `car_year` fillna computation from `get_ragu_score`
  - Removed orphaned `expected_years_on_book`, `impound_probability`, `mmi_standard_increase` variable extractions
  - Removed unused `import copy`

- **bareboned_ragu.ipynb**: Stripped output metrics to additive RAGU decomposition
  - RAGU score now computed as `model_score + gross_loss_impact + recovery_impact + ltv_impact`
  - `gross_loss_impact` = `unit_loss_score - ms_original`
  - `recovery_impact` = `unit_loss_score * est_unit_loss * recovery_unadjusted_multiplier * (baselined_unadjusted_recovery - 1)`
  - `ltv_impact` = `((baseline_ltv / ltv) - 1) * multiplier`, where multiplier is 17 for non-KMX and 17/0.65 for KMX
  - Added `LTV_IMPACT_MULTIPLIER` and `LTV_IMPACT_MULTIPLIER_KMX` to centralized config
  - Removed `EXCEL_CELL_MAP`, `EXCEL_TEMPLATE`, and hardcoded cell positions
  - Removed intermediate columns: `ms_exclude_ltv`, `ms_100_ltv`, `baselined_recovery`, `baselined_100_ltv_recovery`, `recovery_100_ltv_multiplier`, `recovery_multiplier`, `ltv_realization_factor`, `only_recovery_ragu`
  - Excel export rewritten: all LOBs stacked vertically on one sheet per granularity, no template dependency
  - Output metrics: Model Score, Gross Loss Impact, Recovery Impact, LTV Impact, RAGU Score, Amount Financed
  - CSV and display updated to match slim column set

### Added
- **bareboned_ragu.ipynb**: New streamlined RAGU notebook built from scratch with the following improvements:
  - All configuration, assumptions, baselines, and inputs consolidated in a single top cell
  - Automatic period assignment using `pd.to_period('Q')`, `pd.to_period('M')`, `pd.to_period('W-SAT')` replacing manual string-based vintage construction
  - Auto-detection of max quarter/month/week from `END_DATE` (defaults to today), eliminating manual `max_quarter`/`max_month` variables
  - Configurable `START_DATE` and `END_DATE` that work across all granularities
  - Unified Excel export: single template and output file for quarterly, monthly, and weekly granularities
  - Individual LOB processing only (AN, FRN, STG, FLD, ENT, KMX) with no POS or non_kmxent rollups
  - Baselines defined per individual LOB instead of per group
  - Hardcoded date thresholds (pricing change, student loans cutoff, theft risk) moved to top-cell config
  - Batch concatenation for RAGU results (O(n) instead of O(n^2))
  - Removed: `auc_pred`, `float_to_vintage`, distribution query, t-1 table, waterfall exports, leave-one-out analysis, legacy ms_query path, yearly rollup logic, ULA diagnostics

### Changed
- **Model Score DataFrame (ms_df) Derivation**: Added `use_legacy_ms_query` flag (default: `False`) in `ragu general cursor.ipynb`.
  - When `False`, `ms_df` is derived from `ula_df_total` after it loads, eliminating the ~1 minute `postmodern_ms_query.txt` database query.
  - Uses the same BB-valued population as ULA calculations, ensuring consistency between model score baseline and adjustment calculations.
  - Legacy behavior preserved when flag is `True` for validation or rollback purposes.
  - **Performance optimization**: Replaced slow `groupby().apply()` with vectorized `.agg()` operations, reducing ms_df derivation from ~12 minutes to seconds.

### Added
- ULA Non-KMX Adjustment Diagnostics cell in `new_recovery_ragu.ipynb` (cell after the wrapper cell).
  - `get_ula_multiplier_nonkmx_diag`: Rewritten version of `get_ula_multiplier_nonkmx` that captures the simple mean of `loss_multiplier` after every adjustment step, with verbose print output showing flag means and multiplier means per step.
  - Analysis loop iterating over non-KMX LOBs (FRN, AN, STG, FLD, ENT) and quarterly vintages from 2023 Q3 onward.
  - Exports `ula_nonkmx_adjustment_diagnostics.xlsx` (Excel workbook, two sheets):
    - **Multiplier Steps**: Per-step simple-mean multipliers, final multiplier (mean), weighted multiplier from `get_ragu_score`, gross loss impact (`25 * (1 - weighted_multiplier)`), and record counts.
    - **Flag Means**: Simple mean of every flag used in the ULA adjustments, per LOB and vintage, with record counts. Employment flags (`seasonal_employment_count`, `waiter_employment_count`, `other_employment_count`) use raw counts instead of proportions for clarity.
  - Weighting by `amt_financed` is applied only to the final summary rows, not to intermediate adjustment steps.
  - Includes inline formula verification confirming `gross_loss_impact = 25 * (1 - weighted_loss_multiplier)`.

### Fixed
- **Step 10 (Student Loans)**: Corrected conditional from `leave_out != 'Student Loans'` to `leave_out == 'Student Loans'` in `get_ula_multiplier_nonkmx_diag`, matching the original `get_ula_multiplier_nonkmx` logic. The student-loan adjustment only fires when it is the factor being left out.
- **Step 12 (Chime / Secured Credit)**: Corrected conditional from `leave_out != 'Secured credit (Chime, etc.)'` to `leave_out == 'Secured credit (Chime, etc.)'` in `get_ula_multiplier_nonkmx_diag`, matching the original function logic.
- **FINAL_MULT (mean)**: Added `18_final` step recorded after the final `[0.7, 1.4]` clip so the reported mean accurately reflects the true final loss multiplier, not the pre-clip value.
- **Weighted multiplier population**: The weighted multiplier (`WTD_MULT_RAGU`) is now computed on the `bb_populated` population (inner join with `rra_df_total`, deduplicated by `account_number`, `bbvalue` not null), replicating the exact filtering in `get_ragu_score`. Previously it was computed on the full `processed_df`, which included records without `bbvalue`.
