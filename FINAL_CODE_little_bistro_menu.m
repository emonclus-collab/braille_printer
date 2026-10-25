clear;
clc;
close all;

%% Menu
menuLines = {
    'the little bistro'
    ''
    'classic'
    'cheeseburger 13'
    'brioche bun, lettuce,'
    'tomato'
    'add bacon 3'
    ''
    'spaghetti marinara 9'
    ''
    'caesar salad 9'
    ''
    'vanilla ice cream 6'
    'homemade vanilla bean'
};

%% Page and spacing settings
paperLeft = 0;
paperBottom = 0;
paperWidth = 210;
paperHeight = 297;

leftMargin = 38.1;
rightMargin = 38.1;

dotSpacingX = 2.5;
dotSpacingY = 2.5;
cellPitch = 6;
linePitch = 15;

firstLineTop = 240.9;

%% Embossing settings
% Board X/Y = page height; board Z = page width.
% E controls the physical Z tool connected to E0.
% Establish workspace zero and fully raised E0 before running.
% Use E2 between dots only after verifying clearance.

pressPosition = 9.5;
raisedPosition = 2;
fullyRaisedPosition = 0;

initialFeedRate = 2000;
moveFeedRate = 1500;
toolFeedRate = 700;
retractFeedRate = 750;
initialToolFeedRate = 30;
returnFeedRate = 2000;
dwellTime = 100;

%% Calculate mirrored Braille coordinates
dotCoordinates = zeros(0,3);
firstCellLeft = paperLeft + paperWidth ...
    - leftMargin - dotSpacingX;

for lineIndex = 1:numel(menuLines)
    cells = menuToBraille(menuLines{lineIndex});

    if isempty(cells), continue; end

    lineWidth = (numel(cells)-1)*cellPitch + dotSpacingX;
    assert(lineWidth <= paperWidth-leftMargin-rightMargin, ...
        'Line %d is too wide.', lineIndex);

    lineTop = firstLineTop - (lineIndex-1)*linePitch;
    assert(lineTop-2*dotSpacingY >= paperBottom, ...
        'Line %d extends below the paper.', lineIndex);

    for k = 1:numel(cells)
        pattern = fliplr(cells{k});
        cellLeft = firstCellLeft - (k-1)*cellPitch;

        for row = 1:3
            for col = 1:2
                if pattern(row,col)
                    w = cellLeft + (col-1)*dotSpacingX;
                    h = lineTop - (row-1)*dotSpacingY;
                    dotCoordinates(end+1,:) = [w, h, lineIndex];
                end
            end
        end
    end
end

%% Preview
figure('Name', 'The Little Bistro');

for face = 1:2
    subplot(1,2,face);

    w = dotCoordinates(:,1) - paperLeft;
    h = dotCoordinates(:,2) - paperBottom;

    if face == 2, w = paperWidth-w; end

    scatter(w,h,8,'filled');
    axis equal;
    grid on;
    xlim([0 paperWidth]);
    ylim([0 paperHeight]);

    if face == 1
        title('Embossing face');
    else
        title('Reading face after flipping');
    end

    xlabel('Page width (mm)');
    ylabel('Height from bottom (mm)');
end

%% Export embossing G-code
outputFile = 'little_bistro_fast_retract.gcode';
fid = fopen(outputFile,'w');
assert(fid ~= -1, 'Could not create G-code file.');

fprintf(fid,'; The Little Bistro\n');
fprintf(fid,'; Existing workspace zero and fully raised E0 required\n');
fprintf(fid,'; Initial F2000; positioning F1500\n');
fprintf(fid,'; Press E11 F700; retract E2 F750\n');
fprintf(fid,'G21\nG90\nM82\n');

% Stay fully raised during initial positioning.
fprintf(fid,'G1 E%.3f F%.0f\n', ...
    fullyRaisedPosition,initialToolFeedRate);

previousLine = 0;

for k = 1:size(dotCoordinates,1)
    w = dotCoordinates(k,1);
    h = dotCoordinates(k,2);
    lineIndex = dotCoordinates(k,3);

    if lineIndex ~= previousLine
        fprintf(fid,'\n; Line %d: %s\n', ...
            lineIndex,menuLines{lineIndex});
        previousLine = lineIndex;
    end

    feed = moveFeedRate;
    if k == 1, feed = initialFeedRate; end

    % Position both gantry motors together.
    fprintf(fid,'G1 X%.3f Y%.3f Z%.3f F%.0f\n', ...
        h,h,w,feed);

    % Press to E11.
    fprintf(fid,'G1 E%.3f F%.0f\n', ...
        pressPosition,toolFeedRate);

    % Hold.
    fprintf(fid,'G4 P%d\n',dwellTime);

    % Retract to E2 before moving to the next dot.
    fprintf(fid,'G1 E%.3f F%.0f\n', ...
        raisedPosition,retractFeedRate);
end

%% Fully retract and return to existing workspace zero
fprintf(fid,'\n; Fully retract and return to workspace zero\n');
fprintf(fid,'G1 E%.3f F%.0f\n', ...
    fullyRaisedPosition,retractFeedRate);
fprintf(fid,'G1 X0.000 Y0.000 Z0.000 F%.0f\n',returnFeedRate);
fprintf(fid,'M400\n');

fclose(fid);
fprintf('Created: %s\n',fullfile(pwd,outputFile));

%% Braille translator
function cells = menuToBraille(text)
    text = lower(char(text));

    assert(isempty(regexp(text,'[^a-z0-9 ,]','once')), ...
        'Use letters, digits, spaces and commas only.');

    dots = {
        1, [1 2], [1 4], [1 4 5], [1 5], ...
        [1 2 4], [1 2 4 5], [1 2 5], [2 4], [2 4 5], ...
        [1 3], [1 2 3], [1 3 4], [1 3 4 5], [1 3 5], ...
        [1 2 3 4], [1 2 3 4 5], [1 2 3 5], ...
        [2 3 4], [2 3 4 5], [1 3 6], [1 2 3 6], ...
        [2 4 5 6], [1 3 4 6], [1 3 4 5 6], [1 3 5 6]
    };

    cells = {};
    numberMode = false;

    for i = 1:numel(text)
        ch = text(i);

        if ch >= '0' && ch <= '9'
            if ~numberMode
                p = zeros(3,2);
                p([3 4 5 6]) = 1;
                cells{end+1} = p;
            end

            numberMode = true;
            index = double(ch)-double('0');
            if index == 0, index = 10; end
            ids = dots{index};

        else
            numberMode = false;

            if ch == ' '
                ids = [];
            elseif ch == ','
                ids = 2;
            else
                ids = dots{double(ch)-double('a')+1};
            end
        end

        p = zeros(3,2);
        p(ids) = 1;
        cells{end+1} = p;
    end
end