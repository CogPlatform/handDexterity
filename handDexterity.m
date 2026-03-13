%% Main Script: Dexterity Analysis for Apple Grasping Experiments
% Author: [Wang XiaoChun]
% Purpose: Analyze monkey hand movements for apple grasping tasks, calculate error rates, reaction times, and spatial metrics
% Features: 
% 1. Folder selection dialog for data directory
% 2. Robust file I/O with error handling
% 3. Optimized data processing pipelines
% 4. Clear modular structure with English documentation
% 5. Improved computational efficiency (vectorization, reduced redundant calculations)

clearvars
close all
clc

%% Step 1: User Input - Select Data Directory
% Let analyst select target folder interactively
dataDir = uigetdir(pwd, 'Select the folder containing hand/apple CSV data files');
if dataDir == 0
    error('No folder selected. Please run the script again and select a valid data directory.');
end
cd(dataDir); % Set working directory to selected folder

%% Step 2: Configuration Parameters
monkeyNames = {'76','11','43','44','60','70','76','132','133','137','159','187','195'};
monkeyNum = length(monkeyNames);
p2mm = 3; % Pixel to millimeter conversion (1mm = 3 pixels)
rng('default'); % Set random seed for reproducibility

%% Step 3: Batch Process Each Monkey's Data
for monkeyIdx = 1:monkeyNum
    % Get monkey ID and find relevant CSV files
    monkeyID = char(monkeyNames(monkeyIdx));
    filePattern = [monkeyID '-*-hand.csv'];
    fileList = dir(fullfile(dataDir, filePattern)); % Use dir instead of ls for better structure
    
    if isempty(fileList)
        warning('No files found for monkey %s with pattern: %s', monkeyID, filePattern);
        continue;
    end
    
    fileNum = length(fileList);
    % Preallocate arrays for efficiency
    slitErrorRate = zeros(fileNum, 1);
    wanderErrorRate = zeros(fileNum, 1);
    dropRate = zeros(fileNum, 1);
    rtValidMean = zeros(fileNum, 1);
    appleEdgeDistance = zeros(fileNum, 1);

    %% Step 4: Process Each File
    for fileIdx = 1:fileNum
        try
            % Get file paths
            handFilePath = fullfile(fileList(fileIdx).folder, fileList(fileIdx).name);
            appleFilePath = strrep(handFilePath, '-hand.csv', '-apple.csv');
            
            % Validate apple file exists
            if ~exist(appleFilePath, 'file')
                error('Apple file not found: %s', appleFilePath);
            end

            % Read and process single file
            fileData = struct();
            fileData.handFilePath = handFilePath;
            fileData.appleFilePath = appleFilePath;
            [singleFileResults, ~] = processSingleFile(fileData);

            % Store results
            slitErrorRate(fileIdx) = singleFileResults.slitE_rate;
            wanderErrorRate(fileIdx) = singleFileResults.wandE_rate;
            dropRate(fileIdx) = singleFileResults.drop_rate;
            rtValidMean(fileIdx) = singleFileResults.RT_vali_mean;
            appleEdgeDistance(fileIdx) = singleFileResults.a2e_distance / p2mm;

        catch ME
            warning('Failed to process file %s: %s', fileList(fileIdx).name, ME.message);
            % Assign NaN for failed files to maintain array structure
            slitErrorRate(fileIdx) = NaN;
            wanderErrorRate(fileIdx) = NaN;
            dropRate(fileIdx) = NaN;
            rtValidMean(fileIdx) = NaN;
            appleEdgeDistance(fileIdx) = NaN;
        end
    end

    %% Step 5: Generate Output Table and Save
    % Create output filename
    outputFileName = strrep(fileList(1).name, '-hand.csv', '.xlsx');
    outputFilePath = fullfile(dataDir, outputFileName);

    % Prepare data matrix (round to 2 decimal places)
    dataMatrix = [
        round(slitErrorRate, 2);
        round(wanderErrorRate, 2);
        round(dropRate, 2);
        round(rtValidMean, 2);
        round(appleEdgeDistance, 2)
    ];

    % Define table variables
    errorTypes = {
        'slitErrorRate';
        'wanderErrorRate';
        'dropRate';
        'fetchTime(Valid trials:ms)';
        'distance(Apple-Edge:mm)'
    };
    
    % Generate session column names
    sessionNames = cell(1, fileNum);
    for k = 1:fileNum
        sessionNames{k} = ['Session_' num2str(k)];
    end

    % Build output table
    outputTable = table(errorTypes, 'VariableNames', {'ErrorType'});
    for k = 1:fileNum
        outputTable.(sessionNames{k}) = dataMatrix(:, k);
    end

    % Save table to Excel (overwrite existing file)
    writetable(outputTable, outputFilePath, 'WriteMode', 'overwrite');
    fprintf('Successfully saved results for monkey %s to: %s\n', monkeyID, outputFilePath);
