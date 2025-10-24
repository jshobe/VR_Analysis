function [speed] = VRspeedtest (interval_subset,tbl_locCSV_ts,tbl_locpos_y)

for i = 1 : length(interval_subset) %get timestamps
    interval_subset_ts{i} = tbl_locCSV_ts(find((tbl_locCSV_ts>=interval_subset(i,1)) & (tbl_locCSV_ts<=interval_subset(i,2))));%NEW
end

for i = 1 : length(interval_subset)
    interval_subset_ps{i} = tbl_locpos_y(find((tbl_locCSV_ts>=interval_subset(i,1)) & (tbl_locCSV_ts<=interval_subset(i,2))));%NEW
end

for i = 1 : length(interval_subset) %corresponding postionstamps for each interval by trial
    [C,ia_subset{i},ib] = intersect(tbl_locCSV_ts,interval_subset_ts{i});  %NEW
    Interval_all_ps{i} = tbl_locpos_y(ia_subset{i});
end

for i = 1 : length(interval_subset(:,3)) %====resample trial by trial
    interval_subset_ts_RS{i} = interval_subset(i,1):1/300:interval_subset(i,2);
    interval_subset_ps_RS{i} = interp1(interval_subset_ts{i}, Interval_all_ps{i}, interval_subset_ts_RS{i});
end

Bin_4cm = 0:4:532;
Bin_4cm(1)=1;
trial_ps_MAT=[]; speed=[];
for i = 1: length(interval_subset_ps_RS)
    Bin_1cm = 1:length(interval_subset_ps_RS{i});  %1cm bins
    Idx = knnsearch(interval_subset_ps_RS{i}',Bin_1cm');
    Idx = Idx(Bin_4cm);
    trial_ps_MAT(i,:)=interval_subset_ps_RS{i}(Idx);
    trial_ts_MAT(i,:)=interval_subset_ts_RS{i}(Idx);
    speed(i,:) = diff(trial_ps_MAT(i,:))./diff(trial_ts_MAT(i,:)); 
end


end

