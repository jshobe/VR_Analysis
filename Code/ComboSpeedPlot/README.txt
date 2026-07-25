LINEAR REWARD-CENTERED FIGURE UPDATE

Changes
-------
1. First 100 complete laps are divided into three groups:
   - Laps 1-34
   - Laps 35-67
   - Laps 68-100

2. Speed and acceleration group curves use purple, blue, and green.
   No yellow group curve is used.

3. The acceleration legend is inside the southwest corner and is forced
   onto one horizontal row when supported by the installed MATLAB version.

4. Each session heatmap now uses its own color scale. The color maximum is
   calculated from that session using the existing percentile setting.
   Average-speed and acceleration y-axis scales remain shared across sessions.

5. Short-gap heatmap interpolation remains display-only. It does not alter
   P.speedMat, speed summaries, acceleration, or outlier filtering.

Installation
------------
Copy all .m files in this folder into ComboSpeedPlot and replace files with
matching names.

Do NOT replace get_single_reward_config.m. Keep your current configuration,
including:
   cfg.useSpeedThreshold = false;
   cfg.spatialAccelerationWindowBins = 9;

No preprocessing needs to be repeated. Run:

   test_lap_group_ranges
   test_acceleration_outlier_filter
   LinearSingleRewardSpeed

MATLAB was not available in the packaging environment, so the included tests
must be run locally.
