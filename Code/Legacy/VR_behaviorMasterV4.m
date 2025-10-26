
%====STEP1-import and format CSV table and NE timestamps
%trim CSV in excel to remove headers and anything after stop and save
%drag file to matlab and rename "tbl_raw" after import
clearvars; close all; 

[file, path] = uigetfile('*.csv','MultiSelect','on'); file = cellstr(file);
fileNameNum = cell2mat(cellfun(@(x) str2double(regexp(x,'\d*','Match')), file, 'UniformOutput', false)); %extract filename #s
isFNNEven = mod(fileNameNum, 2) == 0;                                                                      %are they even?

if any(fileNameNum>=28)
prompt = "enter 1 to plot swap block ";
swap_block = input(prompt);
end

for mouse = 1: length(file)  %need 

VRpath = path;VRfile = file{mouse};

VRtableRAW= readtable(fullfile(VRpath,VRfile),"Delimiter",",","TextType","string"); tbl_cm=VRtableRAW;

tbl_cm.Properties.VariableNames([1]) = {'CSV_ts'}; tbl_cm.Properties.VariableNames([2]) = {'type'};        %label table columns
tbl_cm.Properties.VariableNames([4]) = {'pos_x'}; tbl_cm.Properties.VariableNames([5]) = {'pos_y'};
tbl_cm.Properties.VariableNames([3]) = {'condition'};

tbl_cm.pos_y = tbl_cm.pos_y*5.3; % convert to cm based on scale

tbl_loc = tbl_cm(tbl_cm.condition=='state',:); % extract used rows
                                                                                                       
%====STEP4-find trial specific interval timestamps during VR

tbl_loc = tbl_loc(tbl_loc.pos_x<9,:);    %9 remove blackout periods 

tbl_locCSV_ts=tbl_loc.CSV_ts;
tbl_locpos_y=tbl_loc.pos_y;

trans = find(diff(tbl_loc.pos_y)<-300);                                     %indicies of large transitions
trans = vertcat(1,trans);
trans_end = tbl_loc.CSV_ts(trans);                                          %corresponding end timestamps
trans_beg = tbl_loc.CSV_ts(trans+1);                                        %corresponding beg timestamps

trans_end = trans_end(trans_end > min(trans_beg));                          %delete first value
trans_beg = trans_beg(trans_beg < max(trans_end));                          %delete last value

hallways = tbl_loc.pos_x(trans+1);                                           %extract hall identity or trial type trans+1?
hallways = hallways(1:length(trans_beg));                                     %trim

%use this CTX 
                             
%start_stop=[178 204;204 230;230 256;256 282;282 308]; 
%start_stop=[12 39;39 66;66 93;93 120;120 147;147 174];
%start_stop=[348 375;375 402;402 429;429 456];%define intervals for block analysis
%start_stop=[12 178; 178 234];
if any(fileNameNum<=21)
start_stop=[12 length(hallways)];
else
block1_end=178; block2_end=336;  %default
if length(hallways)<178
    block1_end=length(hallways);
end
start_stop=[12 block1_end];
if swap_block == 1
 start_stop=[12 block1_end; 178 block2_end];
 if length(hallways)<336
   start_stop=[12 block1_end; 178 length(hallways)];
 end
end
end

for block = 1: size(start_stop(:,1))

trans_beg1 = trans_beg(start_stop(block,1):start_stop(block,2));
trans_end1 = trans_end(start_stop(block,1):start_stop(block,2));

interval_subset = [trans_beg1, trans_end1, hallways(start_stop(block,1):start_stop(block,2))];

int_trial = interval_subset(:,2) - interval_subset(:,1);                          %identify outliers for each trial (ie very long pause trials)
int_out = isoutlier(int_trial, 'mean');
int_out_trials = find(int_out==1);
interval_subset(int_out_trials,:)=[];

[speed] = VRspeedtest (interval_subset,tbl_loc.CSV_ts,tbl_loc.pos_y);

for hall=1:length(unique(tbl_loc.pos_x))

scene.meanspeed.all{hall} = (smooth(mean(speed((find(interval_subset(:,3)==hall)),:))))';
scene.avetime.all{hall} = 4./(smooth(mean(speed((find(interval_subset(:,3)==hall)),:))))';

if length(scene.meanspeed.all{1, hall})<100 %needed this so code doesnt crash 
    scene.meanspeed.all{hall}=scene.meanspeed.all{hall-1};
    scene.avetime.all{hall}=scene.avetime.all{hall-1};
 
