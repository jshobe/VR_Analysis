function log_msg(fmt, varargin)
% LOG_MSG  Tiny timestamped logger.
t = datetime('now','Format','yyyy-MM-dd HH:mm:ss');
msg = sprintf(fmt, varargin{:});
fprintf('[%s] %s\n', char(t), msg);
end
