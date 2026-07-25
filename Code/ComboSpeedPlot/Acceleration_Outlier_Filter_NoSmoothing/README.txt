ACCELERATION OUTLIER FILTER — NO SMOOTHING

Replace these files in ComboSpeedPlot:
  LinearSingleRewardSpeed.m
  compute_acceleration_lap_group_curves.m
  plot_reward_centered_average_acceleration.m

Add these files:
  filter_acceleration_outliers_by_position.m
  test_acceleration_outlier_filter.m

Run once:
  test_acceleration_outlier_filter

Then run:
  LinearSingleRewardSpeed

Method:
- Each 25-lap block is handled separately.
- Each position bin is handled separately.
- Values are compared across laps at the same position using median and MAD.
- Values farther than 5 robust SD from the median are set to NaN in a
  temporary summary matrix.
- P.accelMat is not modified.
- No interpolation or smoothing is introduced.
- A large acceleration feature shared across laps is retained.

Optional config settings in get_single_reward_config.m:
  cfg.removeAccelerationOutliers = true;
  cfg.accelerationOutlierThresholdRobustSD = 5;
  cfg.accelerationOutlierMinLaps = 8;
  cfg.smoothAccelerationBins = 1;

A larger threshold removes fewer values; a smaller threshold removes more.
