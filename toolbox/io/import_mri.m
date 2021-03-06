function [BstMriFile, sMri] = import_mri(iSubject, MriFile, FileFormat, isInteractive)
% IMPORT_MRI: Import a MRI file in a subject of the Brainstorm database
% 
% USAGE: [BstMriFile, sMri] = import_mri(iSubject, MriFile, FileFormat='ALL', isInteractive=0)
%
% INPUT:
%    - iSubject  : Indice of the subject where to import the MRI
%                  If iSubject=0 : import MRI in default subject
%    - MriFile   : Full filename of the MRI to import (format is autodetected)
%                  => if not specified : file to import is asked to the user
%    - FileFormat : String, one on the file formats in in_mri
%    - isInteractive : if 1, importation will be interactive (MRI is displayed after loading)
% OUTPUT:
%    - BstMriFile : Full path to the new file if success, [] if error

% @=============================================================================
% This function is part of the Brainstorm software:
% http://neuroimage.usc.edu/brainstorm
% 
% Copyright (c)2000-2017 University of Southern California & McGill University
% This software is distributed under the terms of the GNU General Public License
% as published by the Free Software Foundation. Further details on the GPLv3
% license can be found at http://www.gnu.org/copyleft/gpl.html.
% 
% FOR RESEARCH PURPOSES ONLY. THE SOFTWARE IS PROVIDED "AS IS," AND THE
% UNIVERSITY OF SOUTHERN CALIFORNIA AND ITS COLLABORATORS DO NOT MAKE ANY
% WARRANTY, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF
% MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, NOR DO THEY ASSUME ANY
% LIABILITY OR RESPONSIBILITY FOR THE USE OF THIS SOFTWARE.
%
% For more information type "brainstorm license" at command prompt.
% =============================================================================@
%
% Authors: Francois Tadel, 2008-2016

% ===== Parse inputs =====
if (nargin < 3) || isempty(FileFormat)
    FileFormat = 'ALL';
end
if (nargin < 4) || isempty(isInteractive)
    isInteractive = 0;
end
% Initialize returned variables
BstMriFile = [];
sMri = [];
% Get Protocol information
ProtocolInfo     = bst_get('ProtocolInfo');
ProtocolSubjects = bst_get('ProtocolSubjects');
% Default subject
if (iSubject == 0)
	sSubject = ProtocolSubjects.DefaultSubject;
% Normal subject 
else
    sSubject = ProtocolSubjects.Subject(iSubject);
end


%% ===== SELECT MRI FILE =====
% If MRI file to load was not defined : open a dialog box to select it
if isempty(MriFile)    
    % Get last used directories
    LastUsedDirs = bst_get('LastUsedDirs');
    % Get last used format
    DefaultFormats = bst_get('DefaultFormats');
    if isempty(DefaultFormats.MriIn)
        DefaultFormats.MriIn = 'ALL';
    end
    % Get MRI file
    [MriFile, FileFormat] = java_getfile( 'open', ...
        'Import MRI...', ...              % Window title
        LastUsedDirs.ImportAnat, ...      % Default directory
        'single', 'files', ...            % Selection mode
        bst_get('FileFilters', 'mri'), ...
        DefaultFormats.MriIn);
    % If no file was selected: exit
    if isempty(MriFile)
        return
    end
    % Save default import directory
    LastUsedDirs.ImportAnat = bst_fileparts(MriFile);
    bst_set('LastUsedDirs', LastUsedDirs);
    % Save default import format
    DefaultFormats.MriIn = FileFormat;
    bst_set('DefaultFormats',  DefaultFormats);
end
    
    
%% ===== LOAD MRI FILE =====
bst_progress('start', 'Import MRI', ['Loading file "' MriFile '"...']);
% Load MRI
sMri = in_mri(MriFile, FileFormat, isInteractive);
if isempty(sMri)
    bst_progress('stop');
    return
end
% History: File name
sMri = bst_history('add', sMri, 'import', ['Import from: ' MriFile]);


