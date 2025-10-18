% Make a unitdata struct
dir='Z:\Justin\VR mice'
[file,location] = uigetfile(dir,'*.csv')
unitdata=table2struct(readtable([location '\' file])); % load VR29_GoodUnitInfo

[ratemapfile,rmloc]=uigetfile(dir,'*.mat'); % load spatial_analysis_v2
load(fullfile(rmloc,ratemapfile));

if sum(cluster_id_good'==[unitdata.ClusterID])==size(unitdata,1) % check to make sure its in same order
    disp('Cluster id matches unitdata.ClusterID')
else
    disp('Wrong cluster id list!')
end

for c=1:size(unitdata,1)
    unitdata(c).trialtypes = arrayfun(@(tt) RateMeansByType(c, :, tt), 1:7, 'UniformOutput', false);
end

