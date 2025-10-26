function opts = get_default_opts()
% Centralized defaults for the core pipeline
opts = struct();
opts.animalID   = "";
opts.sessionID  = "";
opts.regions    = ["CA1","mPFC"];  % adjust to your defaults
opts.overwrite  = false;
opts.nWorkers   = max(1, feature('numcores')-1);

% You can add more defaults here as you formalize options:
% opts.clock.align_method = "xcorr";
% opts.filter.spike_min_fr = 0.1;
end
