%% Fitting multiple PSFs in a single frame

close all
clear all

addpath(genpath('./'));

% Define base parameters
%baseParams.nPixels = 171;
%baseParams.stageDrift = LinearDrift(0.0001, 0.0001, 1, 'nm');
%baseParams.defocusRange = [-500, 500];  % Defocus range

% Input params
thunderstorm_results_path = '/home/tfq96423/Documents/cryoCLEM/dipole-issue/localizationFixedDipoles-motionFit/loop-test/thunderstorm_results.csv';
pixel_width = 51.2; % Pixel width (nm per px)
frames_dir = '/home/tfq96423/Documents/cryoCLEM/dipole-issue/localizationFixedDipoles-motionFit/loop-test/ASIL240923C05_50.ome.tif-frames/';
patch_width = 12; % size of NxN pixel patch around blob centroid to consider


% Run thunderstorm on stack
% (do this manually for now)


% Read in frame, x, y from thunderstorm results table
df = readtable(thunderstorm_results_path);
f_array = df.('frame');
x_array = df.('x_nm_');
y_array = df.('y_nm_');

% Rescale from nm to px
x_array_image_coords = x_array / pixel_width;
y_array_image_coords = y_array / pixel_width;

% Create the centroids in image coordinates
centroids_image_coords = [f_array, round(x_array_image_coords), round(y_array_image_coords)];


% Loop over each frame:
files = dir(frames_dir);
valid_extensions = {'.png', '.jpg', '.jpeg', '.bmp', '.tiff', '.tif'};
frame_paths = {};

% Keep only image files
for i = 1:length(files)
    [~, ~, ext] = fileparts(files(i).name);
    if ismember(lower(ext), valid_extensions)
        frame_paths{end+1} = fullfile(frames_dir, files(i).name);
    end
end

% Loop over each image path and process

% Initialise results arrays
inclination_estimates = [];
azimuth_estimates = [];
x_estimates = [];
y_estimates = [];
defocus_estimates = [];

for frame_index = 1:length(frame_paths)

    fprintf('----------\n');
    fprintf('FRAME %d\n', frame_index);
    frame_path = frame_paths{frame_index};

    % Load frame
    image = imread(frame_path);
    
    % Convert to greyscale if not
    if size(image, 3) == 3
        image = rgb2gray(image);
    end
    
    % Subtract the background roughly
    image = double(image); % Convert to double for calculations
    image = image - mean(image(:)); % Subtract the mean
    image = max(min(image, 255), 0); % Clip values to [0, 255]
    image = uint8(image); % Convert back to uint8

    % Get 12x12 patches around each centroid and show them
    [patches, outlined_image] = extract_patches(centroids_image_coords, frame_index, patch_width, image);
    % Uncomment to make sure patches are in the right places - not
    % implemented properly, but works for a single frame
    % imshow(outlined_image);
    % title('Original Image with Patch Outlines');


    % Loop over each blob in a frame, run analysis

    % Initialise results arrays
    inclination_estimates_frame = [];
    azimuth_estimates_frame = [];
    x_estimates_frame = [];
    y_estimates_frame = [];
    defocus_estimates = [];

    for blob_index = 1:length(patches)

        fprintf('Analysing blob %d/%d\n', blob_index, length(patches));


        % --------------------
        % Simulate psf - replace this whole chunk with reading in an image
        % --------------------
        % Not sure what FitPSF() uses to do the fitting. Does it just use the
        % psf.image part of a psf object? Or does it use the other stuff stored in that?
        % Looking at FitPSF.m, it seems to use a lot of stuff that isn't just
        % the image. Like psf.pixelSensitivityMask, psf.stageDrift, and the
        % parameter estimates. So might need to adapt the PSF simulator so that
        % it "simulates" a psf object containing the image we choose to give
        % it, which will be a patch of a frame.
        %
        % Maybe we can adapt the PSF() class/function/whatever that currently
        % generates a simulation so that it simply generates a psf object where
        % the psf.image bit = some input image. The other stuff in the psf
        % object are experimental params mostly? I think.
        %
        % If we use thunderSTORM to get an initial etimate of localisations ,we
        % can pass those as our initial estimates for this to use.
        % Oh and because the patches we consider will be centered on those
        % locations, the initial estimate will always be (0,0) by definition.

        % Set input parameters
        angleInclination = pi * rand;
        angleAzimuth = 2 * pi * rand;
        par.position = Length([rand rand rand] * 100, 'nm');
        par.dipole = Dipole(angleInclination, angleAzimuth);
        par.stageDrift = LinearDrift(0.0001, 0.0001, 1, 'nm');%(10, 1, 10, 'nm');
        par.defocus = Length(-500 + 1000 * rand(), 'nm');
        % Simulate
        psf = PSF(par);
        % --------------------

        % Fitting
        parEst.angleInclinationEstimate = angleInclination;
        parEst.angleAzimuthEstimate = angleAzimuth;
        parEst.stageDrift = par.stageDrift;
        fitResult = FitPSF(psf, parEst);

        % Store results

        % Estimates for angles are stored in:
        %   fitResult.angleInclinationEstimate
        %   fitResult.angleAzimuthEstimate
        %
        % Position is estimated with both least squares and max likelihood
        %   fitResult.estimatesPositionDefocus.LS
        %   fitResult.estimatesPositionDefocus.ML
        %       given as [x, y, defocus]

        inclination_estimates_frame(blob_index) = fitResult.angleInclinationEstimate;
        azimuth_estimates_frame(blob_index) = fitResult.angleAzimuthEstimate;
        x_estimates_frame(blob_index) = fitResult.estimatesPositionDefocus.ML(1);
        y_estimates_frame(blob_index) = fitResult.estimatesPositionDefocus.ML(2);
        defocus_estimates_frame(blob_index) = fitResult.estimatesPositionDefocus.ML(3);

    end % end loop over blobs

    inclination_estimates{frame_index} = inclination_estimates_frame;
    azimuth_estimates{frame_index} = azimuth_estimates_frame;
    x_estimates{frame_index} = x_estimates_frame;
    y_estimates{frame_index} = y_estimates_frame;
    defocus_estimates{frame_index} = defocus_estimates_frame;

end % end loop over frames

% Flatten the array (convert cell array to a numeric array)
inclination_estimates = [inclination_estimates{:}];
azimuth_estimates = [azimuth_estimates{:}];
x_estimates = [x_estimates{:}];
y_estimates = [y_estimates{:}];
defocus_estimates = [defocus_estimates{:}];

% Make a copy of thunderstorm results table

% Add new localisations to those