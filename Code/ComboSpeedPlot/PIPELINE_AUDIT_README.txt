PREPROCESSED + SHARED-HELPER REWARD-CENTERED PIPELINE
====================================================

Architecture
------------
The original TXT file is never edited or overwritten.

Raw TXT
  -> preprocess_single_reward_session.m
  -> ProcessedSessions/<raw_name>_processed.mat
  -> compute_session_window_speed.m
  -> LinearSingleRewardSpeed.m

The processed MAT file contains:
  Session.Samples
    Complete raw-aligned rows, including reward and lick events.
  Session.Kinematics
    The first row of each consecutive constant-position plateau.
  Session.Events
    Reward, lick, brake, and redundant event/logging rows.
  Session.Audit
    Source SHA-256, preprocessing version, row counts, and QC results.

Single active correction
------------------------
The prior reward-specific interpolation and the prior in-driver duplicate-row
correction are not used. The only active correction is canonical preprocessing:
  1. Preserve all original rows and event values.
  2. Identify the first row of every consecutive position plateau.
  3. Store those genuine position-update rows in Session.Kinematics.
  4. Compute speed only from Session.Kinematics.
  5. Map speed back to the corresponding original rows.
  6. Leave event-only/redundant rows as NaN for speed.

This prevents double correction and prevents event rows from changing the time
anchor of the 5 cm distance-window speed estimate.

Automatic cache behavior
------------------------
LinearSingleRewardSpeed.m calls load_or_preprocess_single_reward_session.m.
The processed MAT cache is rebuilt when:
  - it is missing;
  - its preprocessing version is old;
  - its source SHA-256 does not match the raw TXT;
  - track_cm changed;
  - positionPlateauTolerance_cm changed;
  - its stored audit failed; or
  - its row counts are inconsistent.

Files replaced
--------------
  LinearSingleRewardSpeed.m

New active files
----------------
  PreprocessSingleRewardSessions.m
  preprocess_single_reward_session.m
  build_preprocessed_single_reward_session.m
  load_or_preprocess_single_reward_session.m
  compute_session_window_speed.m
  get_file_fingerprint.m
  compute_file_sha256.m
  single_reward_preprocessor_version.m
  test_single_reward_preprocessing.m
  run_single_reward_preprocessing_audit.m

Matched analysis files retained unchanged
-----------------------------------------
  add_old_reward_location_line.m
  build_reward_centered_speed_matrix.m
  compute_acceleration_lap_group_curves.m
  compute_shared_reward_centered_scales.m
  compute_spatial_acceleration_from_speed_matrix.m
  compute_speed_lap_group_curves.m
  compute_window_speed.m
  plot_reward_centered_average_acceleration.m
  plot_reward_centered_average_speed.m
  plot_reward_centered_trial_speed.m

Superseded files: archive or remove from the active MATLAB folder
---------------------------------------------------------------
  compute_kinematic_window_speed.m
  correct_reward_speed_artifact.m
  test_compute_kinematic_window_speed.m
  run_kinematic_speed_audit.m
  test_reward_speed_artifact_correction.m
  run_reward_artifact_audit.m

The new driver does not call any of those files. Removing them avoids confusion
about which correction is active.

Required existing shared helpers not included
---------------------------------------------
  get_single_reward_config.m
  read_vr_session_txt.m
  parse_mouse_date.m
  detect_laps_from_wrap.m

First-run procedure
-------------------
1. Copy the full package into the analysis folder and replace duplicate files.
2. Archive/remove the superseded files listed above.
3. Run:
     test_single_reward_preprocessing
4. Run the raw-file audit:
     run_single_reward_preprocessing_audit
5. Run:
     LinearSingleRewardSpeed

Optional batch preprocessing
----------------------------
Run:
  PreprocessSingleRewardSessions

This is optional because the main driver automatically preprocesses missing or
stale files.

Configuration defaults added by the driver
------------------------------------------
  cfg.processedSessionSubfolder = 'ProcessedSessions';
  cfg.positionPlateauTolerance_cm = 1e-9;
  cfg.forcePreprocess = false;
  cfg.verifyProcessedSourceHash = true;

Existing analysis settings are unchanged:
  track length, bin size, 5 cm speed window, speed threshold, 25-lap blocks,
  spatial acceleration, plot smoothing, and shared axes.