end

fprintf('\nBatch processing completed successfully!\n');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Core Functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [results, handData] = processSingleFile(fileData)
    % PROCESSINGLEFILE Process single hand/apple CSV file pair
    %   Input:
    %       fileData - Struct containing:
    %           handFilePath - Path to hand CSV file
    %           appleFilePath - Path to apple CSV file
    %   Output:
    %       results - Struct with computed metrics (error rates, RT, distance)
    %       handData - Struct with raw/processed hand/apple tracking data

    %% Step 1: Read and parse CSV files
    handData = readAndParseCSV(fileData.handFilePath, fileData.appleFilePath);
    
    %% Step 2: Extract apple trajectory features
    appleData = extractAppleTrace(handData);
    
    %% Step 3: Detect action events (timing, invalid trials, drops)
    actionData = detectActionEvents(handData, appleData);
    
    %% Step 4: Calculate error metrics
    [slitHitError, wanderError, graspError] = calculateErrorMetrics(handData, actionData, appleData);
    
    %% Step 5: Compile and save results
    results = compileResults(appleData, graspError, slitHitError, wanderError, actionData, fileData);
end

function handData = readAndParseCSV(handFilePath, appleFilePath)
    % READANDPARSECSV Read and parse hand/apple CSV files with validation
    % Thresholds for valid tracking points
    handConfidenceThresh = 1e-5;
    appleConfidenceThresh = 0.2;

    %% Read hand CSV
    try
        tHand = readtable(handFilePath, 'ReadVariableNames', true);
        handVarNames = tHand.Properties.VariableNames;
        handRawData = table2array(tHand);
    catch ME
        error('Failed to read hand file %s: %s', handFilePath, ME.message);
    end

    %% Read apple CSV
    try
        tApple = readtable(appleFilePath, 'ReadVariableNames', true);
        appleVarNames = tApple.Properties.VariableNames;
        appleRawData = table2array(tApple);
    catch ME
        error('Failed to read apple file %s: %s', appleFilePath, ME.message);
    end

    %% Extract hand joint coordinates
    % Thumb joints
    [thumbTipX, thumbTipY] = extractTrackedPoint(handVarNames, handRawData, ...
        'tip1_x', 'tip1_y', 'tip1_p', handConfidenceThresh);
    [thumbPipX, thumbPipY] = extractTrackedPoint(handVarNames, handRawData, ...
        'PIP1_x', 'PIP1_y', 'PIP1_p', handConfidenceThresh);
    [thumbMcpX, thumbMcpY] = extractTrackedPoint(handVarNames, handRawData, ...
        'MCP1_x', 'MCP1_y', 'MCP1_p', handConfidenceThresh);
    [baseX, baseY] = extractTrackedPoint(handVarNames, handRawData, ...
        'base_x', 'base_y', 'base_p', handConfidenceThresh);

    % Index finger joints
    [indexTipX, indexTipY] = extractTrackedPoint(handVarNames, handRawData, ...
        'tip2_x', 'tip2_y', 'tip2_p', handConfidenceThresh);
    [indexDipX, indexDipY] = extractTrackedPoint(handVarNames, handRawData, ...
        'DIP2_x', 'DIP2_y', 'DIP2_p', handConfidenceThresh);
    [indexPipX, indexPipY] = extractTrackedPoint(handVarNames, handRawData, ...
        'PIP2_x', 'PIP2_y', 'PIP2_p', handConfidenceThresh);
    [indexMcpX, indexMcpY] = extractTrackedPoint(handVarNames, handRawData, ...
        'MCP2_x', 'MCP2_y', 'MCP2_p', handConfidenceThresh);

    %% Extract apple/slit/pole coordinates
    % Slit edge position
    slotCols = findColumnIndices(appleVarNames, 'SlotTop_x', 'SlotBottom_x', 'SlotTop_y', 'SlotBottom_y');
    edgeX = (mean(appleRawData(:, slotCols(1)), 'omitnan') + mean(appleRawData(:, slotCols(2)), 'omitnan')) / 2;

    % Apple position
    [appleX, appleY] = extractTrackedPoint(appleVarNames, appleRawData, ...
        'Apple_x', 'Apple_y', 'Apple_p', appleConfidenceThresh);

    % Pole position
    [poleX, poleY] = extractTrackedPoint(appleVarNames, appleRawData, ...
        'Pole_x', 'Pole_y', 'Pole_p', appleConfidenceThresh);

    %% Compile hand data struct
    handData = struct();
    handData.thumbTipX = thumbTipX;
    handData.thumbTipY = thumbTipY;
    handData.thumbPipX = thumbPipX;
    handData.thumbPipY = thumbPipY;
    handData.thumbMcpX = thumbMcpX;
    handData.thumbMcpY = thumbMcpY;
    handData.baseX = baseX;
    handData.baseY = baseY;

    handData.indexTipX = indexTipX;
    handData.indexDipX = indexDipX;
    handData.indexPipX = indexPipX;
    handData.indexMcpX = indexMcpX;
    handData.indexTipY = indexTipY;
    handData.indexDipY = indexDipY;
    handData.indexPipY = indexPipY;
    handData.indexMcpY = indexMcpY;

    handData.edgeX = edgeX;
    handData.appleX = appleX;
    handData.appleY = appleY;
    handData.poleX = poleX;
    handData.poleY = poleY;
    handData.handFilePath = handFilePath;
