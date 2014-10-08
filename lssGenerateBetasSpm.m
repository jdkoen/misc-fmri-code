function images = lssGenerateBetasSpm(subject, spmDir, outDir, ignoreConditions, settings)
% FORMAT images = lssGenerateBetasSpm(subject, spmDir, outDir, ignoreConditions, settings)
% This function takes an existing first-level SPM.mat file uses it to
% create one of two possible models: multi-regressor and multi-model.
% The multi-regressor approach estimates a single model with all trials
% represented by individual regressors. The multi-model approach estimates
% a model for each individual trial, setting the first regressor to the
% individual trial and all other regressors to be the same as the original
% model. Beta images are then moved and renamed in a single betas
% directory. The multi-regressor approach is similar to that described in
% Rissman et al. 2004 NI, and the multi-model approach is similar to the
% LS-S approach described in Turner et al. 2012 NI.
% This function is integrated with newLSS_correlation for beta-series
% functional connectivity with the multi-model approach through
% batch_newLSS.
%
%
% Inputs:
% subject:               Subject ID. String.
% spmDir:                Path to folder containing SPM.mat file. String.
% outDir:                Path to output directory, where generated files
%                        will be saved. String.
% ignoreConditions:      Conditions to be ignored. Set to NONE if you do
%                        not want to ignore any conditions. Cell array of
%                        strings.
% settings:              Additional settings. Structure.
% settings.model:        Which model type you wish to run: Rissman beta
%                        series (1) or LS-S multiple models (2). Double.
% settings.overwrite:    Overwrite any pre-existing files (1) or not (0).
%                        Double.
% settings.deleteFiles:  Delete intermediate files (1) or not (0). Double.
%
% Outputs:
% images:                Cell array of 4D images generated by function in
%                        format images{conds}{sessImages}
%
% Requirements: SPM8, cellstrfind (Matlab function written by Taylor Salo)
%               
%
% Author: Maureen Ritchey, 10-2012
% Modified by Taylor Salo (140806) according to adjustments suggested by
% Jeanette Mumford. LS-S now matches Turner et al. 2012 NI, where the
% design matrix basically matches the original design matrix (for a given
% block), except for the single trial being evaluated, which gets its own
% regressor. Also now you can ignore multiple conditions. I also added some
% overwrite stuff so that it won't re-run existing subjects if you don't
% want it to.

%% MAIN CODE
% Load pre-existing SPM file containing model information
fprintf('\nLoading previous model for %s:\n%s\n', subject, [spmDir, '/SPM.mat']);
if exist([spmDir '/SPM.mat'],'file')
    load([spmDir '/SPM.mat'])
    SPM_orig = SPM;
else
    error('Cannot find SPM.mat file.');
end

if ~exist(outDir, 'dir')
    fprintf('\nCreating directory:\n%s\n', outDir);
    mkdir(outDir)
end

% Get model information from SPM file
fprintf('\nGetting model information...\n');
files = SPM.xY.P;
fprintf('Modeling %i timepoints across %i sessions.\n', size(files, 1), length(SPM.Sess));
% Make trial directory
betaDir = [outDir 'betas/'];
if ~exist(betaDir, 'dir')
    mkdir(betaDir)
end

