LINEAR FIGURE-ONLY DISPLAY UPDATE

Replace these two files in ComboSpeedPlot:
  1. plot_reward_centered_trial_speed.m
  2. plot_reward_centered_average_acceleration.m

Changes:
- The heatmap uses a local display copy of P.speedMat.
- Only short missing runs of up to 2 bins are linearly interpolated.
- Circular -180/180 boundary gaps are handled correctly.
- P.speedMat is not modified, so mean speed, SEM, lap-group curves,
  shared scales, and acceleration calculations remain unchanged.
- The acceleration legend is fixed at the lower-left ('southwest').

Optional settings may be added to get_single_reward_config.m:
  cfg.interpolateHeatmapForDisplay = true;
  cfg.heatmapDisplayMaxGapBins = 2;

No preprocessing needs to be repeated.