end

function [x, y] = extractTrackedPoint(varNames, rawData, xName, yName, pName, confidenceThresh)
    % EXTRACTTRACKEDPOINT Extract and filter tracked point coordinates
    % Apply confidence threshold and moving average smoothing
    
    % Find column indices
    xCol = findColumnIndices(varNames, xName);
    yCol = findColumnIndices(varNames, yName);
    pCol = findColumnIndices(varNames, pName);

    % Extract raw coordinates
    x = rawData(:, xCol);
    y = rawData(:, yCol);
    p = rawData(:, pCol);

    % Apply confidence threshold (set low-confidence points to NaN)
    x(p < confidenceThresh) = NaN;
    y(p < confidenceThresh) = NaN;

    % Apply 5-point moving average for smoothing
    x = movmean(x, 5, 'omitnan');
    y = movmean(y, 5, 'omitnan');
end

function appleData = extractAppleTrace(handData)
    % EXTRACTAPPLETRACE Extract apple trajectory features (start time, position filtering)
    appleX = handData.appleX;
    appleY = handData.appleY;
    edgeX = handData.edgeX;
    nFrames = length(appleX);

    %% Filter invalid apple positions
    appleX(appleX < edgeX - 20) = NaN;    % Filter left of slit edge
    appleX(appleX > 350) = NaN;          % Filter beyond glass boundary
    appleY(isnan(appleX)) = NaN;         % Sync NaNs between X/Y

    %% Detect backward apple movement (human retrieval)
    backwardWindow = 30; % 1 second (30 frames)
    appleDiff = [NaN; diff(appleX)];
    signDiff = sign(appleDiff);
    signDiff(isnan(signDiff)) = 0;
    sumSign = movsum(signDiff, backwardWindow, 'omitnan');
    
    % Find positions with sustained backward movement
    backwardLocs = find(sumSign >= backwardWindow);
    [counts, centers] = histcounts(appleX(~isnan(appleX)), 20);
    [~, maxCountIdx] = max(counts);
    mostPosition = centers(maxCountIdx);

    % Remove points from human retrieval
    if ~isempty(backwardLocs)
        for i = 1:length(backwardLocs)-2
            if appleX(backwardLocs(i)) > mostPosition + 20
                appleX(backwardLocs(i)-2:backwardLocs(i)+2) = NaN;
            end
        end
    end

    %% Detect apple appearance start times
    appleStart = [];
    % Look for transition from NaN to valid decreasing X (apple entering slit)
    for frameIdx = 3:nFrames-5
        if all(isnan(appleX(frameIdx-2:frameIdx))) && ...
           appleX(frameIdx+1) > appleX(frameIdx+2) && ...
           appleX(frameIdx+2) > appleX(frameIdx+3) && ...
           appleX(frameIdx+3) > appleX(frameIdx+4) && ...
           appleY(frameIdx+1) > 190 && appleY(frameIdx+1) < 215
            
            appleStart = [appleStart, frameIdx+1];
        end
    end

    %% Visualization (optional)
    figure('Name', 'Apple Trajectory');
    plot(appleX, 1:nFrames, 'c-', 'LineWidth', 1);
    hold on;
    plot(appleX(appleStart), appleStart, 'ro', 'MarkerSize', 6);
    plot([edgeX, edgeX], [1, nFrames], 'r--', 'LineWidth', 1);
    xlabel('X Position (pixels)');
    ylabel('Frame Number');
    title(['Apple Trajectory - ' handData.handFilePath]);
    hold off;

    %% Compile apple data
    appleData.appleStart = appleStart;
    appleData.appleDiff = appleDiff;
    appleData.mostPosition = mostPosition;
    appleData.appleX = appleX;
    appleData.appleY = appleY;
    appleData.nApples = length(appleStart);