% MULTI-MODEL APPROACH
if settings.model == 2
    % Set up beta information
    trialInfo = {'beta_number' 'session' 'condition' 'condition_rep' 'number_onsets' 'beta_name' 'trial_dir' 'beta_name'};
    counter = 1;

    % Loop across sessions
    for iSess = 1:length(SPM.Sess)
        rows = SPM.Sess(iSess).row;
        sessFiles = files(rows', :);
        sessFiles = cellstr(sessFiles);
        covariates = SPM.Sess(iSess).C.C;

        for jCond = 1:length(SPM.Sess(iSess).U)
            % As long as the current condition isn't an IgnoreCondition,
            % set up a model for each individual trial.
            if ~cellstrfind(SPM.Sess(iSess).U(jCond).name{1}, ignoreConditions, '')
                for kCond = 1:length(SPM.Sess(iSess).U)
                    allOtherConds{kCond} = SPM.Sess(iSess).U(kCond).name{1};
                    allConds{kCond} = SPM.Sess(iSess).U(kCond).name{1};
                end
                allOtherConds(jCond) = [];
                otherDiffCondNames = allOtherConds;
                
                for jjCond = 1:length(SPM.Sess(iSess).U)
                    if jCond ~= jjCond
                        for jjjCond = 1:length(allOtherConds)
                            if strcmp(SPM.Sess(iSess).U(jjCond).name{1}, allOtherConds{jjjCond})
                                otherDiffCondOnsets{jjjCond} = SPM.Sess(iSess).U(jjCond).ons;
                                otherDiffCondDurations{jjjCond} = SPM.Sess(iSess).U(jjCond).dur;
                            end
                        end
                    end
                end
                if settings.overwrite || ~exist([betaDir '4D_' allConds{jCond} '_Sess' sprintf('%03d', iSess) '.nii'], 'file')
                    for kTrial = 1:length(SPM.Sess(iSess).U(jCond).ons)
                        % Set onsets and durations. setdiff will reorder alphabetically/numerically,
                        % but that should not matter.
                        onsets = {};
                        durations = {};
                        names = {};

                        singleName = [SPM.Sess(iSess).U(jCond).name{1} '_' sprintf('%03d', kTrial)];
                        otherSameCondName = ['OTHER_' SPM.Sess(iSess).U(jCond).name{1}];

                        singleOnset = SPM.Sess(iSess).U(jCond).ons(kTrial);
                        singleDuration = SPM.Sess(iSess).U(jCond).dur(kTrial);
                        [otherSameCondOnsets, index] = setdiff(SPM.Sess(iSess).U(jCond).ons, SPM.Sess(iSess).U(jCond).ons(kTrial));
                        otherSameCondDurations = SPM.Sess(iSess).U(jCond).dur(index);
                        
                        % This is basically a special case for conditions
                        % with only one trial in that Session. Hopefully
                        % you would ignore such conditions (since they're
                        % hopefully error conditions or NRs), but if you
                        % didn't the script would otherwise break here.
                        if ~isempty(otherSameCondOnsets)
                            onsets = [onsets singleOnset otherSameCondOnsets otherDiffCondOnsets];
                            durations = [durations singleDuration otherSameCondDurations otherDiffCondDurations];
                            names = [names singleName otherSameCondName otherDiffCondNames];
                        else
                            onsets = [onsets singleOnset otherSameCondOnsets otherDiffCondOnsets];
                            durations = [durations singleDuration otherSameCondDurations otherDiffCondDurations];
                            names = [names singleName otherSameCondName otherDiffCondNames];
                        end

                        % Make trial directory
                        trialDir = [outDir 'Sess' sprintf('%03d', iSess) '/' singleName '/'];
                        if ~exist(trialDir,'dir')
                            mkdir(trialDir)
                        end

                        % Add trial information
                        currInfo = {counter iSess SPM.Sess(iSess).U(jCond).name{1} kTrial...
                            length(SPM.Sess(iSess).U(jCond).ons(kTrial)) singleName trialDir...
                            ['Sess' sprintf('%03d', iSess) '_' singleName '.img']};
                        trialInfo = [trialInfo; currInfo];

                        % Save regressor onset files
                        regFile = [trialDir 'st_regs.mat'];
                        save(regFile, 'names', 'onsets', 'durations');

                        covFile = [trialDir 'st_covs.txt'];
                        dlmwrite(covFile, covariates, '\t');

                        % Create matlabbatch for creating new SPM.mat file
                        matlabbatch = create_spm_init(trialDir, SPM);
                        matlabbatch = create_spm_sess(matlabbatch, 1, sessFiles, regFile, covFile, SPM);

                        % Run matlabbatch to create new SPM.mat file using SPM batch tools
                        if counter == 1
                            spm_jobman('initcfg')
                            spm('defaults', 'FMRI');
                        end
                        if settings.overwrite || ~exist([trialDir 'beta_0001.img'], 'file')
                            fprintf('\nCreating SPM.mat file:\n%s\n\n', [trialDir 'SPM.mat']);
                            spm_jobman('serial', matlabbatch);
                            clear matlabbatch
                            runBatches = 1;
                        else
                            clear matlabbatch
                            runBatches = 0;
                        end
                        counter = counter + 1;

                        if runBatches
                            fprintf('\nEstimating model from SPM.mat file.\n');
                            spmFile = [trialDir 'SPM.mat'];
                            matlabbatch = estimate_spm(spmFile);
                            spm_jobman('serial', matlabbatch);
                            clear matlabbatch

                            % Copy first beta image to beta directory
                            copyfile([trialDir 'beta_0001.img'],[betaDir 'Sess' sprintf('%03d', iSess) '_' singleName '.img']);
                            copyfile([trialDir 'beta_0001.hdr'],[betaDir 'Sess' sprintf('%03d', iSess) '_' singleName '.hdr']);

                            % Discard extra files, if desired
                            if settings.deleteFiles
                                prevDir = pwd;
                                cd(trialDir);
                                delete SPM*; delete *.hdr; delete *.img;
                                cd(prevDir);
                            end
                        end
                    end
                end
            end
        end
        
        % Make 4D image for each condition of interest in block.
        wantedConds = setdiff(allConds, ignoreConditions);
        for jCond = 1:length(wantedConds)
            condVols = dir([betaDir 'Sess' sprintf('%03d', iSess) '_' wantedConds{jCond} '*.img']);

            cellVols = struct2cell(condVols);
            cellVols = cellVols(1, :);
            for kVol = 1:length(cellVols)
                cellVols{kVol} = [betaDir cellVols{kVol} ',1'];
            end
            images{jCond}{iSess} = [betaDir '4D_' wantedConds{jCond} '_Sess' sprintf('%03d', iSess) '.nii'];
            matlabbatch{1}.spm.util.cat.name = [betaDir '4D_' wantedConds{jCond} '_Sess' sprintf('%03d', iSess) '.nii'];
            matlabbatch{1}.spm.util.cat.vols = cellVols;
            matlabbatch{1}.spm.util.cat.dtype = 0;
            
            if settings.overwrite || ~exist([betaDir '4D_' wantedConds{jCond} '_Sess' sprintf('%03d', iSess) '.nii'], 'file')
                save([betaDir '3Dto4D_jobfile.mat'], 'matlabbatch');
                spm_jobman('run', matlabbatch);
            else
                fprintf('Exists: %s\n', [betaDir '4D_' wantedConds{jCond} '_Sess' sprintf('%03d', iSess) '.nii']);
            end
        end
    end

    % Save beta information
    infofile = [betaDir subject '_beta_info.mat'];
    save(infofile, 'trialInfo');

% MULTI-REGRESSOR APPROACH
elseif settings.model == 1
    spmFile = [outDir 'SPM.mat'];
    
    % Set up beta information
    trialInfo = {'beta_number' 'session' 'condition' 'condition_rep' 'number_onsets' 'first_onset' 'beta_name'};
    counter = 1;

    % Loop across sessions
    wantedConds = {};
    for iSess = 1:length(SPM.Sess)
        rows = SPM.Sess(iSess).row;
        sessFiles = files(rows', :);
        sessFiles = cellstr(sessFiles);
        covariates = SPM.Sess(iSess).C.C;

        onsets = {};
        durations = {};
        names = {};

        for jCond = 1:length(SPM.Sess(iSess).U)
            % Check for special condition names to lump together
            if cellstrfind(SPM.Sess(iSess).U(jCond).name{1}, ignoreConditions, '')
                onsets = [onsets SPM.Sess(iSess).U(jCond).ons'];
                durations = [durations SPM.Sess(iSess).U(jCond).dur'];
                singleName = [SPM.Sess(iSess).U(jCond).name{1}];
                names = [names singleName];
                currInfo = {counter iSess SPM.Sess(iSess).U(jCond).name{1}...
                    1 length(SPM.Sess(iSess).U(jCond).ons) SPM.Sess(iSess).U(jCond).ons(1) singleName};
                trialInfo = [trialInfo; currInfo];
                counter = counter + 1;
            % Otherwise set up a regressor for each individual trial
            else
                wantedConds{length(wantedConds) + 1} = SPM.Sess(iSess).U(jCond).name{1};
                for kTrial = 1:length(SPM.Sess(iSess).U(jCond).ons)
                    onsets = [onsets SPM.Sess(iSess).U(jCond).ons(kTrial)];
                    durations = [durations SPM.Sess(iSess).U(jCond).dur(kTrial)];
                    singleName = [SPM.Sess(iSess).U(jCond).name{1} '_' num2str(kTrial)];
                    names = [names singleName];
                    currInfo = {counter iSess SPM.Sess(iSess).U(jCond).name{1}...
                        kTrial length(SPM.Sess(iSess).U(jCond).ons(kTrial))...
                        SPM.Sess(iSess).U(jCond).ons(kTrial) singleName};
                    trialInfo = [trialInfo; currInfo];
                    counter = counter + 1;
                end
            end
        end

        % Save regressor onset files
        if settings.overwrite || ~exist(spmFile, 'file')
            fprintf('Saving regressor onset files for Session %i: %i trials included\n', iSess, length(names));
            regFile = [outDir 'st_regs_session_' num2str(iSess) '.mat'];
            save(regFile, 'names', 'onsets', 'durations');

            % Save covariates (e.g., motion parameters) that were specified
            % in the original model
            covFile = [outDir 'st_covs_session_' num2str(iSess) '.txt'];
            dlmwrite(covFile, covariates, '\t');
            if ~isempty(covariates)
                for icov = 1:size(covariates, 2)
                    currInfo = {counter iSess 'covariate' icov 1 0 strcat('covariate',num2str(icov))};
                    trialInfo = [trialInfo; currInfo];
                    counter = counter + 1;
                end
            end

            % Create matlabbatch for creating new SPM.mat file
            if iSess == 1
                matlabbatch = create_spm_init(outDir, SPM);
            end
            matlabbatch = create_spm_sess(matlabbatch, iSess, sessFiles, regFile, covFile, SPM);
            
            % Save beta information
            infofile = [outDir 'beta_info_session_' num2str(iSess) '.mat'];
            save(infofile, 'trialInfo');
        end
    end
    
    % Run matlabbatch to create new SPM.mat file using SPM batch tools
    if settings.overwrite || ~exist([outDir 'SPM.mat'], 'file')
        fprintf('\nCreating SPM.mat file:\n%s\n', [outDir 'SPM.mat']);
        spm_jobman('initcfg')
        spm('defaults', 'FMRI');
        spm_jobman('serial', matlabbatch);
        clear matlabbatch

        fprintf('\nEstimating model from SPM.mat file.\n');
        matlabbatch = estimate_spm(spmFile);
        spm_jobman('serial', matlabbatch);
    else
        fprintf('Exists: %s\n', [outDir 'SPM.mat']);
    end
    
    clear matlabbatch
    load(spmFile);
    wantedConds = unique(wantedConds);
    for iCond = 1:length(wantedConds)
        counter = 1;
        for jBeta = 1:length(SPM.Vbeta)
            if strfind(SPM.Vbeta(jBeta).descrip, wantedConds{iCond})
                cellVols{counter} = [SPM.swd '/' SPM.Vbeta(jBeta).fname ',1'];
                counter = counter + 1;
            end
        end
        images{iCond}{1} = [betaDir '4D_' wantedConds{iCond} '.nii'];
        matlabbatch{iCond}.spm.util.cat.name = [betaDir '4D_' wantedConds{iCond} '.nii'];
        matlabbatch{iCond}.spm.util.cat.vols = cellVols;
        matlabbatch{iCond}.spm.util.cat.dtype = 0;
        clear cellVols
    end
    if settings.overwrite || ~exist([betaDir '4D_' wantedConds{end} '.nii'], 'file')
        save([betaDir '3Dto4D_jobfile.mat'], 'matlabbatch');
        spm_jobman('run', matlabbatch);
    else
        fprintf('Exists: %s\n', [betaDir '4D_' wantedConds{end} '.nii']);
    end
    clear SPM matlabbatch
else
    error('Specify model type as 1 or 2');
end

clear SPM
end

%% SUBFUNCTIONS
function [matlabbatch] = create_spm_init(outDir, SPM)
% Subfunction for initializing the matlabbatch structure to create the SPM
    matlabbatch{1}.spm.stats.fmri_spec.dir = {outDir};
    matlabbatch{1}.spm.stats.fmri_spec.timing.units = SPM.xBF.UNITS;
    matlabbatch{1}.spm.stats.fmri_spec.timing.RT = SPM.xY.RT;
    matlabbatch{1}.spm.stats.fmri_spec.timing.fmri_t = SPM.xBF.T;
    matlabbatch{1}.spm.stats.fmri_spec.timing.fmri_t0 = SPM.xBF.T0;
    matlabbatch{1}.spm.stats.fmri_spec.fact = struct('name', {}, 'levels', {});
    matlabbatch{1}.spm.stats.fmri_spec.bases.hrf.derivs = [0 0];
    matlabbatch{1}.spm.stats.fmri_spec.volt = SPM.xBF.Volterra;
    matlabbatch{1}.spm.stats.fmri_spec.global = 'None';
    if isempty(SPM.xM.VM)
        matlabbatch{1}.spm.stats.fmri_spec.mask = {''};
    else
        matlabbatch{1}.spm.stats.fmri_spec.mask = {SPM.xM.VM.fname};
    end
    matlabbatch{1}.spm.stats.fmri_spec.cvi = SPM.xVi.form;
end

function [matlabbatch] = create_spm_sess(matlabbatch, iSess, sessFiles, regFile, covFile, SPM)
% Subfunction for adding sessions to the matlabbatch structure
    matlabbatch{1}.spm.stats.fmri_spec.sess(iSess).scans = sessFiles; %fix this
    matlabbatch{1}.spm.stats.fmri_spec.sess(iSess).cond = struct('name', {}, 'onset', {}, 'duration', {}, 'tmod', {}, 'pmod', {});
    matlabbatch{1}.spm.stats.fmri_spec.sess(iSess).multi = {regFile};
    matlabbatch{1}.spm.stats.fmri_spec.sess(iSess).regress = struct('name', {}, 'val', {});
    matlabbatch{1}.spm.stats.fmri_spec.sess(iSess).multi_reg = {covFile};
    matlabbatch{1}.spm.stats.fmri_spec.sess(iSess).hpf = SPM.xX.K(iSess).HParam;
end

function [matlabbatch] = estimate_spm(spmFile)
% Subfunction for creating a matlabbatch structure to estimate the SPM
    matlabbatch{1}.spm.stats.fmri_est.spmmat = {spmFile};
    matlabbatch{1}.spm.stats.fmri_est.method.Classical = 1;
end
