
%====STEP1-import and format CSV table and NE timestamps
%trim CSV in excel to remove headers and anything after stop and save
%drag file to matlab and rename "tbl_raw" after import
clearvars; close all; 

[file, path] = uigetfile('*.csv','MultiSelect','on'); file = cellstr(file);

for q = 1: length(file)  %need 

VRpath = path;VRfile = file{q};

VRtableRAW= readtable(fullfile(VRpath,VRfile),"Delimiter",",","TextType","string"); tbl_cm=VRtableRAW;

tbl_cm.Properties.VariableNames([1]) = {'CSV_ts'}; tbl_cm.Properties.VariableNames([2]) = {'type'};        %label table columns
tbl_cm.Properties.VariableNames([4]) = {'pos_x'}; tbl_cm.Properties.VariableNames([5]) = {'pos_y'};
tbl_cm.Properties.VariableNames([3]) = {'condition'};

tbl_cm.pos_y = tbl_cm.pos_y*5.3; % convert to cm based on scale

tbl_loc = tbl_cm(tbl_cm.condition=='state',:); % extract used rows
                                                                                                       
%====STEP4-find trial specific interval timestamps during VR

tbl_loc = tbl_loc(tbl_loc.pos_x<9,:);    %remove blackout periods
tbl_locCSV_ts=tbl_loc.CSV_ts;
tbl_locpos_y=tbl_loc.pos_y;

trans = find(diff(tbl_loc.pos_y)<-300);                                     %indicies of large transitions
trans = vertcat(1,trans);
trans_end = tbl_loc.CSV_ts(trans);                                          %corresponding end timestamps
trans_beg = tbl_loc.CSV_ts(trans+1);                                        %corresponding beg timestamps

trans_end = trans_end(trans_end > min(trans_beg));                          %delete first value
trans_beg = trans_beg(trans_beg < max(trans_end));                          %delete last value

hallway = tbl_loc.pos_x(trans+1);                                           %extract hall identity or trial type trans+1?
hallway = hallway(1:length(trans_beg));                                     %trim



%use this CTX 
                             
start_stop=[93 174]; %define intervals for block analysis
%start_stop=[15 76];

for h = 1: size(start_stop(:,1))

trans_beg1 = trans_beg(start_stop(h,1):start_stop(h,2));
trans_end1 = trans_end(start_stop(h,1):start_stop(h,2));

interval_subset = [trans_beg1, trans_end1, hallway(start_stop(h,1):start_stop(h,2))];

int_trial = interval_subset(:,2) - interval_subset(:,1);                          %identify outliers for each trial (ie very long pause trials)
int_out = isoutlier(int_trial, 'mean');
int_out_trials = find(int_out==1);
interval_subset(int_out_trials,:)=[];

[speed] = VRspeedtest (interval_subset,tbl_loc.CSV_ts,tbl_loc.pos_y);

for j=1:7

scene.meanspeed.all{j} = (smooth(mean(speed((find(interval_subset(:,3)==j)),:))))';
scene.avetime.all{j} = 4./(smooth(mean(speed((find(interval_subset(:,3)==j)),:))))';

scene.meanspeed.early{j} = scene.meanspeed.all{1, j}(1,44:64);
scene.avetime.early{j} = scene.avetime.all{1, j}(1,44:64);
scene.deltaspeed.early{j} = scene.meanspeed.early{1,j}(end) - scene.meanspeed.early{1,j}(1,1);
scene.totaltime.early{j} = sum(scene.avetime.early{1,j});
scene.acceleration.early{j} = scene.deltaspeed.early{j} / scene.totaltime.early{j} ;


scene.meanspeed.late{j} = scene.meanspeed.all{1, j}(1,112:132);
scene.avetime.late{j} = scene.avetime.all{1, j}(1,112:132);
scene.deltaspeed.late{j} = scene.meanspeed.late{1,j}(end) - scene.meanspeed.late{1,j}(1,1);
scene.totaltime.late{j} = sum(scene.avetime.late{1,j});
scene.acceleration.late{j} = scene.deltaspeed.late{j} / scene.totaltime.late{j} ;

end

%SceneBlocks{h} = scene;

flatten = flattenStruct2Cell(scene.acceleration);
acceleration_mat{q,h} = vertcat(flatten{:});
meanspeed_mat{q,h} = vertcat(scene.meanspeed.all{:});
normspeed_mat{q,h} = meanspeed_mat{h}/max(max(meanspeed_mat{h}));