else
end   
scene.meanspeed.early{hall} = scene.meanspeed.all{1, hall}(1,44:64);
scene.avetime.early{hall} = scene.avetime.all{1, hall}(1,44:64);
scene.meanspeed.late{hall} = scene.meanspeed.all{1, hall}(1,112:132);
scene.avetime.late{hall} = scene.avetime.all{1, hall}(1,112:132);
scene.deltaspeed.early{hall} = scene.meanspeed.early{1,hall}(end) - scene.meanspeed.early{1,hall}(1,1);
scene.totaltime.early{hall} = sum(scene.avetime.early{1,hall});
scene.acceleration.early{hall} = scene.deltaspeed.early{hall} / scene.totaltime.early{hall} ;
scene.deltaspeed.late{hall} = scene.meanspeed.late{1,hall}(end) - scene.meanspeed.late{1,hall}(1,1);
scene.totaltime.late{hall} = sum(scene.avetime.late{1,hall});
scene.acceleration.late{hall} = scene.deltaspeed.late{hall} / scene.totaltime.late{hall} ;

end

%SceneBlocks{h} = scene;

flatten = flattenStruct2Cell(scene.acceleration);
AccelerationBlock_by_Mouse{block,mouse} = vertcat(flatten{:});

%acceleration_mat{q,h}(isnan(cell2mat(acceleration_mat{q,h})))=[];        % identify index of NaN values and remove them from the array
Meanspeed_by_Mouse{block,mouse} = vertcat(scene.meanspeed.all{:});
Normspeed_by_Mouse{block,mouse} = Meanspeed_by_Mouse{block,mouse}/max(max(Meanspeed_by_Mouse{block,mouse}));
AveMeanspeed_by_Mouse_early{block,mouse} = mean(vertcat(scene.meanspeed.early{:}),2);
AveMeanspeed_by_Mouse_late{block,mouse} = mean(vertcat(scene.meanspeed.late{:}),2);
NormFactor_by_mouse{block,mouse}=max(max(Meanspeed_by_Mouse{block,mouse}));

figure('Position',[((mouse-1)*500),0,500,700]); 
% Change tiledlayout to have 6 rows
t = tiledlayout(6,2, "TileSpacing","tight");

title(t,regexprep(file{1,mouse}, '_', '\\_'))

%mice:'early even'   'recent even'        'odd;
A={'Fam D-S' , 'Fam S-C', 'Fam C-S'};
B={'Fam S-C' , 'Fam D-S', 'Fam S-D'};
E='FamO-NovO'; F='FamS-NovS'; G='FamO-SwapO'; H='S-S';


if mod(block, 2) == 0
    C= {'Swap S-D','Swap C-S','Swap S-C'};
    D= {'Swap C-S','Swap S-D','Swap D-S'};
    plot_param = [5, 6];
else
    C={'Nov D-S' , 'Nov S-C', 'Nov C-S'};
    D={'Nov S-C' , 'Nov D-S', 'Nov S-D'};
    plot_param = [3, 4];
end


if isFNNEven(1,mouse) && fileNameNum(mouse)<=30 %
    A1 = A{1,1}; B1 = B{1,1}; C1 = C{1,1}; D1 = D{1,1}; 
elseif  isFNNEven(1,mouse) == 1 %File name is even
    A1 = A{1,2}; B1 = B{1,2}; C1 = C{1,2}; D1 = D{1,2}; 
elseif isFNNEven(1,mouse) == 0 %file is odd
    A1 = A{1,3}; B1 = B{1,3}; C1 = C{1,3}; D1 = D{1,3}; 
end

plotImage(interval_subset, speed, 1, A1);
plotImage(interval_subset, speed, 2, B1);
plotImage(interval_subset, speed, plot_param(1), C1);
plotImage(interval_subset, speed, plot_param(2), D1);

% Adjust h1 to occupy 2 rows
h1 = nexttile([2,2]);
scene_data = [scene.meanspeed.all{1, 1}; scene.meanspeed.all{1, 2}; scene.meanspeed.all{1, plot_param(1)}; scene.meanspeed.all{1, plot_param(2)}]';
plot(scene_data, 'LineWidth',2)
if ismember(7, hallways)
scene_data1 = [scene.meanspeed.all{1, 7}]';
hold on
plot(scene_data1,'--','LineWidth',1)
end
legend((A1),(B1),(C1),(D1),'Location','southwest','NumColumns',2)
xticks(0:20:120);
x_labels={'0','80','160','240','320','400','480'};
L = legend; L.AutoUpdate = 'off'; fontsize(L,scale=0.8);
xticklabels(x_labels);
xlim([0 133]);
xline([66 133],'LineWidth',1.5,'Color','g')

