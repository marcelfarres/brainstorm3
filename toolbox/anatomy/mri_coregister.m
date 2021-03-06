function [sMriReg, errMsg] = mri_coregister(MriFileSrc, MriFileRef)
% MRI_COREGISTER: Compute the MNI transformation on both input volumes, then register the first on the second.
%
% USAGE:  [MriFileReg, errMsg] = mri_coregister(MriFileSrc, MriFileRef)
%            [sMriReg, errMsg] = mri_coregister(sMriSrc,    sMriRef)
%
% INPUTS:
%    - MriFileSrc : Relative path to the Brainstorm MRI file to register
%    - MriFileRef : Relative path to the Brainstorm MRI file used as a reference
%    - sMriSrc    : Brainstorm MRI structure to register (fields Cube, Voxsize, SCS, NCS...)
%    - sMriRef    : Brainstorm MRI structure used as a reference
%
% OUTPUTS:
%    - MriFileReg : Relative path to the new Brainstorm MRI file (containing the structure sMriReg)
%    - sMriReg    : Brainstorm MRI structure with the registered volume
%    - errMsg     : Error messages if any

% @=============================================================================
% This function is part of the Brainstorm software:
% http://neuroimage.usc.edu/brainstorm
% 
% Copyright (c)2000-2016 University of Southern California & McGill University
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
% Authors: Francois Tadel, 2016

% ===== PARSE INPUTS =====
sMriReg = [];
errMsg = [];
% Progress bar
isProgress = bst_progress('isVisible');
if ~isProgress
    bst_progress('start', 'MRI register', 'Loading input volumes...');
end
% USAGE: mri_coregister(sMriSrc, sMriRef)
if isstruct(MriFileSrc)
    sMriSrc = MriFileSrc;
    sMriRef = MriFileRef;
    MriFileSrc = [];
    MriFileRef = [];
% USAGE: mri_coregister(MriFileSrc, MriFileRef)
elseif ischar(MriFileSrc)
    sMriSrc = in_mri_bst(MriFileSrc);
    sMriRef = in_mri_bst(MriFileRef);
else
    error('Invalid call.');
end


% ===== COMPUTE MNI TRANSFORMATIONS =====
% Source MRI
if isfield(sMriSrc, 'NCS') && isfield(sMriSrc.NCS, 'R') && isfield(sMriSrc.NCS, 'T') && ~isempty(sMriSrc.NCS.R) && ~isempty(sMriSrc.NCS.T)
    TransfSrc = [sMriSrc.NCS.R, sMriSrc.NCS.T; 0 0 0 1];
else
    TransfSrc = mri_register_maff(sMriSrc);
end
% Reference MRI
if isfield(sMriRef, 'NCS') && isfield(sMriRef.NCS, 'R') && isfield(sMriRef.NCS, 'T') && ~isempty(sMriRef.NCS.R) && ~isempty(sMriRef.NCS.T)
    TransfRef = [sMriRef.NCS.R, sMriRef.NCS.T; 0 0 0 1];
else
    TransfRef = mri_register_maff(sMriRef);
end

% ===== INTERPOLATE MRI VOLUME =====
bst_progress('text', 'Interpolating volume...');
% Original position vectors
X1 = ((0:size(sMriSrc.Cube,1)-1) + 0.5) .* sMriSrc.Voxsize(1);
Y1 = ((0:size(sMriSrc.Cube,2)-1) + 0.5) .* sMriSrc.Voxsize(2);
Z1 = ((0:size(sMriSrc.Cube,3)-1) + 0.5) .* sMriSrc.Voxsize(3);
% Reference position vectors
X2 = ((0:size(sMriRef.Cube,1)-1) + 0.5) .* sMriRef.Voxsize(1);
Y2 = ((0:size(sMriRef.Cube,2)-1) + 0.5) .* sMriRef.Voxsize(2);
Z2 = ((0:size(sMriRef.Cube,3)-1) + 0.5) .* sMriRef.Voxsize(3);
% Mesh grids
[Xgrid2, Ygrid2, Zgrid2] = meshgrid(Y2, X2, Z2);
% Apply final transformation: reference MRI => SPM/MNI => original MRI
allGrid = [Ygrid2(:)'; Xgrid2(:)'; Zgrid2(:)'; ones(size(Xgrid2(:)))'];
allGrid = inv(TransfSrc) * TransfRef * allGrid;
Xgrid2 = reshape(allGrid(2,:), size(Xgrid2));
Ygrid2 = reshape(allGrid(1,:), size(Ygrid2));
Zgrid2 = reshape(allGrid(3,:), size(Zgrid2));
% Interpolate volume
newCube = uint8(interp3(Y1, X1, Z1, double(sMriSrc.Cube), Xgrid2, Ygrid2, Zgrid2, 'spline', 0));


