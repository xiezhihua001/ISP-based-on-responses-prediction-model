clear; close all; clc;

DELTA_LAMBDA = 5;
WAVELENGTHS = 400:DELTA_LAMBDA:700;
GAINS = [0.3535, 0.1621, 0.3489]; % ISO100
T = 0.01; % 10ms
CC_MODEL = 'root6x3';

% load canonical illuminant spd
canonical_illuminant_spd = xlsread('cie.15.2004.tables.xls', 1, 'B27:B87')';

% load 'unknown' illuminant spds
unknown_illuminant_names = {'D65', 'A', 'D50', 'CWF', 'TL84'};
unknown_illuminant_spds = [xlsread('cie.15.2004.tables.xls', 1, 'B27:B87')';... % D65
                           xlsread('cie.15.2004.tables.xls', 1, 'A27:A87')';... % A
                           xlsread('cie.15.2004.tables.xls', 1, 'E27:E87')';... % D50
                           xlsread('cie.15.2004.tables.xls', 6, 'C10:C70')';... % CWF
                           xlsread('cie.15.2004.tables.xls', 6, 'C10:C70')'];   % TL84


% load parameters of imaging simulation model
data_path = load('global_data_path.mat');
params_dir = fullfile(data_path.path,...
                      'imaging_simulation_model\parameters_estimation\responses\NIKON_D3x\camera_parameters.mat');
load(params_dir);

% load spectral reflectane data of Classic ColorChecker
wavelengths = 400:10:700;
spectral_reflectance_train = xlsread('SpectralReflectance_DSG140_SP64.csv', 1, 'Q5:AU284') / 100;
spectral_reflectance_val = xlsread('SpectralReflectance_Classic24_SP64.csv', 1, 'Q5:AU52') / 100;

spectral_reflectance_train = interp1(wavelengths, spectral_reflectance_train', WAVELENGTHS, 'pchip')';
spectral_reflectance_val = interp1(wavelengths, spectral_reflectance_val', WAVELENGTHS, 'pchip')';

spectral_reflectance_train = (spectral_reflectance_train(1:2:end, :) + spectral_reflectance_train(2:2:end, :)) / 2;
spectral_reflectance_val = (spectral_reflectance_val(1:2:end, :) + spectral_reflectance_val(2:2:end, :)) / 2;

% calculate XYZ values
canonical_xyz_train = spectra2colors(spectral_reflectance_train, WAVELENGTHS, 'spd', 'd65');
canonical_xyz_val = spectra2colors(spectral_reflectance_val, WAVELENGTHS, 'spd', 'd65');

for i = 1:numel(unknown_illuminant_names)
    iname = unknown_illuminant_names{i};
    unknown_illuminant_spd = unknown_illuminant_spds(i, :);
    
    % training
    spectra_train = spectral_reflectance_train .* unknown_illuminant_spd;
    [~, saturation] = responses_predict(spectra_train, WAVELENGTHS, params, GAINS, T, DELTA_LAMBDA);
    camera_rgb_train_ = responses_predict(spectra_train/saturation, WAVELENGTHS, params, GAINS, T, DELTA_LAMBDA);
    neutral_idx = [61, 62, 63, 64, 65];
    gains = [camera_rgb_train_(neutral_idx, 1) \ camera_rgb_train_(neutral_idx, 2),...
             1,...
             camera_rgb_train_(neutral_idx, 3) \ camera_rgb_train_(neutral_idx, 2)];
    camera_rgb_train.(iname) = camera_rgb_train_ .* gains;
    
    [matrix.(iname),...
     scale.(iname),...
     predicted_responses_train.(iname),...
     errs_train.(iname)] = ccmtrain(camera_rgb_train.(iname),...
                                    canonical_xyz_train,...
                                    'model', CC_MODEL,...
                                    'targetcolorspace', 'xyz',...
                                    'whitepoint', whitepoint('d65'));
                                                      
	% validation
    spectra_val = spectral_reflectance_val .* unknown_illuminant_spd;
    [~, saturation] = responses_predict(spectra_val, WAVELENGTHS, params, GAINS, T, DELTA_LAMBDA);
    camera_rgb_val_ = responses_predict(spectra_val/saturation, WAVELENGTHS, params, GAINS, T, DELTA_LAMBDA);
    camera_rgb_val.(iname) = camera_rgb_val_ .* gains;
    
    [predicted_responses_val.(iname),...
     errs_val.(iname)] = ccmvalidate(camera_rgb_val.(iname),...
                                     canonical_xyz_val,...
                                     CC_MODEL,...
                                     matrix.(iname),...
                                     scale.(iname),...
                                     'targetcolorspace', 'xyz');
end

for i = 1:numel(unknown_illuminant_names)
    iname = unknown_illuminant_names{i};
    fprintf(['illuminant %s:\n',...
             'training error: %.2f (mean), %.2f (max)\n',...
             'validation error: %.2f (mean), %.2f (max)\n'],...
             iname,...
             mean(errs_train.(iname)), max(errs_train.(iname)),...
             mean(errs_val.(iname)), max(errs_val.(iname)));
end