end

function actionData = detectActionEvents(handData, appleData)
    % DETECTACTIONEVENTS Detect action timing, invalid trials, and drop events
    appleStart = appleData.appleStart;
    appleX = appleData.appleX;
    appleY = appleData.appleY;
    edgeX = handData.edgeX;
    poleY = mean(handData.poleY, 'omitnan');
    nApples = appleData.nApples;
    nFrames = length(appleX);

    %% Preallocate action matrix
    % Columns: 1=TrialID, 2=AppleStart, 3=AppleStop, 4=AppleDisappear, 
    %          5=InvalidStatus, 6=FwdTime, 7=BackTime, 8=TouchTime, 9=DropStatus
    actionMatrix = zeros(nApples, 9);
    dropIDs = [];

    %% Process each apple trial
    for appleIdx = 1:nApples
        % Define time window for current apple
        if appleIdx < nApples
            timeWindow = appleStart(appleIdx):appleStart(appleIdx+1)-1;
        else
            timeWindow = appleStart(appleIdx):nFrames;
        end
        
        appleWindowX = appleX(timeWindow);
        actionMatrix(appleIdx, 1) = appleIdx;          % Trial ID
        actionMatrix(appleIdx, 2) = appleStart(appleIdx); % Apple start frame

        %% Detect apple stop position
        appleDiffWindow = abs([NaN; diff(appleX(timeWindow))]);
        stopLocs = findContinuousValues(appleDiffWindow, 0.5, 3); % Continuous low movement
        
        if length(stopLocs) > 3
            appleEnd = stopLocs(1);
            peakX = mean(findpeaks(appleWindowX));
            % Validate stop position
            while appleX(timeWindow(1)+appleEnd-1) > peakX + 20 && appleEnd < length(stopLocs)-1
                appleEnd = stopLocs(appleEnd+1);
            end
        else
            stopLocs = find(appleDiffWindow < 0.2, 1, 'first');
            if isempty(stopLocs)
                [~, minDiffIdx] = min(abs(appleDiffWindow));
                appleEnd = minDiffIdx;
            else
                appleEnd = stopLocs;
            end
        end
        actionMatrix(appleIdx, 3) = timeWindow(1) + appleEnd - 1; % Apple stop frame

        %% Detect apple disappearance
        disappearLocs = findContinuousNaN(appleWindowX, 12); % 12 consecutive NaNs
        if isempty(disappearLocs)
            appleDisappear = appleEnd + 200;
        else
            appleDisappear = disappearLocs(1);
            % Validate disappearance time
            while appleDisappear < appleEnd && appleDisappear < length(disappearLocs)-1
                appleDisappear = disappearLocs(appleDisappear+1);
            end
        end
        
        % Bound disappearance time to valid frame range
        if timeWindow(1) + appleDisappear > nFrames
            actionMatrix(appleIdx, 4) = nFrames - 10;
        else
            actionMatrix(appleIdx, 4) = timeWindow(1) + appleDisappear - 2;
        end

        %% Detect apple drop events
        dropStatus = 0;
        appleYWindow = handData.appleY(actionMatrix(appleIdx, 2):timeWindow(end));
        dropLocs = find(appleYWindow > poleY + 6); % Threshold for drop detection
        
        if length(dropLocs) > 2 && mean(diff(appleYWindow(dropLocs))) > 1e-4
            dropStatus = 1;
            dropIDs = [dropIDs, appleIdx];
        end
        actionMatrix(appleIdx, 9) = dropStatus;

        %% Detect invalid trials (out-of-bounds stop position)
        stopXMean = mean(appleX(actionMatrix(:, 3)), 'omitnan');
        stopYMean = mean(appleY(actionMatrix(:, 3)), 'omitnan');
        windowThresh = 30; % 1cm in pixels
        stopX = mean(appleX(actionMatrix(appleIdx, 3)-2:actionMatrix(appleIdx, 3)+2), 'omitnan');
        stopY = mean(appleY(actionMatrix(appleIdx, 3)-2:actionMatrix(appleIdx, 3)+2), 'omitnan');
        
        if stopX > stopXMean + windowThresh || stopX < stopXMean - windowThresh || ...
           stopY > stopYMean + windowThresh || stopY < stopYMean - windowThresh
            actionMatrix(appleIdx, 5) = 1; % Mark as invalid
        else
            actionMatrix(appleIdx, 5) = 0; % Valid trial
        end

        %% Detect grasp timing (forward/backward movement across slit edge)
        [fwdTime, backTime] = detectGraspTiming(handData, actionMatrix, appleIdx);
        if isempty(fwdTime) || isempty(backTime) || backTime < fwdTime
            actionMatrix(appleIdx, 6:7) = [NaN, NaN];
            actionMatrix(appleIdx, 5) = 1; % Mark as invalid
        else
            actionMatrix(appleIdx, 6:7) = [fwdTime, backTime];
            % Detect touch time (max Y position of index tip)
            indexYWindow = handData.indexTipY(fwdTime:backTime);
            [~, touchOffset] = max(indexYWindow);
            actionMatrix(appleIdx, 8) = fwdTime + touchOffset;
        end
    end

    %% Compile action data
    actionData.actionMatrix = actionMatrix;
    actionData.invalidIDs = find(actionMatrix(:, 5) == 1);
    actionData.dropIDs = dropIDs;
    actionData.combinedInvalidIDs = unique([actionData.invalidIDs; dropIDs]);
    actionData.appleEdgeDistance = stopXMean - edgeX;