% ===== TRANSFORM COORDINATES =====
% Initialize transformed structure
sMriReg         = sMriSrc;
sMriReg.Cube    = newCube;
sMriReg.Voxsize = sMriRef.Voxsize;
% Apply transformation: original MRI => SPM/MNI => reference MRI
Transf = inv(TransfRef) * TransfSrc;
% Update fiducials
if isfield(sMriSrc, 'SCS') && isfield(sMriSrc.SCS, 'NAS') && ~isempty(sMriSrc.SCS.NAS)
    sMriReg.SCS.NAS = (Transf(1:3,1:3) * sMriSrc.SCS.NAS' + Transf(1:3,4))';
end
if isfield(sMriSrc, 'SCS') && isfield(sMriSrc.SCS, 'LPA') && ~isempty(sMriSrc.SCS.LPA)
    sMriReg.SCS.LPA = (Transf(1:3,1:3) * sMriSrc.SCS.LPA' + Transf(1:3,4))';
end
if isfield(sMriSrc, 'SCS') && isfield(sMriSrc.SCS, 'RPA') && ~isempty(sMriSrc.SCS.RPA)
    sMriReg.SCS.RPA = (Transf(1:3,1:3) * sMriSrc.SCS.RPA' + Transf(1:3,4))';
end
if isfield(sMriSrc, 'NCS') && isfield(sMriSrc.NCS, 'AC') && ~isempty(sMriSrc.NCS.AC)
    sMriReg.NCS.AC = (Transf(1:3,1:3) * sMriSrc.NCS.AC' + Transf(1:3,4))';
end
if isfield(sMriSrc, 'NCS') && isfield(sMriSrc.NCS, 'PC') && ~isempty(sMriSrc.NCS.PC)
    sMriReg.NCS.PC = (Transf(1:3,1:3) * sMriSrc.NCS.PC' + Transf(1:3,4))';
end
if isfield(sMriSrc, 'NCS') && isfield(sMriSrc.NCS, 'IH') && ~isempty(sMriSrc.NCS.IH)
    sMriReg.NCS.IH = (Transf(1:3,1:3) * sMriSrc.NCS.IH' + Transf(1:3,4))';
end
% Update SCS transformation
if isfield(sMriSrc, 'SCS') && isfield(sMriSrc.SCS, 'R') && ~isempty(sMriSrc.SCS.R) && isfield(sMriSrc.SCS, 'T') && ~isempty(sMriSrc.SCS.T)
    % Compute new transformation matrices to SCS
    Tscs = [sMriSrc.SCS.R, sMriSrc.SCS.T; 0 0 0 1] * inv(Transf);
    % Report in the new MRI structure
    sMriReg.SCS.R = Tscs(1:3,1:3);
    sMriReg.SCS.T = Tscs(1:3,4);
end    
% Update MNI transformation
if isfield(sMriSrc, 'NCS') && isfield(sMriSrc.NCS, 'R') && ~isempty(sMriSrc.NCS.R) && isfield(sMriSrc.NCS, 'T') && ~isempty(sMriSrc.NCS.T)
    % Compute new transformation matrices to SCS
    Tncs = [sMriSrc.NCS.R, sMriSrc.NCS.T; 0 0 0 1] * inv(Transf);
    % Report in the new MRI structure
    sMriReg.NCS.R = Tncs(1:3,1:3);
    sMriReg.NCS.T = Tncs(1:3,4);
end


% ===== SAVE NEW FILE =====
% Save output
if ~isempty(MriFileSrc)
    bst_progress('text', 'Saving new file...');
    % Get subject
    [sSubject, iSubject, iMri] = bst_get('MriFile', MriFileSrc);
    % Update comment
    sMriReg.Comment = [sMriReg.Comment, '_coreg'];
    sMriReg.Comment = file_unique(sMriReg.Comment, {sSubject.Anatomy.Comment});
    % Add history entry
    sMriReg = bst_history('add', sMriReg, 'resample', ['MRI co-registered on default file: ' MriFileRef]);
    % Save new file
    newMriFile = file_unique(strrep(file_fullpath(MriFileSrc), '.mat', '_resample.mat'));
    shorMriFile = file_short(newMriFile);
    % Save new MRI in Brainstorm format
    sMriReg = out_mri_bst(sMriReg, newMriFile);

    % Register new MRI
    iAnatomy = length(sSubject.Anatomy) + 1;
    sSubject.Anatomy(iAnatomy) = db_template('Anatomy');
    sSubject.Anatomy(iAnatomy).FileName = shorMriFile;
    sSubject.Anatomy(iAnatomy).Comment  = sMriReg.Comment;
    % Update subject structure
    bst_set('Subject', iSubject, sSubject);
    % Refresh tree
    panel_protocols('UpdateNode', 'Subject', iSubject);
    panel_protocols('SelectNode', [], 'anatomy', iSubject, iAnatomy);
    % Save database
    db_save();
    % Return output filename
    sMriReg = shorMriFile;
end
% Close progress bar
if ~isProgress
    bst_progress('stop');
end