% Adjust h2 to also to occupy 2 rows
h2 = nexttile([2,2]);
SceneC=scene.meanspeed.all{1,plot_param(1)}; SceneA=scene.meanspeed.all{1,1};
SceneD=scene.meanspeed.all{1,plot_param(2)}; SceneB=scene.meanspeed.all{1,2};
FamNovAC=SceneA-SceneC;FamNovBD=SceneB-SceneD;FamNovAD=SceneA-SceneD;FamNovBC=SceneB-SceneC;

FamNov_begO1 = FamNovAC(1:66)'; FamNov_endO2 = FamNovBD(67:132)'; %default for block1 'odd' and 'early even'
FamNov_begS1 = FamNovBD(1:66)'; FamNov_endS2 = FamNovAC(67:132)';

if isFNNEven(1,mouse) == 1 && fileNameNum(mouse)>30                     % block1 change if 'recent even'
    FamNov_begS1 = FamNovAC(1:66)'; FamNov_endS2 = FamNovBD(67:132)';
    FamNov_begO1 = FamNovBD(1:66)'; FamNov_endO2 = FamNovAC(67:132)';
end

%%%%% h=2
if mod(block, 2) == 0                                                     %if block is even it's a SWAP condition
    FamNov_begS1 = FamNovBC(1:66)'; FamNov_endS2 = FamNovAD(67:132)'; %default for SWAP 'odd' and 'early even'
    FamNov_begO1 = FamNovAD(1:66)'; FamNov_endO2 = FamNovBC(67:132)';

if isFNNEven(1,mouse) == 1 && fileNameNum(mouse)>30                     % SWAP change if 'recent even'
    FamNov_begS1 = FamNovAD(1:66)'; FamNov_endS2 = FamNovBC(67:132)';
    FamNov_begO1 = FamNovBC(1:66)'; FamNov_endO2 = FamNovAD(67:132)';
end
end

FamNov.FamNov_O1_beg{mouse}=FamNov_begO1; FamNov.FamNov_S1_beg{mouse}=FamNov_begS1; %saving in struct
FamNov.FamNov_O2_end{mouse}=FamNov_endO2; FamNov.FamNov_S2_end{mouse}=FamNov_endS2;

%[FamNov_O1_beg;FamNov_O2_end]


plot([FamNov_begO1;NaN;FamNov_endO2],'LineWidth',2)
hold on
plot([FamNov_begS1;NaN;FamNov_endS2],'LineWidth',2)



% if isFNNEven(1,mouse) && fileNameNum(mouse)<=30 %
%     DeltaXS_first=(NovFamP1(1:66)-NovFAM1(1:66))-((NovFamP2(1:66)-NovFAM2(1:66)));
%     DeltaXS_second=(NovFAM1(67:132)-NovFamP1(67:132))-((NovFAM2(67:132)-NovFamP2(67:132)));
%     plot ([DeltaXS_first,DeltaXS_second],'.','LineWidth',2)
% elseif  isFNNEven(1,mouse) == 1 %File name is even
%     DeltaXS_first=(NovFAM1(1:66)-NovFamP1(1:66))-((NovFAM2(1:66)-NovFamP2(1:66)));
%     DeltaXS_second=(NovFamP1(67:132)-NovFAM1(67:132))-((NovFamP2(67:132)-NovFAM2(67:132)));
%     plot ([DeltaXS_first,DeltaXS_second],'.','LineWidth',2)  
% elseif isFNNEven(1,mouse) == 0 %file is odd
%     DeltaXS_first=(NovFamP1(1:66)-NovFAM1(1:66))-((NovFamP2(1:66)-NovFAM2(1:66)));
%     DeltaXS_second=(NovFAM1(67:132)-NovFamP1(67:132))-((NovFAM2(67:132)-NovFamP2(67:132)));
%     plot ([DeltaXS_first,DeltaXS_second],'.','LineWidth',2)                            
% end
legend((E),(F),'Location','southwest')
if mod(block, 2) == 0           
legend((G),(H),'Location','southwest')
end
xticks(0:20:120);
x_labels={'0','80','160','240','320','400','480'};
L = legend; L.AutoUpdate = 'off'; fontsize(L,scale=0.8);
xticklabels(x_labels);
xlim([0 133]);
xline([66 133],'LineWidth',1.5,'Color','g')
yline(0,'--','LineWidth',1.5,'Color','b')

% Link y-axes of last two plots
%linkaxes([h1, h2],'y')

end

end

flatten = flattenStruct2Cell(FamNov);
FamNov_by_Mouse = vertcat(flatten{:});



Meanspeed_by_Mouse{1,1}(44:66)









