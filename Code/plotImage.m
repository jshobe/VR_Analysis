function plotImage(interval_subset, speed, index, titleStr)
    nexttile; imagesc(speed((find(interval_subset(:,3)==index)),:)); title(titleStr)
    caxis([0 mean(nanmean(speed))*2]);colorbar;
    xticks(0:20:120);x_labels={'0','80','160','240','320','400','480'};
    xticklabels(x_labels);xlim([0 133]); xline([66 133],'LineWidth',2,'Color','w'); 
end