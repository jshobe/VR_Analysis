%import raw encoder (enc) timestamps (TS) from NE 
RHDencTS=RHDencRAW;

% Select CSV file
[CSVfile, CSVdir] = uigetfile('*.csv', 'MultiSelect', 'on');
CSVfile = cellstr(CSVfile);

% Extract file number
%fileNumbers = cell2mat(cellfun(@(x) str2double(regexp(x, '\d*', 'Match')), CSVfiles, 'UniformOutput', false));

% Read and preprocess CSV data % Rename columns for clarity
CSVpath = fullfile(CSVdir, CSVfile{1});
CSVtableRAW = readtable(CSVpath, "Delimiter", ",", "TextType", "string");
CSVtable=CSVtableRAW;
CSVtable.Properties.VariableNames = {'TS', 'type', 'condition', 'pos_x', 'pos_y'};    

% Cleanup table: keep only loc enteries and eliminate NaNs
%CSVtableREW = CSVtable(CSVtable.type == 'reward',:); 
CSVtable = CSVtable(CSVtable.type == 'loc',:); 
CSVtable = CSVtable(find(~isnan(CSVtable.pos_x)), :);

    
% Extract enc timestamps (TS) 
%CSVencTS = CSVtable.TS;


%COMPARISON PLOTS Compare for trimming
%CSVdiff=diff(CSVtable.TS);RHDdiff=diff(Solenoid);
CSVdiff=diff(CSVtable.TS);RHDdiff=diff(RHDencTS);
figure; plot(CSVdiff); hold on; plot(RHDdiff); hold off; legend('CSV','RHD')


%%STEP1%%
%Manually trim beginning of RHDencTS to align beginning with CSV. Usually just deleting a few
%samples. Also check the end for very high values and delete

%Enter max delay%Manually find max delay and input below
del_max=67;

%%STEP#2 - only trims if CSVtable  is too long%%
%Remove tail on CVSenc and non-matching 
if height(CSVtable)>length(RHDencTS)
CSVtable=CSVtable(1:length(RHDencTS),:);
CSVtable=CSVtable(1:height(CSVtable)-del_max,:);
end


%COMPARISON PLOTS Compare again
CSVdiff=diff(CSVtable.TS);RHDdiff=diff(RHDencTS);
figure; plot(CSVdiff); hold on; plot(RHDdiff); hold off; legend('CSV','RHD');

%RHDencTS(207451:207502)=[];


%Determine bubble positions and length
i=0; thres=0.03; offset=30; window=335; %0; 0.03; 30; 335 DONT CHANGE
while length(CSVdiff)<length(RHDdiff)
i=i+1;
Cvec = CSVdiff-RHDdiff(1:length(CSVdiff));%plot(Cvec)
Cvec(Cvec<0)=0;
%Cvec = Cvec./CSVdiff;%only Use if want ratio
Lvec=find(Cvec>thres);
%Lvec=find(Cvec_ratio>thres);
vec1=CSVdiff(Lvec(1)+offset:Lvec(1)+window);
vec2=RHDdiff(Lvec(1)+offset:Lvec(1)+window);
%plot(vec1);hold on;plot(vec2);
delay=finddelay(vertcat(vec1,vec1),vertcat(vec2,vec2));
RHDdiff(Lvec(1):Lvec(1)+(delay-1))=[];%no change if 0 or neg
CSVdiff(Lvec(1)) = RHDdiff(Lvec(1));
%RHDdiff(Lvec(1)) = CSVdiff(Lvec(1));
MS{i}=Lvec(1);
ML{i}=delay(1);
end

MS=cell2mat(MS);ML=cell2mat(ML);
MS=MS(find(ML>0));
ML=ML(find(ML>0));  %set low threshold then just eliminate zeros




%If CSV is now longer it means that the table had non-matching (NM) 
%values at the end so remove them
NM=length(CSVdiff)-length(RHDdiff);
if NM>0
    CSVtable=CSVtable(1:(end-NM),:);
end

%Now the only difference between CSVenc and RHDenc 
%should be the same as the max delay determined earlier
del_check=length(RHDencTS)-height(CSVtable);


%Extract CSV enc PVs (convert to cm) and CSV timestamps so that
%we can insert nans
CSVnansPV = CSVtable.pos_y * 5.3;% Convert y position to cm
CSVnansTS=CSVtable.TS;

%insert nans at at bubble position values in CSV
val=0; shift=0;
for j=1:length(MS)
   
   
val = NaN([ML(j),5]); val=array2table(val);
val.Properties.VariableNames = {'TS', 'type', 'condition', 'pos_x', 'pos_y'};  

idx = MS(j)+shift-1;

CSVtable=(vertcat(CSVtable(1:idx-1,:) ,val, CSVtable(idx:end,:)));
% CSVnansTS=(vertcat(CSVnansTS(1:idx-1) ,val, CSVnansTS(idx:end)));
% CSVnansPV=(vertcat(CSVnansPV(1:idx-1) ,val, CSVnansPV(idx:end)));
InsStart{j}=idx;
shift=shift+ML(j); 
end



%now CSV timestamps and position values should match RHD timestamps
%COMPARISON PLOTS to check
CSVdiff=diff(CSVtable.TS);RHDdiff=diff(RHDencTS);
figure; plot(CSVdiff); hold on; plot(RHDdiff); hold off; legend('CSV','RHD')

%Final Trim optional
%CSVtable=CSVtable(1:247550,:);RHDencTS=RHDencTS(1:247550,:);



%Replace CSV timestamps with RHD timestamps in CSVtable and save
CSVtable.TS=RHDencTS;
CSVtable=renamevars(CSVtable,"TS","RHD_ts");
writetable(CSVtable, fullfile(CSVdir, 'CSVtableRHDts_Nans.csv'));





%replace nans in CSVnansPV with interpolated values
x = RHDencTS; y= CSVnansPV;
y(isnan(y)) = interp1(x(~isnan(y)),y(~isnan(y)),x(isnan(y)));
CSVinterpPV = y;




%Plot location of interp start insertion
plot(CSVinterpPV);
hold on
plot(cell2mat(InsStart),CSVinterpPV(cell2mat(InsStart)),'.r','MarkerSize',20)





plot(diff(CSVnansTS));hold on;plot(diff(RHDencTS));