%% ===== MANAGE MULTIPLE MRI =====
% Add new anatomy
iAnatomy = length(sSubject.Anatomy) + 1;
% If add an extra MRI: read the first one to check that they are compatible
if (iAnatomy > 1)
    % Load the reference MRI (the first one)
    refMriFile = sSubject.Anatomy(1).FileName;
    sMriRef = in_mri_bst(refMriFile);
    % If some transformation where made to the intial volume: apply them to the new one ?
    if isfield(sMriRef, 'InitTransf') && ~isempty(sMriRef.InitTransf) && any(ismember(sMriRef.InitTransf(:,1), {'permute', 'flipdim'}))
        if ~isInteractive || java_dialog('confirm', ['A transformation was applied to the reference MRI.' 10 10 'Do you want to apply the same transformation to this new volume?' 10 10], 'Import MRI')
            % Apply step by step all the transformations that have been applied to the original MRI
            for it = 1:size(sMriRef.InitTransf,1)
                ttype = sMriRef.InitTransf{it,1};
                val   = sMriRef.InitTransf{it,2};
                switch (ttype)
                    case 'permute'
                        sMri.Cube = permute(sMri.Cube, val);
                        sMri.Voxsize = sMri.Voxsize(val);
                    case 'flipdim'
                        sMri.Cube = bst_flip(sMri.Cube, val(1));
                end
            end
            % Modifying the volume disables the option "Reslice"
            isResliceDisabled = 1;
        else
            isResliceDisabled = 0;
        end
    else
        isResliceDisabled = 0;
    end
    % Get volumes dimensions
    refSize = size(sMriRef.Cube);
    newSize = size(sMri.Cube);
    isSameSize = all(refSize == newSize) && all(sMriRef.Voxsize == sMriRef.Voxsize);
    % Initialize list of options to register this new MRI with the existing one
    strOptions = ['<HTML>How to register the new volume with the previous one?<BR>'];
    cellOptions = {};
    % Use the NIfTI vox2ras transformation if available
    if isfield(sMriRef, 'InitTransf') && ~isempty(sMriRef.InitTransf) && any(ismember(sMriRef.InitTransf(:,1), 'vox2ras')) && ...
       isfield(sMri,    'InitTransf') && ~isempty(sMri.InitTransf)    && any(ismember(sMri.InitTransf(:,1),    'vox2ras')) && ...
       ~isResliceDisabled
        strOptions = [strOptions, '<BR>- <U><B>Reslice</B></U>:&nbsp;&nbsp;&nbsp;The two volumes are registered but not resliced, reslice the new volume.'];
        cellOptions{end+1} = 'Reslice';
    end
    % Register with the MNI transformation
    strOptions = [strOptions, '<BR>- <U><B>Register</B></U>:&nbsp;&nbsp;&nbsp;Compute the MNI transformation for both volumes, then register the new one.'];
    cellOptions{end+1} = 'Register';
    % Resample the new volume
    if ~isSameSize
        strOptions = [strOptions, '<BR>- <U><B>Resample</B></U>:&nbsp;&nbsp;&nbsp;Change the size and resolution of the new volume to match the previous one.'];
        cellOptions{end+1} = 'Resample';
    end
    % If the dimensions are the same: allow to keep the volume with no modifications
    if isSameSize
        strOptions = [strOptions, '<BR>- <U><B>Ignore</B></U>:&nbsp;&nbsp;&nbsp;The two volumes are already registered and resliced, do not edit the new volume.'];
        cellOptions{end+1} = 'Ignore';
    end
    
    % Ask what operation to perform with this MRI
    if isInteractive
        res = java_dialog('question', [strOptions '<BR><BR></HTML>'], 'Import MRI', [], cellOptions, 'Register');
    % In non-interactive mode: ignore if possible, or use the first option available
    else
        if ismember('Ignore', cellOptions)
            res = 'Ignore';
        else
            res = cellOptions{1};
        end
    end
    % User aborted the import
    if isempty(res)
        sMri = [];
        bst_progress('stop');
        return;
    end
    % Registration
    switch (res)
        case 'Reslice'
            % Register the new MRI on the existing one using the transformation in the input files (files already registered)
            iTransfRef = find(strcmpi(sMriRef.InitTransf(:,1), 'vox2ras'));
            iTransf    = find(strcmpi(sMri.InitTransf(:,1),    'vox2ras'));
            [sMri, errMsg] = mri_coregister(sMri, sMriRef, sMri.InitTransf{iTransf(1),2}, sMriRef.InitTransf{iTransfRef(1),2});
        case 'Register'
            % Register the new MRI on the existing one using the MNI transformation
            [sMri, errMsg] = mri_coregister(sMri, sMriRef);
        case 'Resample'
            % Resample the new MRI using the properties of the old one
            [sMri, Transf, errMsg] = mri_resample(sMri, size(sMriRef.Cube), sMriRef.Voxsize);
        case 'Ignore'
            errMsg = [];
    end
    % Stop in case of error
    if ~isempty(errMsg)
        bst_error(errMsg, [res ' MRI'], 0);
        sMri = [];
        bst_progress('stop');
        return;
    end
    % Copy the old SCS and NCS fields to the new file
    sMri.SCS = sMriRef.SCS;
    sMri.NCS = sMriRef.NCS;
