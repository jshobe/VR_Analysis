%% GLM Analysis for Justin's Data, WN edits 10/20/2025
dir='Z:\Justin\VR mice';
[unitdata_filename, unitdata_path] = uigetfile(dir,'Select a unitdata.mat file');
load(fullfile([unitdata_path unitdata_filename]));

predictor_tab=readtable('C:\Users\jshobe\Desktop\VR_Analysis\Code\Predictors.xlsx');
predictor_tab.INDEX=[];
predictors=table2array(predictor_tab);
predictors(:,1:2)=[];
% figure; plot(predictors); legend('CTX','Obj1','Ob2','Star');
% legend('Pos1','Pos2','CTX','Obj1','Ob2','Star');
GLMrez=[]; AllPvals=[];

% %% 2. CONTEXT
% % Use 0 and 1 for context (instead of 1 and 2), predictors need to be on the same scale. If you multiply values x 10, then beta coeffs go down by factor of 10
% context=[repmat(0,1,50) repmat(1,1,50) repmat(0,1,50) repmat(1,1,50) repmat(0,1,50) repmat(1,1,50)]; % 0 for context A, 1 for context B (in order of baseline A, baseline B, config 1A, config 1B, config 2A, config 2B)
% %%% note context needs to be from 0 to 1!!!


% Cntx, Obj1, Obj2, Star

% rmap_sm_JS = gaussian_smooth(rmap, 4);
% test_sm=smoothdata(rmap,'Gaussian',4); % double check if 2 means 2*4 = 8?

simdata=[zeros(133,1);zeros(133,1); ones(133,1); ones(133,1)];
pval=[];  % store for each cell

for c=1:size(unitdata,1) % for each cell (row)
   % rmap=[unitdata(c).Block1{1} unitdata(c).Block1{2} unitdata(c).Block1{3} unitdata(c).Block1{4}]; % one column vector for each unit for block 1 only
   rmap=[unitdata(c).Block3{1} unitdata(c).Block3{2} unitdata(c).Block3{3} unitdata(c).Block3{4}]; % one column vector for each unit for block 3 only

   figure; plot(rmap); xline([133:133:size(predictors,1)],'r-');
    
   % 1. GLMFIT original method: this is similar to multiple linear regression when using normal dist with identity link
    [all_b_coeffs, dev, stats] = glmfit(predictors, rmap,'normal','link','identity','constant','on'); % input design matrix, all ratemaps, constant on gives intercept
    unitdata(c).GLM.b_int=all_b_coeffs(1); % first val is beta intercept/constant (grand mean?) % coefficient of constant term
    unitdata(c).GLM.b_coeffs=all_b_coeffs(2:end) % beta coefficients for each predictor
    % positive beta coefs for context mean more firing for context B SNOWY (which is 1), negative coefficients mean more firing for context
    % A DESERT (which is 0)
    unitdata(c).GLM.pval=stats.p(2:end); % first pval is intercept (ignore) ***note that glmfit pvalue default gives two-tailed  pval!!!
    unitdata(c).GLM.dev=dev;
    unitdata(c).GLM.stats=stats;
    pval(c,:)=stats.p(2:end)
end



%%  old code wont work
% GLMrez=[]; AllPvals=[];
% %for reg=1:size(rmaps,1)  % each region
%     cells=GLM_rmap{reg}; % pull out the cells in each region
%     pval=[]; unitdata=[];
% 
%     for c=1:size(cells,2) % for each cell (col)
%         rmap=cells(:,c);
%         % 1. GLMFIT original method: this is similar to multiple linear regression when using normal dist with identity link
%         [all_b_coeffs, dev, stats] = glmfit(predictors, rmap,'normal','link','identity','constant','on'); % input design matrix, all ratemaps, constant on gives intercept
%         unitdata(c).b_int=all_b_coeffs(1); % first val is beta intercept/constant (grand mean?) % coefficient of constant term
%         unitdata(c).b_coeffs=all_b_coeffs(2:end); % beta coefficients for each predictor
%         % positive beta coefs for context mean more firing for context B SNOWY (which is 1), negative coefficients mean more firing for context
%         % A DESERT (which is 0)
%         unitdata(c).pval=stats.p(2:end); % first pval is intercept (ignore) ***note that glmfit pvalue default gives two-tailed  pval!!!
%         unitdata(c).dev=dev;
%         unitdata(c).stats=stats;
%         pval(c,:)=stats.p(2:end);
%     end
%     GLMrez{reg}=unitdata;
%     AllPvals{reg}=pval;
% % end