end

function [fwdTime, backTime] = detectGraspTiming(handData, actionMatrix, trialIdx)
    % DETECTGRASPTIMING Detect forward/backward movement across slit edge
    fwdTime = [];
    backTime = [];
    trialWindow = actionMatrix(trialIdx, 2):actionMatrix(trialIdx, 4);
    edgeX = handData.edgeX;
    indexTipX = handData.indexTipX;
    appleX = handData.appleX;

    for frameIdx = trialWindow
        % Detect forward movement (crossing edge from left to right)
        if frameIdx > 1 && frameIdx < length(indexTipX) && ~isnan(appleX(frameIdx))
            if indexTipX(frameIdx-1) <= edgeX && indexTipX(frameIdx+1) >= edgeX
                fwdTime = [fwdTime, frameIdx];
                
                % Detect backward movement (crossing edge back to left)
                k = frameIdx;
                while k < frameIdx + 1000 && k < length(indexTipX)
                    if indexTipX(k) >= edgeX && indexTipX(k+1) <= edgeX
                        backTime = [backTime, k];
                        break;
                    end
                    k = k + 1;
                end
            end
        end
    end

    % Get last valid timing points
    if ~isempty(fwdTime), fwdTime = fwdTime(end); end
    if ~isempty(backTime), backTime = backTime(end); end
