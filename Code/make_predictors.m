%% Create GLM Predictor Files from Scratch - Linear Object Ramps (0.25 to 1)

clearvars; close all;

%% Define spatial structure
bins_per_context = 133;
num_contexts = 4;
total_bins = bins_per_context * num_contexts;  % 532 bins

%% Create POS predictor (0 = first half, 1 = second half of each context)
POS = zeros(total_bins, 1);
for ctx = 1:num_contexts
    ctx_start = (ctx - 1) * bins_per_context + 1;
    second_half_start = ctx_start + 66;  % bin 67 onwards
    second_half_end = ctx_start + bins_per_context - 1;
    POS(second_half_start:second_half_end) = 1;
end

%% Create CNTX predictor for ODD blocks (0 for TT1/TT2, 1 for TT3/TT4)
CNTX_odd = [zeros(133,1); zeros(133,1); ones(133,1); ones(133,1)];

%% Create object predictors with LINEAR RAMP from 0.25 to 1
% Object positions (in bins):
% - Middle object: bins 32-66 (linear ramp from 0.25 to 1)
% - End object: bins 99-133 (linear ramp from 0.25 to 1)
% - Star (reward): bins 99-133 (same as end object)

bin_positions = (1:bins_per_context)';

% Create linear ramp from 0.25 to 1 over 35 bins
ramp_length = 35;
linear_ramp = linspace(0.25, 1, ramp_length)';

% Middle object (Chair or Drum depending on group)
OBJ_middle = zeros(bins_per_context, 1);
OBJ_middle(32:66) = linear_ramp;  % 35 bins: 66-32+1 = 35

% End object (Drum or Chair depending on group)
OBJ_end = zeros(bins_per_context, 1);
OBJ_end(99:133) = linear_ramp;  % 35 bins: 133-99+1 = 35

% Star (reward) - same position as end object
STAR_profile = zeros(bins_per_context, 1);
STAR_profile(99:133) = linear_ramp;

% Replicate across 4 contexts
OBJ_middle_full = repmat(OBJ_middle, num_contexts, 1);
OBJ_end_full = repmat(OBJ_end, num_contexts, 1);
STAR_full = repmat(STAR_profile, num_contexts, 1);

%% ===== GROUP 1: TT1=C_S, TT2=D_S =====
% Mice: VR29, 31, 33, 35, 37, 39, 41, 43, 46, 47

% ODD BLOCKS: Chair in middle, Drum at end
C_odd_g1 = OBJ_middle_full;
D_odd_g1 = OBJ_end_full;
NR_odd_g1 = C_odd_g1 + D_odd_g1;

predictor_tab_odd_g1 = table(POS, CNTX_odd, C_odd_g1, D_odd_g1, STAR_full, NR_odd_g1, ...
    'VariableNames', {'POS', 'CNTX', 'C', 'D', 'STAR', 'NONREWARDED'});

writetable(predictor_tab_odd_g1, 'Predictors_ODD_Group1.xlsx');
fprintf('Created: Predictors_ODD_Group1.xlsx (6 predictors)\n');

% EVEN BLOCKS: Drum in middle, Chair at end (SWAPPED, no CNTX)
D_even_g1 = OBJ_middle_full;
C_even_g1 = OBJ_end_full;
NR_even_g1 = C_even_g1 + D_even_g1;

predictor_tab_even_g1 = table(POS, C_even_g1, D_even_g1, STAR_full, NR_even_g1, ...
    'VariableNames', {'POS', 'C', 'D', 'STAR', 'NONREWARDED'});

writetable(predictor_tab_even_g1, 'Predictors_EVEN_Group1.xlsx');
fprintf('Created: Predictors_EVEN_Group1.xlsx (5 predictors, no CNTX)\n');

%% ===== GROUP 2: TT1=S_C, TT2=S_D =====
% All other mice (excluding VR27)

% ODD BLOCKS: Drum in middle, Chair at end
D_odd_g2 = OBJ_middle_full;
C_odd_g2 = OBJ_end_full;
NR_odd_g2 = C_odd_g2 + D_odd_g2;

predictor_tab_odd_g2 = table(POS, CNTX_odd, D_odd_g2, C_odd_g2, STAR_full, NR_odd_g2, ...
    'VariableNames', {'POS', 'CNTX', 'D', 'C', 'STAR', 'NONREWARDED'});

writetable(predictor_tab_odd_g2, 'Predictors_ODD_Group2.xlsx');
fprintf('Created: Predictors_ODD_Group2.xlsx (6 predictors)\n');