% CNT1 = []; SWAP = []; CNT2 = [];
% for v=1:q
%     CTX1 = [CTX1; normspeed_mat{v,1}]; SWAP = [SWAP; normspeed_mat{v,2}]; CTX2 = [CTX2; normspeed_mat{v,3}];
% end

% CNT1fam_CS=CTX1(1:7:size(CTX1,1),:)';CNT1fam_SD=CTX1(2:7:size(CTX1,1),:)';CNT1nov_CS=CTX1(3:7:size(CTX1,1),:)'; CNT1nov_CS=CTX1(4:7:size(CTX1,1),:)';



%%Figures%%
figure; tiledlayout(4,2, "TileSpacing","tight");

if h==2 %OBJECT SWAP

A='Familiar C-S';B='Familiar S-D';C='Familiar S-C(swap)';D='Familiar D-S(swap)'; %odd
%A='Familiar S-C';B='Familiar D-S';C='Familiar C-S(swap)';D='Familiar S-D(swap)'; %Even VR31-36
%A='Familiar D-S';B='Familiar S-C';C='Familiar S-D(swap)';D='Familiar C-S(swap)'; %Even VR27-30
    
    
nexttile; imagesc(speed((find(hallway(interval_subset(:,3))==1)),:)); title(A)
caxis([0 mean(nanmean(speed))*2]);colorbar;
xticks(0:20:120);x_labels={'0','80','160','240','320','400','480'};
xticklabels(x_labels);xlim([0 133]); xline([66 133],LineWidth=2,Color='w'); 

nexttile;imagesc(speed((find(hallway(interval_subset(:,3))==2)),:));title(B)
caxis([0 mean(nanmean(speed))*2]);colorbar;
xticks(0:20:120);x_labels={'0','80','160','240','320','400','480'};
xticklabels(x_labels);xlim([0 133]); xline([66 133],LineWidth=2,Color='w'); 

nexttile;imagesc(speed((find(hallway(interval_subset(:,3))==5)),:));title(C)
caxis([0 mean(nanmean(speed))*2]);colorbar;
xticks(0:20:120);x_labels={'0','80','160','240','320','400','480'};
xticklabels(x_labels);xlim([0 133]); xline([66 133],LineWidth=2,Color='w'); 

nexttile;imagesc(speed((find(hallway(interval_subset(:,3))==6)),:));title(D)
caxis([0 mean(nanmean(speed))*2]);colorbar;
xticks(0:20:120);x_labels={'0','80','160','240','320','400','480'};
xticklabels(x_labels);xlim([0 133]); xline([66 133],LineWidth=2,Color='w'); 

nexttile([2,2]);scene1256 = [scene.meanspeed.all{1, 1};scene.meanspeed.all{1, 2};scene.meanspeed.all{1, 5};scene.meanspeed.all{1, 6}]';
plot(scene1256,'LineWidth',2)
legend((A),(B),(C),(D), Location='southwest')
xticks(0:20:120);x_labels={'0','80','160','240','320','400','480'};
L = legend; L.AutoUpdate = 'off'; 
xticklabels(x_labels);xlim([0 133]); xline([66 133],LineWidth=1.5,Color='g')

else

A='Familiar C-S';B='Familiar S-D';C='Novel C-S';D='Novel S-D'; %odd
%A='Familiar S-C';B='Familiar D-S';C='Novel S-C';D='Novel D-S'; %Even VR31-36
%A='Familiar D-S';B='Familiar S-C';C='Novel D-S';D='Novel S-C'; %Even VR27-30
%A='Familiar C-S';B='Familiar S-D';C='Familiar C-D';D='Familliar S-S'; %Training
%A='Novel S-S';B='Novel C-D';C='Novel D-C(swap)';D='Familiar S-S';E='Familiar D-C(swap)'; F='Familiar C-D';    VR23&24
%A='Familiar S-S';B='Familiar C-D';C='Familiar D-C(swap)';D='Novel S-S';E='Novel D-C(swap)'; F='Novel C-D';    VR25&26

nexttile; imagesc(speed((find(hallway(interval_subset(:,3))==1)),:)); title(A)
caxis([0 mean(nanmean(speed))*2]);colorbar;
xticks(0:20:120);x_labels={'0','80','160','240','320','400','480'};
xticklabels(x_labels);xlim([0 133]); xline([66 133],LineWidth=2,Color='w'); 