end

function [slitHitError, wanderError, graspError] = calculateErrorMetrics(handData, actionData, appleData)
    % CALCULATEERRORMETRICS Calculate three main error types:
    %   1. Slit hit error
    %   2. Wander error (re-grasp attempts)
    %   3. Precision grasp error

    %% Prepare valid action data (remove invalid/drop trials)
    validActionMatrix = removeErrorTrials(actionData.actionMatrix, actionData.combinedInvalidIDs);
    nValidTrials = size(validActionMatrix, 1);

    %% Calculate slit hit error
    slitHitError = calculateSlitHitError(validActionMatrix, handData);
    
    %% Calculate wander error
    wanderError = calculateWanderError(validActionMatrix, handData);
    
    %% Calculate precision grasp error
    graspError = calculatePrecisionGraspError(validActionMatrix, handData);

    %% Add trial count to error structs
    slitHitError.nValidTrials = nValidTrials;
    wanderError.nValidTrials = nValidTrials;
    graspError.nValidTrials = nValidTrials;
end

function errorData = calculateSlitHitError(validActionMatrix, handData)
    % CALCULATESLITHITERROR Calculate slit hit error rate (slow movement at slit edge)
    nValidTrials = size(validActionMatrix, 1);
    errorCount = 0;
    errorIDs = [];
    edgeX = handData.edgeX;
    indexTipX = handData.indexTipX;

    for trialIdx = 1:nValidTrials
        % Time window around forward movement time
        fwdTime = validActionMatrix(trialIdx, 6);
        if isnan(fwdTime), continue; end
        
        timeWindow = fwdTime - 10:fwdTime + 10;
        timeWindow = timeWindow(timeWindow >= 1 & timeWindow <= length(indexTipX)); % Bound to valid frames
        
        % Calculate index tip velocity
        indexVelX = [false; diff(indexTipX(timeWindow))];
        meanVel = mean(indexVelX(9:11)); % Mean velocity at critical frame range
        
        % Classify error (slow movement = slit hit error)
        if meanVel < 5
            errorCount = errorCount + 1;
            errorIDs = [errorIDs, validActionMatrix(trialIdx, 1)];
        end
    end

    %% Compile error data
    errorData.num = errorCount;
    errorData.ids = errorIDs;
    errorData.rate = errorCount / nValidTrials;
end

