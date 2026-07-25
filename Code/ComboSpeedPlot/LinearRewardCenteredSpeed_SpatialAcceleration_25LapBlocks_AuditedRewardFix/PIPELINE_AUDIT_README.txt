AUDITED REWARD-CENTERED SPEED PIPELINE
======================================

Purpose
-------
Restore the validated reward-onset speed-artifact correction that existed in
an earlier circular analysis and ensure it is applied before both displayed
speed and spatial acceleration.

Validated historical behavior
-----------------------------
At every reward onset, replace:
  1. the speed estimate at the onset sample
  2. the immediately following speed estimate
by linear interpolation.

Current implementation order
----------------------------
1. Read raw session data.
2. Convert position to wrapped and unwrapped centimeters.
3. Calculate 5-cm window-based speed.
4. Correct reward-onset sample plus the next sample.
5. Preserve corrected unthresholded speed for spatial acceleration.
6. Apply the optional low-speed threshold only to displayed/averaged speed.
7. Detect laps from position wrapping.
8. Bin speed in 3-cm position bins.
9. Derive spatial acceleration lap by lap using a local quadratic fit.
10. Average speed and acceleration in matching 25-lap blocks.

Intentional safety refinement relative to the old monolithic code
-----------------------------------------------------------------
The old implementation called interp1 over the entire speed vector, which
could fill unrelated interior NaN values. The new helper interpolates only
the reward-targeted indices. All unrelated NaNs are preserved.

Files changed or added
----------------------
CHANGED:
  LinearSingleRewardSpeed.m
    - Adds correction settings.
    - Calculates uncorrected window speed.
    - Applies correct_reward_speed_artifact before thresholding.
    - Uses corrected unthresholded speed for acceleration.
    - Runs invariant checks and prints a per-file audit line.

ADDED:
  correct_reward_speed_artifact.m
  test_reward_speed_artifact_correction.m
  run_reward_artifact_audit.m
  compute_window_speed.m (included so the audited version is explicit)
  PIPELINE_AUDIT_README.txt
  PACKAGE_MANIFEST_SHA256.txt

Unchanged analysis behavior
---------------------------
- Track and bin settings continue to come from get_single_reward_config.m.
- A maximum of the first 100 complete laps is used.
- Speed and acceleration are grouped into 25-lap blocks.
- Spatial acceleration uses a = v * dv/dx and a local quadratic fit.
- Reward-centered coordinates, omission-trial licks, old-reward lines, and
  shared session scales are unchanged.

Required checks before scientific use
-------------------------------------
1. In MATLAB, run:
     test_reward_speed_artifact_correction
2. Run:
     run_reward_artifact_audit
   and select the raw session(s) used for the figure.
3. Confirm:
   - NonTargetSamplesChanged = 0
   - AuditPassed = true
   - CompleteLaps matches the prior pipeline
   - the reward-adjacent speed spike is reduced without altering surrounding
     non-target samples
4. Then run LinearSingleRewardSpeed.m on the same files and inspect the
   reward-centered heatmap and acceleration scale.

Current limitation of this delivery audit
-----------------------------------------
The exact raw VR session that generated the most recent figure was not
available in the execution container, so the data-specific before/after
comparison could not be executed here. Deterministic algorithm tests and
static pipeline-order checks were performed; the included audit script is
for the required session-level verification in MATLAB.
