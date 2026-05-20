% TreadmillMaze_RecordingDay_SnowyV2_Even_RB_1SEC
%
% High-level overview
% -------------------
% This class controls a NI-DAQ–based virtual reality hallway task:
%
%  * Reads a rotary encoder on a treadmill (NI counter input).
%  * Integrates counts -> position along a linear hallway.
%  * Sends the camera position and rotation to a Unity/VR scene over UDP.
%  * Switches between pre-defined Unity scenes according to a text trial order.
%  * Has two possible reward “zones” per scene (positions read from a text file).
%  * Delivers rewards via NI:
%       - Digital line (Port0/Line1) for the water valve.
%       - Analog pulse (ao0) for a 5 V reward pulse.
%  * Detects licks from a capacitive lick sensor (AI channel 7) and logs them.
%  * Provides a GUI to edit parameters (gain, reward locations, hallway Xpos, etc.).
%  * Uses a 1-second blackout (blank screen) after teleport to the start.
%
% Dependencies (other .m files in your toolbox)
% ---------------------------------------------
%  * Scheduler   - manages periodic callbacks using MATLAB timers.
%  * UDPSender   - sends UDP packets to VR machines.
%  * Files       - opens log file, creating folder if needed.
%  * CSV         - used in export() to convert CSV logs to MAT.
%  * Tools       - Tools.compose builds multi-monitor UDP strings,
%                  Tools.tone can play a reward beep.
%  * NITreadmill / PretendTreadmill - treadmill abstraction; here mostly for
%                  compatibility (we read NI directly in onUpdate).
%  * readn       - parses space-separated numbers from GUI edit boxes.
%  * Callbacks   - used by Scheduler (indirectly) for safe timer callbacks.
%
% Important: Node-based maze logic (the "Nodes" class and related callbacks)
% -------------------------------------------------------------------------
% The original toolbox had a more complex graph-based maze controller using
% a Nodes object (vertices, laps, nodes, etc.). This SnowyV2 hallway task
% does *not* use that path. All Nodes-related code here has been either
% commented out or turned into no-op stubs, so this class now depends only
% on NI-DAQ, UDP, and the small helper classes above.