% EVEN BLOCKS: Chair in middle, Drum at end (SWAPPED, no CNTX)
C_even_g2 = OBJ_middle_full;
D_even_g2 = OBJ_end_full;
NR_even_g2 = C_even_g2 + D_even_g2;

predictor_tab_even_g2 = table(POS, C_even_g2, D_even_g2, STAR_full, NR_even_g2, ...
    'VariableNames', {'POS', 'C', 'D', 'STAR', 'NONREWARDED'});

writetable(predictor_tab_even_g2, 'Predictors_EVEN_Group2.xlsx');
fprintf('Created: Predictors_EVEN_Group2.xlsx (5 predictors, no CNTX)\n');

%% Verify ranges
fprintf('\n=== VERIFICATION ===\n');
fprintf('All predictors scaled 0-1:\n');
fprintf('  POS: min=%.2f, max=%.2f\n', min(POS), max(POS));
fprintf('  CNTX: min=%.2f, max=%.2f\n', min(CNTX_odd), max(CNTX_odd));
fprintf('  C (Group1 ODD): min=%.3f, max=%.3f\n', min(C_odd_g1), max(C_odd_g1));
fprintf('  D (Group1 ODD): min=%.3f, max=%.3f\n', min(D_odd_g1), max(D_odd_g1));
fprintf('  STAR: min=%.3f, max=%.3f\n', min(STAR_full), max(STAR_full));
fprintf('  NONREWARDED: min=%.3f, max=%.3f (should not exceed 1)\n', min(NR_odd_g1), max(NR_odd_g1));

%% Visualize
figure('Position', [100 100 1600 900]);

subplot(2,2,1);
plot(table2array(predictor_tab_odd_g1), 'LineWidth', 1.5);
legend(predictor_tab_odd_g1.Properties.VariableNames, 'Location', 'eastoutside');
xlabel('Spatial Bin (4cm)'); ylabel('Predictor Value');
title('Group 1 ODD (C\_S/D\_S): Novel Context - LINEAR RAMPS');
grid on; xline([133 266 399], 'r--', 'LineWidth', 2);

subplot(2,2,2);
plot(table2array(predictor_tab_even_g1), 'LineWidth', 1.5);
legend(predictor_tab_even_g1.Properties.VariableNames, 'Location', 'eastoutside');
xlabel('Spatial Bin (4cm)'); ylabel('Predictor Value');
title('Group 1 EVEN (C\_S/D\_S): Swapped - LINEAR RAMPS');
grid on; xline([133 266 399], 'r--', 'LineWidth', 2);

subplot(2,2,3);
plot(table2array(predictor_tab_odd_g2), 'LineWidth', 1.5);
legend(predictor_tab_odd_g2.Properties.VariableNames, 'Location', 'eastoutside');
xlabel('Spatial Bin (4cm)'); ylabel('Predictor Value');
title('Group 2 ODD (S\_C/S\_D): Novel Context - LINEAR RAMPS');
grid on; xline([133 266 399], 'r--', 'LineWidth', 2);

subplot(2,2,4);
plot(table2array(predictor_tab_even_g2), 'LineWidth', 1.5);
legend(predictor_tab_even_g2.Properties.VariableNames, 'Location', 'eastoutside');
xlabel('Spatial Bin (4cm)'); ylabel('Predictor Value');
title('Group 2 EVEN (S\_C/S\_D): Swapped - LINEAR RAMPS');
grid on; xline([133 266 399], 'r--', 'LineWidth', 2);

%% Summary
fprintf('\n=== SUMMARY ===\n');
fprintf('Created 4 predictor files with LINEAR RAMPS (0.25 to 1):\n\n');
fprintf('Group 1 (TT1=C_S, TT2=D_S): VR29, 31, 33, 35, 37, 39, 41, 43, 46, 47\n');
fprintf('Group 2 (TT1=S_C, TT2=S_D): All other mice (excluding VR27)\n\n');
fprintf('ODD blocks: 6 predictors (POS, CNTX, C, D, STAR, NONREWARDED)\n');
fprintf('EVEN blocks: 5 predictors (POS, C, D, STAR, NONREWARDED) - no CNTX\n\n');
fprintf('Object predictors use LINEAR RAMP from 0.25 to 1 over 35 bins\n');
fprintf('  - Middle object: bins 32-66\n');
fprintf('  - End object: bins 99-133\n');
fprintf('  - Star: bins 99-133\n');