nexttile;imagesc(speed((find(hallway(interval_subset(:,3))==2)),:));title(B)
caxis([0 mean(nanmean(speed))*2]);colorbar;
xticks(0:20:120);x_labels={'0','80','160','240','320','400','480'};
xticklabels(x_labels);xlim([0 133]); xline([66 133],LineWidth=2,Color='w'); 

nexttile;imagesc(speed((find(hallway(interval_subset(:,3))==3)),:));title(C)
caxis([0 mean(nanmean(speed))*2]);colorbar;
xticks(0:20:120);x_labels={'0','80','160','240','320','400','480'};
xticklabels(x_labels);xlim([0 133]); xline([66 133],LineWidth=2,Color='w'); 

nexttile;imagesc(speed((find(hallway(interval_subset(:,3))==4)),:));title(D)
caxis([0 mean(nanmean(speed))*2]);colorbar;
xticks(0:20:120);x_labels={'0','80','160','240','320','400','480'};
xticklabels(x_labels);xlim([0 133]); xline([66 133],LineWidth=2,Color='w'); 
        
nexttile([2,2]);scene1234 = [scene.meanspeed.all{1, 1};scene.meanspeed.all{1, 2};scene.meanspeed.all{1, 3};scene.meanspeed.all{1, 4}]';
plot(scene1234,'LineWidth',2)
legend((A),(B),(C),(D), Location='southwest')
xticks(0:20:120);x_labels={'0','80','160','240','320','400','480'};
L = legend; L.AutoUpdate = 'off'; 
xticklabels(x_labels);xlim([0 133]); xline([66 133],LineWidth=1.5,Color='g')

end

end

end










%maxspeed = max(meanspeed_mat,[],2);
%C = meanspeed_mat ./ reshape( maxspeed, [],1 );%max by row
% 
% 
% scene1_mean = (smooth(mean(speed((find(hallway==1)),:))))';
% scene2_mean = (smooth(mean(speed((find(hallway==2)),:))))';
% scene3_mean = (smooth(mean(speed((find(hallway==3)),:))))';
% scene4_mean = (smooth(mean(speed((find(hallway==4)),:))))';
% scene5_mean = (smooth(mean(speed((find(hallway==5)),:))))';
% scene6_mean = (smooth(mean(speed((find(hallway==6)),:))))';
% scene7_mean = (smooth(mean(speed((find(hallway==7)),:))))';
% 
% scene1_type = (speed((find(hallway==1)),:))';
% scene2_type = (speed((find(hallway==2)),:))';
% scene3_type = (speed((find(hallway==3)),:))';
% scene4_type = (speed((find(hallway==4)),:))';
% 
% N=5;
% scene1_Ntrialblock=reshape(mean(reshape(scene1_type(:,1:30)',N,[])),size(scene1_type(:,1:30),2)/N,[]).';
% scene2_Ntrialblock=reshape(mean(reshape(scene2_type(:,1:30)',N,[])),size(scene2_type(:,1:30),2)/N,[]).';
% scene3_Ntrialblock=reshape(mean(reshape(scene5_type(:,1:30)',N,[])),size(scene3_type(:,1:30),2)/N,[]).';
% scene4_Ntrialblock=reshape(mean(reshape(scene6_type(:,1:30)',N,[])),size(scene4_type(:,1:30),2)/N,[]).';
% 
% % odd mice use trial 1 and 3 early and trial 2 and 4 late
% 
% earlyposidx=56:66;
% scene1_early=(mean(scene1_Ntrialblock(earlyposidx,:),1)./max(scene1_Ntrialblock,[],1)).*100; %familiar
% scene3_early=(mean(scene3_Ntrialblock(earlyposidx,:),1)./max(scene3_Ntrialblock,[],1)).*100; %novel
% lateposidx=123:133;
% scene2_late=mean(scene2_Ntrialblock(lateposidx,:),1)./max(scene2_Ntrialblock,[],1).*100; %familiar
% scene4_late=mean(scene4_Ntrialblock(lateposidx,:),1)./max(scene4_Ntrialblock,[],1).*100; %novel



str2double(file{1,1})


out = regexp(file{1,1}, '\d+(?=\.log)', 'match', 'once')

str = 'Shot 12 Spectra data.mat';
Nr = sscanf(str, '%*s%d'