classdef TreadmillMaze_RecordingDay_SnowyV2_Even_RB_1SEC < handle

    %% Public configuration properties (used by the task)
    properties
        % Allow behavior during intertrial (legacy; not used in current hallway logic).
        intertrialBehavior   = false;
        intertrialDuration   = 1;     % s, used by legacy newTrial

        % Logging configuration for legacy treadmill/Nodes callbacks.
        logOnChange          = true;
        logOnFrame           = true;
        logOnUpdate          = true;

        % Reward settings (used mainly by legacy treadmill path; hallway task uses var.reward_duration).
        rewardDuration       = 0.050; % s (legacy)
        rewardTone           = [2000 0.5]; % [frequency, duration] used only in legacy newTrial.

        % Whether tape sensor should trigger trials (legacy path).
        tapeTrigger          = false;
    end

    %% Public read-only properties that describe the setup
    properties (SetAccess = private)
        % com - Serial port name (used only if you connect to Arduino / bridge; NI hallway does not require it).
        com

        % filename - Log file location (CSV) under Documents/VR.
        filename

        % monitors - List of monitor IP addresses and yaw offsets:
        %   {'IP1', yawOffset1, 'IP2', yawOffset2, ...}
        % These become "addresses" and "offsets" internally.
        monitors = { ...
            '192.168.0.100', 0, ...    % control system / monitor
            '192.168.0.198', 0, ...    % center tablet
            '192.168.0.147', -90, ...  % left tablet
            '192.168.0.117', 90, ...   % right tablet
            '192.168.0.112', 0};       % (optional) bottom tablet

        % vertices / resetNode - LEGACY: only used in Nodes-based maze (not in this hallway task).
        % They remain defined for compatibility, but are not used.
        vertices = [0, -100, ...
                    0,    0, ...
                    0, 1000, ...
                    0, -Inf];
        resetNode = 2;
    end

    %% Dependent properties (set/get wrappers)
    properties (Dependent)
        % gain - Forward speed factor in closed-loop when speed is 0 (legacy treadmill path).
        gain

        % speed - Forward speed in open-loop (legacy treadmill path).
        speed
    end

    %% Internal state and helper objects
    properties (Access = private)
        % Network layer: addresses and yaw offsets extracted from "monitors"
        addresses
        offsets

        % Scheduler used to call onUpdate at fps Hz and to schedule blank/pause.
        scheduler

        % UDP sender used to send 'scene', 'position', 'rotation', etc. to Unity.
        sender

        % Log file handle and session timing
        fid
        startTime
        className

        % GUI figure and controls
        figureHandle
        textBox
        reward_probability
        reward_duration
        start_location_beg
        start_location_end
        reward_location
        stop_location
        speed_gain
        hallway_Xpos
        hallway_prob
        teltxt

        % Maze/task variables loaded/saved via maze.mat and GUI
        var
        state
        camera_offset
        current_hallway
        number_of_teleports
        number_of_nonrewards
        max_number_of_nonrewards

        % NI DAQ devices & sessions
        device
        daqsession        % counter input (encoder)
        daqout            % analog output for reward pulse
        daqoutdig         % digital output for position clock
        daqin             % analog input for lick signal
        ch1
        aout
        ain
        dout
        rwdout            % digital output for valve trigger
        intan             % (legacy) digital session for Intan; not used directly here
        intantrg
        positionUpdate
        positionUpdateSig

        % Treadmill abstraction (PretendTreadmill or NITreadmill)
        treadmill

        % State used by hallway movement logic
        enabled = false
        trial   = 1
        mGain   = 1
        mSpeed  = 0
        movement_gain = 10    % not used in hallway

        position_data_previous = 0
        position_data_start
        xr   % for position clock pulse
        rwdxr % for reward digital pulses
        waitflag = 0
        wait_start_time = 0

        % blackoutTime - length of blank screen after teleport (seconds)
        blackoutTime = 1       % you explicitly wanted 1 sec
        blankTimer
        blankId = 0
        pauseId = 0

        % Tape control (legacy)
        tapeControl = [0 1]

        % Legacy Nodes object (not used in this hallway task)
        nodes

        % Scene management
        scene
        scene_table
        scene_idx
        scene_pointer
        reward_locations_arr   % matrix [sceneId, rwdPos1, rwdPos2]
        reward_locations       % row for current scene
        reward1_active
        reward2_active

        % Text to store the latest "update" string that was logged
        update = ''
    end

    %% Constants
    properties (Constant)
        % fps - desired control loop frequency (Scheduler calls onUpdate at this rate)
        fps = 50;

        % programVersion - version tag for this controller
        programVersion = '20180517';

        % Encoder config
        counterNBits    = 32;
        signedThreshold = 2^(32-1);
        encoderCPR      = 1024;
    end

    %% Constructor / setup
    methods
        function obj = TreadmillMaze_RecordingDay_SnowyV2_Even_RB_1SEC(com)
            % Constructor: initializes NI hardware, UDP, log file, GUI,
            % scheduler, and (optionally) treadmill abstraction.
            %
            % The actual closed-loop treadmill->VR control is done via NI
            % directly in onUpdate, not through the treadmill object.

            if nargin == 0
                com = [];
            end
            obj.com = com;

            % -----------------------------
            % NI-DAQ: rotary encoder (counter input)
            % -----------------------------
            obj.device    = daq.getDevices;
            obj.daqsession = daq.createSession('ni');
            obj.ch1        = addCounterInputChannel(obj.daqsession, obj.device.ID, 0, 'Position');
            obj.ch1.EncoderType = 'X1';

            % -----------------------------
            % NI-DAQ: analog output for reward pulse (ao0)
            % -----------------------------
            obj.daqout     = daq.createSession('ni');
            obj.aout       = addAnalogOutputChannel(obj.daqout, obj.device.ID, 'ao0', 'Voltage');
            obj.daqout.Rate = 1000;   % 1 kHz reward pulse

            % -----------------------------
            % NI-DAQ: lick detection (AI7, capacitive sensor)
            % -----------------------------
            obj.daqin = daq.createSession('ni');
            obj.ain   = addAnalogInputChannel(obj.daqin, obj.device.ID, 7, 'Voltage');
            obj.ain.InputType = 'SingleEnded';
            obj.daqin.IsContinuous = true;
            obj.daqin.Rate = 1000;
            obj.daqin.NotifyWhenDataAvailableExceeds = 25;
            obj.daqin.addlistener('DataAvailable', @(src,evnt)obj.getD(src,evnt,obj));

            % -----------------------------
            % NI-DAQ: digital output clock for position (Port0/Line0)
            % -----------------------------
            obj.daqoutdig = daq.createSession('ni');
            addDigitalChannel(obj.daqoutdig, obj.device(1).ID, 'Port0/Line0', 'OutputOnly');
            obj.daqoutdig.Rate = 1000;
            outputSingleScan(obj.daqoutdig, 0);
            obj.xr = 0;

            % -----------------------------
            % NI-DAQ: digital reward valve line (Port0/Line1)
            % -----------------------------
            obj.rwdout = daq.createSession('ni');
            addDigitalChannel(obj.rwdout, obj.device(1).ID, 'Port0/Line1', 'OutputOnly');
            obj.rwdout.Rate = 1000;
            outputSingleScan(obj.rwdout, 0);
            obj.rwdxr = 0;

            % -----------------------------
            % Logging: CSV file under Documents/VR
            % -----------------------------
            addpath Tools;
            folder    = fullfile(getenv('USERPROFILE'), 'Documents', 'VR');
            session   = sprintf('VR%s', datestr(now, 'yyyymmddHHMMSS'));
            obj.filename = fullfile(folder, sprintf('%s.csv', session));
            obj.fid      = Files.open(obj.filename, 'a');

            % Basic session info
            obj.startTime = tic;
            obj.className = mfilename('class');
            obj.print('maze-version,%s-%s', obj.className, TreadmillMaze.programVersion);
            % Nodes.version is not printed because Nodes-based path is unused
            obj.print('treadmill-version,%s', ArduinoTreadmill.programVersion);
            obj.print('filename,%s', obj.filename);

            % -----------------------------
            % UDP to VR (Unity) via UDPSender
            % -----------------------------
            obj.addresses = obj.monitors(1:2:end);
            obj.offsets   = [obj.monitors{2:2:end}];
            obj.sender    = UDPSender(32000);

            % Show blank initially on all VR screens
            obj.sender.send('enable,Blank,1;', obj.addresses);

            % -----------------------------
            % Treadmill abstraction
            % -----------------------------
            if isempty(com)
                % Simulation / no external treadmill bridge
                obj.treadmill = PretendTreadmill();
                obj.print('treadmill-version,%s', PretendTreadmill.programVersion);
            else
                % NI/Arduino bridge path (not used for encoder, but kept for compatibility)
                obj.treadmill = NITreadmill(obj.com);
                obj.treadmill.bridge.register('ConnectionChanged', @obj.onBridge);
            end

            % In this task, we do NOT register treadmill 'Frame', 'Step', or 'Tape' events
            % because movement is handled via NI directly in onUpdate and the
            % Node-based path is disabled.
            if 0
                obj.treadmill.register('Frame', @obj.onFrame);
                obj.treadmill.register('Step',  @obj.onStep);
                obj.treadmill.register('Tape',  @obj.onTape);
            end

            % -----------------------------
            % Scheduler: calls onUpdate at fps Hz
            % -----------------------------
            obj.scheduler = Scheduler();
            obj.scheduler.repeat(@obj.onUpdate, 1 / obj.fps);

            % -----------------------------
            % Load or initialize maze parameters (saved in maze.mat)
            % -----------------------------
            if exist('maze.mat','file')
                load('maze.mat','-mat');   % loads struct var
            else
                var.state_probability   = 50;
                var.reward_probability  = [100 100 100 100]';
                var.speed_gain          = 5;
                var.reward_duration     = 75;     % interpreted as #samples at 1 kHz (75 ms)
                var.start_location_beg  = 10;
                var.start_location_end  = 20;
                var.reward_location     = [100 50 50 100]'; % [sceneId rwd1 rwd2] (legacy)
                var.stop_location       = 90;
                var.hallway_Xpos        = [0 20 40 60]';
                var.hallway_prob        = [25 25 25 25]';
            end
            obj.var                = var;
            obj.state              = 0;
            obj.position_data_start = var.start_location_beg;
            obj.current_hallway    = 1;
            obj.camera_offset      = 0;
            obj.number_of_teleports   = 0;
            obj.max_number_of_nonrewards = 2;
            obj.number_of_nonrewards    = 0;

            % -----------------------------
            % GUI controls
            % -----------------------------
            obj.figureHandle = figure('Name', mfilename('Class'), ...
                                      'MenuBar', 'none', ...
                                      'NumberTitle', 'off', ...
                                      'DeleteFcn', @(~, ~)obj.delete());

            % Buttons
            h(1) = uicontrol('Style', 'PushButton', 'String', 'Stop',  'Callback', @(~, ~)obj.stop());
            h(2) = uicontrol('Style', 'PushButton', 'String', 'Start', 'Callback', @(~, ~)obj.start());
            h(3) = uicontrol('Style', 'PushButton', 'String', 'Reset', 'Callback', @(~, ~)obj.reset());
            h(4) = uicontrol('Style', 'PushButton', 'String', 'Log text', 'Callback', @(~, ~)obj.uiLog());

            % Edit boxes for maze parameters (each calls updt() on change)
            h(5)  = uicontrol('Style', 'Edit', 'String', num2str(var.reward_probability'), ...
                              'Callback', @(~, ~)obj.updt(var));
            obj.reward_probability = h(5);

            h(6)  = uicontrol('Style', 'Edit', 'String', num2str(var.reward_duration), ...
                              'Callback', @(~, ~)obj.updt(var));
            obj.reward_duration = h(6);

            h(7)  = uicontrol('Style', 'Edit', 'String', num2str(var.start_location_beg), ...
                              'Callback', @(~, ~)obj.updt(var));
            obj.start_location_beg = h(7);

            h(8)  = uicontrol('Style', 'Edit', 'String', num2str(var.start_location_end), ...
                              'Callback', @(~, ~)obj.updt(var));
            obj.start_location_end = h(8);

            h(9)  = uicontrol('Style', 'Edit', 'String', num2str(var.reward_location'), ...
                              'Callback', @(~, ~)obj.updt(var));
            obj.reward_location = h(9);

            h(10) = uicontrol('Style', 'Edit', 'String', num2str(var.stop_location), ...
                              'Callback', @(~, ~)obj.updt(var));
            obj.stop_location = h(10);

            h(11) = uicontrol('Style', 'Edit', 'String', num2str(var.speed_gain), ...
                              'Callback', @(~, ~)obj.updt(var));
            obj.speed_gain = h(11);

            h(12) = uicontrol('Style', 'Edit', 'String', num2str(var.hallway_Xpos'), ...
                              'Callback', @(~, ~)obj.updt(var));
            obj.hallway_Xpos = h(12);

            h(13) = uicontrol('Style', 'Edit', 'String', num2str(var.hallway_prob), ...
                              'Callback', @(~, ~)obj.updt(var));
            obj.hallway_prob = h(13);

            % Layout
            p = get(h(1), 'Position');
            set(h, 'Position', [p(1:2), 4 * p(3), p(4)]);
            align(h, 'Left', 'Fixed', 0.5 * p(1));
            set(obj.figureHandle, 'Position', ...
                [500 + obj.figureHandle.Position(1), ...
                 obj.figureHandle.Position(2) - 100, ...
                 3.7 * p(3) + 10 * p(1), ...
                 1.8 * numel(h) * p(4)]);

            % Labels for each parameter field
            ps = get(h(5),'position');  ps(1) = ps(1) + 250; ps(3) = 120;
            uicontrol('Style', 'Text', 'String', 'Reward Probability','position',ps);
            ps = get(h(6),'position');  ps(1) = ps(1) + 250; ps(3) = 120;
            uicontrol('Style', 'Text', 'String', 'Reward Duration','position',ps);
            ps = get(h(7),'position');  ps(1) = ps(1) + 250; ps(3) = 120;
            uicontrol('Style', 'Text', 'String', 'Start Location_beg','position',ps);
            ps = get(h(8),'position');  ps(1) = ps(1) + 250; ps(3) = 120;
            uicontrol('Style', 'Text', 'String', 'Start Location_end','position',ps);
            ps = get(h(9),'position');  ps(1) = ps(1) + 250; ps(3) = 120;
            uicontrol('Style', 'Text', 'String', 'Reward Location','position',ps);
            ps = get(h(10),'position'); ps(1) = ps(1) + 250; ps(3) = 120;
            uicontrol('Style', 'Text', 'String','Stop Location','position',ps);
            ps = get(h(11),'position'); ps(1) = ps(1) + 250; ps(3) = 120;
            uicontrol('Style', 'Text', 'String', 'Speed Gain','position',ps);
            ps = get(h(12),'position'); ps(1) = ps(1) + 250; ps(3) = 120;
            uicontrol('Style', 'Text', 'String', 'Hallway Xpos','position',ps);
            ps = get(h(13),'position'); ps(1) = ps(1) + 250; ps(3) = 120;
            uicontrol('Style', 'Text', 'String', 'Hallway Prob','position',ps);

            % Teleport counter display
            ps = get(h(5),'position');
            ps(1) = ps(1) + 250; ps(2) = ps(2) - 100; ps(3) = 200; ps(4) = 50;
            obj.teltxt  = uicontrol('Style', 'Text', 'String', '0','position',ps,'fontsize',28);
        end

        %% Simple wrappers for logging and blank/pause
        function blank(obj, duration)
            % blank(duration)
            % duration > 0: enable Blank, then schedule turning it off.
            % duration == 0: immediately disable Blank.
            obj.scheduler.stop(obj.blankId);
            if duration == 0
                obj.sender.send('enable,Blank,0;', obj.addresses);
            elseif duration > 0
                obj.sender.send('enable,Blank,1;', obj.addresses);
                obj.blankId = obj.scheduler.delay({@obj.blank, 0}, duration);
            end
        end

        function set.gain(obj, gain)
            obj.mGain = gain;
            obj.print('gain,%.2f', gain);
        end

        function gain = get.gain(obj)
            gain = obj.mGain;
        end

        function set.speed(obj, speed)
            obj.mSpeed = speed;
            obj.print('speed,%.2f', speed);
        end

        function speed = get.speed(obj)
            speed = obj.mSpeed;
        end

        function delete(obj)
            % Destructor: stop treadmill trigger, free scheduler and sender,
            % close log file, and export CSV->MAT.

            obj.treadmill.trigger = false;
            delete(obj.treadmill);
            delete(obj.scheduler);

            % Nodes-based maze is not used; nodes is likely [], but we guard anyway.
            if ~isempty(obj.nodes) && isvalid(obj.nodes)
                delete(obj.nodes);
            end

            delete(obj.sender);
            obj.log('note,delete');
            fclose(obj.fid);
            TreadmillMaze.export(obj.filename);

            if ishandle(obj.figureHandle)
                set(obj.figureHandle, 'DeleteFcn', []);
                delete(obj.figureHandle);
            end
        end

        function log(obj, format, varargin)
            % Low-level logging helper: writes a line to the CSV file.
            fprintf(obj.fid, '%.3f,%s\n', toc(obj.startTime), sprintf(format, varargin{:}));
        end

        function pause(obj, duration)
            % pause(duration)
            % If duration > 0: enable Blank and disable treadmill movement.
            % If duration == 0: re-enable treadmill movement and disable Blank.
            obj.scheduler.stop(obj.pauseId);
            if duration == 0
                obj.enabled = true;
                obj.sender.send('enable,Blank,0;', obj.addresses);
            elseif duration > 0
                obj.enabled = false;
                obj.sender.send('enable,Blank,1;', obj.addresses);
                obj.pauseId = obj.scheduler.delay({@obj.pause, 0}, duration);
            end
        end

        function print(obj, format, varargin)
            % print(...) - write both to console and to CSV log.
            fprintf('[%.1f] %s\n', toc(obj.startTime), sprintf(format, varargin{:}));
            obj.log(format, varargin{:});
        end

        function reset(obj)
            % Reset high-level trial counter and (legacy) Nodes path vertices.
            obj.trial = 1;
            % Node-based maze is unused; do not touch obj.nodes here.
            obj.treadmill.frame = 0;
            obj.treadmill.step  = 0;
            obj.print('note,reset');
        end

        %% High-level start/stop for the VR task
        function start(obj)
            % Start a SnowyV2 hallway session:
            %  * Loads trial order and reward locations from text files.
            %  * Chooses initial scene.
            %  * Resets NI encoder.
            %  * Sends scene and camera state to VR.
            %  * Starts lick acquisition.
            %  * Enables treadmill movement and begins logging.

            global sbuf sbufsize framesize
            global lickVec rewardVec lickState rewardStatus rewardPtr %#ok<NUSED,GLOBL>
            global rewardLine ax1 lickLine trialNum trialsAx trialLicks successfulTrials %#ok<NUSED,GLOBL>
            global lickWindow lickPlot %#ok<NUSED,GLOBL>

            % Scene table: entries must match Unity scene names.
            obj.scene_table = { ...
                'Snowy_star_chair'; ...
                'Snowy_drum_star'; ...
                'Desert_star_chair'; ...
                'Desert_drum_star'; ...
                'Snowy_chair_star'; ...
                'Snowy_star_drum'; ...
                'Snowy_solo'; ...
                'Snowy_star_star'; ...
                'Swamp_drum9'; 'Swamp_drum10'; 'Swamp_drum11'; 'Swamp_drum12'; ...
                'Swamp_drum13'; 'Swamp_drum14'; 'Swamp_drum15'; 'Swamp_drum16'};

            % Load trial order from text file (one integer per line).
            sfid = fopen('TrialOrder_VR28.txt','r');
            obj.scene_idx = cell2mat(textscan(sfid,'%d'));
            fclose(sfid);

            % Load reward location records: each row ~ [sceneId reward1 reward2]
            tfid = fopen('reward_location_recording_file_snowyV2_even.txt','r');
            obj.reward_locations_arr = cell2mat(textscan(tfid,'%d  %d  %d'));
            fclose(tfid);

            obj.scene_pointer = 1;
            tidx = obj.scene_idx(obj.scene_pointer);
            obj.scene = obj.scene_table{tidx};
            fprintf('scene # =  %d       scene =  %s\n',tidx,obj.scene);

            obj.reward_locations = obj.reward_locations_arr(tidx,:);

            % Set which rewards are active for this scene
            obj.reward1_active = obj.reward_locations(2) > 0;
            obj.reward2_active = obj.reward_locations(3) > 0;

            % Buffer for lick plotting (legacy visualization)
            sbufsize = 4000;
            framesize = 25;
            sbuf = zeros(sbufsize,1);

            % Teleport counters
            obj.number_of_teleports    = 0;
            obj.number_of_nonrewards   = 0;
            set(obj.teltxt,'string',num2str(obj.number_of_teleports));

            % One-second blackout after teleport
            obj.blackoutTime = 1;

            % Load initial scene to VR
            obj.current_hallway = 1;
            obj.sender.send(sprintf('scene,%s;', obj.scene), obj.addresses);

            % Hide menu, disable blank, position camera at start
            obj.sender.send('enable,Menu,0;', obj.addresses);
            obj.sender.send('enable,Blank,0;', obj.addresses);
            obj.sender.send(Tools.compose([sprintf( ...
                'position,Main Camera,%.3f,6,%.3f;', 30, obj.camera_offset), ...
                'rotation,Main Camera,0,%.3f,0;'], obj.offsets), ...
                obj.addresses);

            % Trigger-out high pulse (treadmill trigger abstraction)
            obj.treadmill.trigger = true;
            obj.enabled = true;
            obj.print('note,start');

            % Start position at start_location_beg and reset the encoder
            obj.position_data_start = obj.var.start_location_beg;
            resetCounters(obj.daqsession);
            obj.state = 0;

            % Sync var with GUI fields and save maze.mat
            obj.updt(obj.var);

            % Log current parameter values
            obj.log('start pushed');
            obj.log('%s',['  reward_probability     ' num2str(obj.var.reward_probability')]);
            obj.log('%s',['  reward_location     ' num2str(obj.var.reward_location')]);
            obj.log('%s',['  reward_duration     ' num2str(obj.var.reward_duration')]);
            obj.log('%s',['  start_location_beg     ' num2str(obj.var.start_location_beg')]);
            obj.log('%s',['  start_location_end     ' num2str(obj.var.start_location_end')]);
            obj.log('%s',['  stop_location     ' num2str(obj.var.stop_location')]);
            obj.log('%s',['  speed_gain     ' num2str(obj.var.speed_gain')]);
            obj.log('%s',['  hallway_Xpos     ' num2str(obj.var.hallway_Xpos')]);
            obj.log('%s',['  hallway_prob     ' num2str(obj.var.hallway_prob')]);

            % Start lick acquisition in background
            startBackground(obj.daqin);
        end

        function stop(obj)
            % Stop the hallway task:
            %  * Stops treadmill triggers.
            %  * Blanks VR screens.
            %  * Stops lick acquisition.
            obj.treadmill.trigger = false;
            obj.sender.send('enable,Blank,1;', obj.addresses);
            obj.enabled = false;
            obj.print('note,stop');
            stop(obj.daqin);
        end
    end

    %% Private callbacks and core control loop
    methods (Access = private)

        function getD(~, ~, event, varargin)
            % getD - lick detection callback (called by NI when AI buffer fills).
            %
            % Inputs:
            %   event.Data (vector of voltages) -> we use the last sample.
            % Behavior:
            %   * Determines lick onset via threshold crossing.
            %   * Logs 'lick' whenever a lick is detected.
            %   * Legacy plotting code is left in a disabled "if 0" block.

            global sbuf framesize sbufsize
            global lickVec lickState rewardStatus rewardPtr rewardVec %#ok<NUSED,GLOBL>
            global lickWindow rewardLine trialsAx lickPlot lickLine trialNum successfulTrials %#ok<NUSED,GLOBL>

            obj = varargin{1};

            % Shift buffer, append new data
            sbuf(1:end-framesize)   = sbuf(1+framesize:end);
            sbuf(end-framesize+1:end) = event.Data;

            % Simple threshold on the last sample
            if event.Data(end) > 1.5
                lickState(2) = 1;
            else
                lickState(2) = 0;
            end

            % Detect rising edge
            if isequal(lickState,[0 1])
                lickVec = [lickVec round(toc,2)];
            end
            lickState(1) = lickState(2);

            % Log licks
            if lickState(2)
                obj.log('lick');
            end

            % Legacy lick plotting disabled to reduce overhead
            if 0
                % set(lickLine, 'YData', sbuf);
                % [ .. plotting code .. ]
            end
        end

        function newTrial(obj)
            % LEGACY: newTrial
            % This was used in the Nodes-based maze and tape-trigger path
            % (laps, nodes, etc.). It is *not* used in this hallway task,
            % but is left here as a no-op that just gives a reward and logs.

            obj.giveReward();
            Tools.tone(obj.rewardTone(1), obj.rewardTone(2));

            if obj.intertrialBehavior
                obj.blank(obj.intertrialDuration);
            else
                obj.pause(obj.intertrialDuration);
            end

            % Legacy log: distance/yaw/position would come from Nodes; we
            % just log zeros here to avoid errors if ever called.
            obj.log('data,%i,%i,%.2f,%.2f,%.2f,%.2f', ...
                obj.treadmill.frame, obj.treadmill.step, 0, 0, 0, 0);
            obj.trial = obj.trial + 1;
            obj.print('trial,%i', obj.trial);
        end

        function onBridge(obj, connected)
            % Callback for treadmill bridge connection (legacy).
            if connected
                obj.print('note,Arduino connected.');
            else
                obj.print('note,Arduino disconnected.');
            end
        end

        %% All Node-based callbacks are now essentially disabled
        function onChange(obj, position, distance, yaw) %#ok<INUSD>
            % LEGACY Nodes-based callback (not used in this hallway task).
            % Left here for compatibility; does nothing.
        end

        function onFrame(obj, frame) %#ok<INUSD>
            % LEGACY treadmill frame-based logging (not used).
            % Left here as a no-op for compatibility.
        end

        function onLap(obj) %#ok<MANU>
            % LEGACY lap-based callback (Nodes path).
            % Not used in hallway task.
        end

        function onTape(obj, forward) %#ok<INUSD>
            % LEGACY tape-trigger callback (Nodes path).
            % Not used in hallway task.
        end

        function onNode(obj, node) %#ok<INUSD>
            % LEGACY node callback (Nodes path).
            % Not used in hallway task.
        end

        function onStep(obj, step) %#ok<INUSD>
            % LEGACY step callback (Nodes path).
            % Not used in hallway task.
        end

        %% Core NI-based hallway control loop
        function onUpdate(obj)
            % onUpdate - the main closed-loop controller.
            %
            % Called at obj.fps Hz by Scheduler. Each call:
            %   1) Reads NI counter (encoder).
            %   2) Converts to revolutions and hallway position.
            %   3) During blackout: holds camera at start, waits blackoutTime.
            %   4) Otherwise: sends position to VR via UDP.
            %   5) Checks reward zones and delivers rewards when crossed.
            %   6) Detects hallway end, initiates teleport & blackout.
            %
            % This is the critical timing-sensitive section; we avoid prints
            % and heavy work here.

            % -------------------------
            % Handle blackout / wait state
            % -------------------------
            if obj.waitflag == 1
                df = toc - obj.wait_start_time;

                % Read encoder but ignore for movement (we just keep position fixed)
                positionData = inputSingleScan(obj.daqsession);
                signedData   = positionData(:,1);
                signedData(signedData > obj.signedThreshold) = ...
                    signedData(signedData > obj.signedThreshold) - 2^obj.counterNBits;
                positionDataRevs = -signedData / obj.encoderCPR; %#ok<NASGU>

                % Keep camera at start while blank is on
                obj.sender.send(Tools.compose([sprintf( ...
                    'position,Main Camera,%.3f,6,%.3f;', 30, obj.position_data_start + obj.camera_offset ), ...
                    'rotation,Main Camera,0,%.3f,0;'], obj.offsets), ...
                    obj.addresses);

                % End blackout after blackoutTime seconds
                if df > obj.blackoutTime
                    obj.waitflag           = 0;
                    obj.sender.send('enable,Blank,0;', obj.addresses);
                    obj.position_data_start = obj.var.start_location_beg;
                    resetCounters(obj.daqsession);
                    positionData            = 0; %#ok<NASGU>
                    obj.position_data_previous = 0;
                end
            end

            % -------------------------
            % Normal running state
            % -------------------------
            positionData = inputSingleScan(obj.daqsession);
            signedData   = positionData(:,1);
            signedData(signedData > obj.signedThreshold) = ...
                signedData(signedData > obj.signedThreshold) - 2^obj.counterNBits;
            positionDataRevs = -signedData / obj.encoderCPR;

            % Only update when encoder changes
            if (positionData - obj.position_data_previous) ~= 0
                % Compute hallway position
                position(1) = obj.var.hallway_Xpos(obj.current_hallway);  %#ok<NASGU>
                position(2) = obj.position_data_start - obj.var.speed_gain * positionDataRevs;
                yaw = 0;

                % Send camera state to VR (UDP)
                obj.sender.send(Tools.compose([sprintf( ...
                    'position,Main Camera,%.3f,6,%.3f;', 30, position(2) + obj.camera_offset ), ...
                    'rotation,Main Camera,0,%.3f,0;'], yaw + obj.offsets), ...
                    obj.addresses);

                % Toggle position clock (digital)
                if obj.enabled
                    obj.xr = xor(obj.xr, 1);
                end
                outputSingleScan(obj.daqoutdig, obj.xr);

                % Log position with scene index (or 99 during wait)
                if obj.waitflag == 1
                    obj.log('loc, state, %d , %.3f ', 99, position(2));
                else
                    obj.log('loc, state, %d , %.3f ', obj.scene_idx(obj.scene_pointer), position(2));
                end

                % -------------------------
                % Reward zone checks
                % -------------------------
                if obj.reward1_active && position(2) >= obj.reward_locations(2)
                    obj.log('reward');
                    obj.giveReward();
                    obj.state = 1;
                    obj.reward1_active = 0;
                end

                if obj.reward2_active && position(2) >= obj.reward_locations(3)
                    obj.log('reward');
                    obj.giveReward();
                    obj.state = 1;
                    obj.reward2_active = 0;
                end

                % -------------------------
                % Teleport when hallway end is reached
                % -------------------------
                if position(2) > obj.var.stop_location
                    positionDataRevs = 0; %#ok<NASGU>

                    % Reset position to start of hallway and encoder
                    obj.position_data_start = obj.var.start_location_beg;
                    resetCounters(obj.daqsession);
                    obj.state = 0;

                    % Switch to blank screen during teleport blackout
                    obj.sender.send('enable,Blank,1;', obj.addresses);

                    % Advance to next scene in scene_idx
                    obj.scene_pointer = obj.scene_pointer + 1;
                    if obj.scene_pointer > length(obj.scene_idx)
                        obj.scene_pointer = 1;
                    end

                    % Load new scene and reward locations
                    tidx        = obj.scene_idx(obj.scene_pointer);
                    obj.scene   = obj.scene_table{tidx};
                    fprintf('scene # =  %d       scene =  %s\n',tidx,obj.scene);
                    obj.reward_locations = obj.reward_locations_arr(tidx,:);

                    obj.reward1_active = obj.reward_locations(2) > 0;
                    obj.reward2_active = obj.reward_locations(3) > 0;

                    obj.sender.send(sprintf('scene,%s;', obj.scene), obj.addresses);

                    % Start blackout timer
                    obj.blankTimer      = tic; %#ok<NASGU>
                    obj.wait_start_time = toc;
                    obj.waitflag        = 1;
                end

                % Update teleport display
                set(obj.teltxt,'string',num2str(obj.number_of_teleports));

                % Save last encoder reading
                obj.position_data_previous = positionData;
            end
            obj.position_data_previous = positionData;
        end

        %% Unified NI-based reward helper
        function giveReward(obj)
            % giveReward
            % ----------
            % This is the unified reward method for this hallway task.
            %
            % It:
            %   * Toggles the digital reward line (rwdout) on Port0/Line1.
            %   * Sends a 5 V pulse on ao0 using obj.daqout for a duration
            %     defined by obj.var.reward_duration (in samples at 1 kHz).
            %
            % NOTE: We no longer manipulate plotting handles here (rewardLine,
            % etc.) to avoid invalid handle errors and overhead.

            global rewardVec rewardStatus rewardPtr rewardLine trialNum %#ok<NUSED,GLOBL>

            % Digital toggle of valve line
            obj.rwdxr = xor(obj.rwdxr, 1);
            outputSingleScan(obj.rwdout, obj.rwdxr);

            % Analog 5 V pulse for reward_duration samples
            if ~isempty(obj.daqout)
                nSamp = max(1, round(obj.var.reward_duration));
                pulse = [5*ones(nSamp,1); 0];  % 5 V pulse then return to 0
                queueOutputData(obj.daqout, pulse);
                startBackground(obj.daqout);
            end

            % We leave global variables untouched for compatibility, but do not
            % try to update GUI plots here.
        end

        %% GUI helpers
        function uiLog(obj)
            % uiLog - log the contents of textBox to the CSV file as a note.
            if ~isempty(obj.textBox.String)
                obj.print('note,%s', obj.textBox.String);
                obj.textBox.String = '';
            end
        end

        function updt(obj, var)
            % updt - read GUI fields into obj.var and save maze.mat.
            %
            % Called each time a GUI edit box changes. This keeps the var
            % struct in sync with the GUI and persists changes to disk.

            var.speed_gain         = str2double(obj.speed_gain.String);
            var.reward_duration    = str2double(obj.reward_duration.String);
            var.start_location_beg = str2double(obj.start_location_beg.String);
            var.start_location_end = str2double(obj.start_location_end.String);
            var.reward_location    = readn(obj.reward_location.String);
            var.stop_location      = str2double(obj.stop_location.String);
            var.reward_probability = readn(obj.reward_probability.String);
            var.hallway_Xpos       = readn(obj.hallway_Xpos.String);
            var.hallway_prob       = readn(obj.hallway_prob.String);

            obj.var = var;
            save('maze.mat','var');
        end
    end

    %% Static export helper
    methods (Static)
        function export(filename)
            % export(filename)
            % ---------------
            % Converts the CSV log file created by this class into a .mat file
            % with a 'header' cell array and a numeric 'data' matrix.
            %
            % Columns correspond to:
            %   [time (s), frame, encoder-step, distance, yaw, x, z]

            header = {'time (s)', 'frame', 'encoder-step', ...
                      'unfolded-distance (cm)', 'y-rotation (degrees)', ...
                      'x-position (cm)', 'z-position (cm)'};
            data = str2double(CSV.parse(CSV.load(filename), [-1 1:6], 'data'));
            [folder, fname] = fileparts(filename);
            save(fullfile(folder, sprintf('%s.mat', fname)), 'header', 'data');
        end
    end
end