function errorData = calculateWanderError(validActionMatrix, handData)
    % CALCULATEWANDERERROR Calculate wander error (multiple grasp attempts)
    nValidTrials = size(validActionMatrix, 1);
    errorCount = 0;
    errorIDs = [];
    edgeX = handData.edgeX;
    
    % Preprocess tip coordinates
    indexTipX = handData.indexTipX;
    indexTipY = handData.indexTipY;
    thumbTipX = handData.thumbTipX;
    thumbTipY = handData.thumbTipY;

    % Filter out-of-bounds points
    indexTipX(indexTipX < edgeX) = NaN;
    indexTipX(indexTipX > 340) = NaN;
    indexTipY(isnan(indexTipX)) = NaN;

    for trialIdx = 1:nValidTrials
        % Get grasp time window
        fwdTime = validActionMatrix(trialIdx, 6);
        backTime = validActionMatrix(trialIdx, 7);
        if isnan(fwdTime) || isnan(backTime), continue; end
        
        timeWindow = fwdTime:backTime;
        if length(timeWindow) < 5, continue; end

        %% Calculate tip distance
        indexTip = [indexTipX(timeWindow), 406 - indexTipY(timeWindow)];
        thumbTip = [thumbTipX(timeWindow), 406 - thumbTipY(timeWindow)];
        tipDistance = sqrt(sum((indexTip - thumbTip).^2, 2));

        %% Detect extreme values (peaks/troughs)
        [tMax, vMax, tMin, vMin] = findExtrema(tipDistance, timeWindow');
        
        %% Classify wander error (multiple significant grasp attempts)
        if ~isempty(tMin) && length(tMax) >= 2
            % Combine and sort extrema
            extremaTimes = [tMin; tMax];
            extremaValues = [vMin; vMax];
            extremaData = sortrows([extremaTimes, extremaValues], 1);
            extremaDiff = diff(extremaData);
            
            % Count significant extrema changes
            significantChanges = 0;
            for i = 1:size(extremaDiff, 1)
                if extremaDiff(i, 1) > 5 && abs(extremaDiff(i, 2)) > 9
                    significantChanges = significantChanges + 1;
                end
            end
            
            % Classify error if multiple significant changes
            if significantChanges >= 2
                errorCount = errorCount + 1;
                errorIDs = [errorIDs, validActionMatrix(trialIdx, 1)];
            end
        end
    end

    %% Compile error data
    errorData.num = errorCount;
    errorData.ids = errorIDs;
    errorData.rate = errorCount / nValidTrials;
end

function errorData = calculatePrecisionGraspError(validActionMatrix, handData)
    % CALCULATEPRECISIONGRASPERROR Calculate precision grasp error (poor finger positioning)
    nValidTrials = size(validActionMatrix, 1);
    errorCount = 0;
    errorIDs = [];

    %% Extract joint coordinates
    indexTipX = handData.indexTipX;
    indexTipY = handData.indexTipY;
    thumbTipX = handData.thumbTipX;
    thumbTipY = handData.thumbTipY;
    baseX = handData.baseX;
    baseY = handData.baseY;
    thumbMcpX = handData.thumbMcpX;
    thumbMcpY = handData.thumbMcpY;
    indexMcpX = handData.indexMcpX;
    indexMcpY = handData.indexMcpY;
    appleX = handData.appleX;
    appleY = handData.appleY;

    for trialIdx = 1:nValidTrials
        % Get touch time window
        touchTime = validActionMatrix(trialIdx, 8);
        if isnan(touchTime), continue; end
        
        timeWindow = touchTime - 2:touchTime + 3;
        timeWindow = timeWindow(timeWindow >= 1 & timeWindow <= length(appleX)); % Bound to valid frames
        nWindowFrames = length(timeWindow);

        %% Calculate distances and angles
        tipDistance = zeros(nWindowFrames, 1);
        thumbIndexAngle = zeros(nWindowFrames, 1);

        for frameIdx = 1:nWindowFrames
            % Current frame coordinates
            frame = timeWindow(frameIdx);
            idxTip = [indexTipX(frame), indexTipY(frame)];
            thumbTip = [thumbTipX(frame), thumbTipY(frame)];
            base = [baseX(frame), baseY(frame)];
            thumbMcp = [thumbMcpX(frame), thumbMcpY(frame)];
            indexMcp = [indexMcpX(frame), indexMcpY(frame)];

            %% Calculate tip-to-tip distance
            tipDistance(frameIdx) = norm(idxTip - thumbTip);

            %% Calculate thumb-index angle (using law of cosines)
            a = norm(base - thumbMcp);
            b = norm(thumbMcp - indexMcp);
            c = norm(base - indexMcp);
            if a > 0 && c > 0 % Avoid division by zero
                thumbIndexAngle(frameIdx) = acosd((a^2 + c^2 - b^2) / (2 * a * c));
            else
                thumbIndexAngle(frameIdx) = NaN;
            end
        end

        %% Classify grasp error (poor precision)
        meanTipDistance = mean(tipDistance, 'omitnan');
        meanAngle = mean(thumbIndexAngle, 'omitnan');
        
        if meanTipDistance > 30 || meanAngle > 30
            errorCount = errorCount + 1;
            errorIDs = [errorIDs, validActionMatrix(trialIdx, 1)];
        end
    end

    %% Compile error data
    errorData.num = errorCount;
    errorData.ids = errorIDs;
    errorData.rate = errorCount / nValidTrials;
end

function results = compileResults(appleData, graspError, slitHitError, wanderError, actionData, fileData)
    % COMPILERESULTS Compile all analysis results into a single struct
    nApples = appleData.nApples;
    invalidIDs = actionData.invalidIDs;
    dropIDs = actionData.dropIDs;
    combinedInvalidIDs = actionData.combinedInvalidIDs;

    %% Calculate reaction time metrics
    validActionMatrix = removeErrorTrials(actionData.actionMatrix, combinedInvalidIDs);
    rtValid = (validActionMatrix(:, 7) - validActionMatrix(:, 6)) * 1000 / 60; % Convert to ms
    rtValidMean = mean(rtValid, 'omitnan');

    %% Calculate error rates
    slitErrorRate = slitHitError.num / slitHitError.nValidTrials;
    wanderErrorRate = wanderError.num / wanderError.nValidTrials;
    dropRate = length(dropIDs) / nApples;

    %% Compile final results
    results = struct();
    results.slitE_rate = slitErrorRate;
    results.wandE_rate = wanderErrorRate;
    results.drop_rate = dropRate;
    results.RT_vali_mean = rtValidMean;
    results.a2e_distance = actionData.appleEdgeDistance;
    results.invalidIDs = invalidIDs;
    results.dropIDs = dropIDs;
    results.nApples = nApples;

    %% Save MAT file (optional)
    matFileName = strrep(fileData.handFilePath, '-hand.csv', '.mat');
    save(matFileName, 'results');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Helper Functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function colIndices = findColumnIndices(varNames, varargin)
    % FINDCOLUMNINDICES Find column indices for variable names (case-insensitive)
    colIndices = [];
    nTargets = length(varargin);

    for i = 1:nTargets
        targetName = strtrim(varargin{i});
        % Case-insensitive match with trimmed names
        idx = find(strcmpi(strtrim(varNames), targetName), 1);
        
        if isempty(idx)
            error('Column name "%s" not found in file.\nAvailable columns (first 10):\n%s', ...
                targetName, strjoin(varNames(1:min(10, end)), ', '));
        end
        
        colIndices = [colIndices, idx];
    end
end

function stopLocs = findContinuousValues(data, threshold, minCount)
    % FINDCONTINUOUSVALUES Find locations with continuous values below threshold
    binaryData = data < threshold;
    binaryData(isnan(binaryData)) = 0; % Treat NaN as 0
    movingSum = movsum(binaryData, minCount);
    stopLocs = find(movingSum == minCount);
end

function nanLocs = findContinuousNaN(data, minCount)
    % FINDCONTINUOUSNAN Find locations with continuous NaN values
    binaryData = isnan(data);
    movingSum = movsum(binaryData, minCount);
    nanLocs = find(movingSum == minCount);
end

function [tMax, vMax, tMin, vMin] = findExtrema(values, times)
    % FINDEXTREMA Find local maxima/minima in a signal
    dv = diff(values);
    dvSign = sign(dv);
    ddvSign = diff(dvSign);

    % Detect local maxima (sign change from + to -)
    maxLocs = find(ddvSign == -2) + 1;
    % Detect local minima (sign change from - to +)
    minLocs = find(ddvSign == 2) + 1;

    % Extract times/values for extrema
    tMax = times(maxLocs);
    vMax = values(maxLocs);
    tMin = times(minLocs);
    vMin = values(minLocs);
end

function validTrials = removeErrorTrials(actionMatrix, errorIDs)
    % REMOVEERRORTRIALS Remove error trials from action matrix
    if isempty(errorIDs)
        validTrials = actionMatrix;
        return;
    end

    % Find rows to remove
    removeRows = [];
    for i = 1:length(errorIDs)
        rowIdx = find(actionMatrix(:, 1) == errorIDs(i));
        removeRows = [removeRows, rowIdx];
    end

    % Remove error trials
    validTrials = actionMatrix;
    validTrials(removeRows, :) = [];
end