end

%% ===== SAVE MRI IN BRAINSTORM FORMAT =====
% Add a Comment field in MRI structure, if it does not exist yet
if ~isfield(sMri, 'Comment')
    sMri.Comment = 'MRI';
end
% Use filename as comment
if (iAnatomy > 1) || isInteractive
    [fPath, fBase, fExt] = bst_fileparts(MriFile);
    sMri.Comment = file_unique(fBase, {sSubject.Anatomy.Comment});
end
% Get subject subdirectory
subjectSubDir = bst_fileparts(sSubject.FileName);
% Get imported base name
[tmp__, importedBaseName] = bst_fileparts(MriFile);
importedBaseName = strrep(importedBaseName, 'subjectimage_', '');
importedBaseName = strrep(importedBaseName, '_subjectimage', '');
% Produce a default anatomy filename
BstMriFile = bst_fullfile(ProtocolInfo.SUBJECTS, subjectSubDir, ['subjectimage_' importedBaseName '.mat']);
% Make this filename unique
BstMriFile = file_unique(BstMriFile);
% Save new MRI in Brainstorm format
sMri = out_mri_bst(sMri, BstMriFile);
% Clear memory
MriComment = sMri.Comment;

%% ===== STORE NEW MRI IN DATABASE ======
% New anatomy structure
sSubject.Anatomy(iAnatomy) = db_template('Anatomy');
sSubject.Anatomy(iAnatomy).FileName = file_short(BstMriFile);
sSubject.Anatomy(iAnatomy).Comment  = MriComment;
% Default anatomy: do not change
if isempty(sSubject.iAnatomy)
    sSubject.iAnatomy = iAnatomy;
end

% == Update database ==
% Default subject
if (iSubject == 0)
	ProtocolSubjects.DefaultSubject = sSubject;
% Normal subject 
else
    ProtocolSubjects.Subject(iSubject) = sSubject;
end
bst_set('ProtocolSubjects', ProtocolSubjects);


%% ===== UPDATE GUI =====
% Refresh tree
panel_protocols('UpdateNode', 'Subject', iSubject);
panel_protocols('SelectNode', [], 'subject', iSubject, -1 );
% Save database
db_save();
% Unload MRI (if a MRI with the same name was previously loaded)
bst_memory('UnloadMri', BstMriFile);


%% ===== MRI VIEWER =====
if isInteractive
    % First MRI: Edit fiducials
    if (iAnatomy == 1)
        % MRI Visualization and selection of fiducials (in order to align surfaces/MRI)
        hFig = view_mri(BstMriFile, 'EditMri');
        drawnow;
        bst_progress('stop');
%         % Display help message: ask user to select fiducial points
%         if (iAnatomy == 1)
%             jHelp = bst_help('MriSetup.html', 0);
%         else
%             jHelp = [];
%         end
        % Wait for the MRI Viewer to be closed
        if ishandle(hFig)
            waitfor(hFig);
        end
%         % Close help window
%         if ~isempty(jHelp)
%             jHelp.close();
%         end
    % Other volumes: Display registration
    else
        % Open the second volume as an overlay of the first one
        hFig = view_mri(refMriFile, BstMriFile);
        % Set the amplitude threshold to 50%
        panel_surface('SetDataThreshold', hFig, 1, 0.3);
    end
else
    bst_progress('stop');
end





    
