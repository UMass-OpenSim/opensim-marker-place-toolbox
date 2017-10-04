%-------------------------------------------------------------------------% 
% AutoPlace.m
% 
% This file is a wrapper script which performs an automated marker 
% placement algorithm on a scaled OpenSim musculoskeletal walking model. 
% This wrapper is used for subjects with unilateral transtibial amputation.
% It requires a starting .osim model with markers, .trc marker data from one 
% walking trial (single stride), and an inverse kinematics setup .xml.
% Modify the fields in this template for the specific subject model being 
% used.
% 
% Before running, ensure the following folders are in the parent working
% directory:
%     IKSetup         Contains generic setup file and trial specific setup 
%                     files are written
%     MarkerData      Contains marker trajectory files for each trial
%     -  CAL          Standing calibration
%     -  PREF         Preferred walking speed trials
%     Models          Contains the models used in IK
%     -  AutoPlaced   Where output models will be written
%     -  Scaled       Where input model is stored
%
% Before running, modify script options cell appropriately.
% 
% Written by Mark Price 07/2017
% Last modified 10/2/2017
%
%-------------------------------------------------------------------------%

close all
clear all
clc

%% Set directories and subject information

global myModel fileID iteration

import org.opensim.modeling.*

% Create strings for the subject name and type of prosthesis. For file naming and labeling only.
subject = 'A01';
prosType = 'passive';

% Setup folder paths for organization and use between machines
ikSetupPath = ([pwd '\IKSetup\']);
genericSetupForIK = 'A01_Setup_IK.xml';
genericSetupForIKStatic = 'A01_Setup_IK_Static.xml';
trcDataDir = ([pwd '\MarkerData\PREF']);
trcDataDirStatic = ([pwd '\MarkerData\CAL']);
inputModelDir = ([pwd '\Models\Scaled\']);
modelDir = ([pwd '\Models\AutoPlaced\']);

% Specify input and worker filenames
modelFile = [pwd '\autoPlaceWorker.osim']; % Name of the 'worker' model file which is updated with each iteration
outputMotionFile = [pwd '\autoPlaceWorker.mot']; % Name of the 'worker' output motion file which is updated with each iteration
markerFile = [trcDataDir '\A01_PREF_T0015.trc']; % Name of the experimental walking marker data .trc file (single trial)
markerFileStatic = [trcDataDirStatic '\Standing_Cal_SL_Passive0001.trc']; % Name of the standing cal marker data .trc file

% Update IK setup file to reflect current file paths for walking trial
ikTool = InverseKinematicsTool([ikSetupPath genericSetupForIK]);
factorProp  = ikTool.getPropertyByName('model_file');
PropertyHelper.setValueString(modelFile,factorProp); % Set the .osim model file path in the setup .xml
factorProp  = ikTool.getPropertyByName('marker_file');
PropertyHelper.setValueString(markerFile,factorProp); % Set the .trc marker file path in the setup .xml
factorProp  = ikTool.getPropertyByName('output_motion_file');
PropertyHelper.setValueString(outputMotionFile,factorProp); % Set the model path in the setup .xml
ikTool.print([ikSetupPath genericSetupForIK]);

% Update IK setup file to reflect current file paths for standing calibration
ikToolStatic = InverseKinematicsTool([ikSetupPath genericSetupForIKStatic]);
factorProp  = ikToolStatic.getPropertyByName('model_file');
PropertyHelper.setValueString(modelFile,factorProp); % Set the .osim model file path in the setup .xml
factorProp  = ikToolStatic.getPropertyByName('marker_file');
PropertyHelper.setValueString(markerFileStatic,factorProp); % Set the .trc marker file path in the setup .xml
factorProp  = ikToolStatic.getPropertyByName('output_motion_file');
PropertyHelper.setValueString(outputMotionFile,factorProp); % Set the model path in the setup .xml
ikToolStatic.print([ikSetupPath genericSetupForIKStatic]);

% Store names of the model markers in cell arrays. Each run of the
% algorithm will require one cell array of marker names to adjust. Store
% sets of markers to be placed separately or under different conditions in 
% separate arrays.

% rob = "rest of body". All markers not attached to affected limb.
robMarkerNames = {'R_AC','L_AC','R_ASIS','L_ASIS','R_PSIS', ...
            'L_PSIS','R_THIGH_PROX_POST','R_THIGH_PROX_ANT', ...
            'R_THIGH_DIST_POST','R_THIGH_DIST_ANT','R_SHANK_PROX_ANT', ...
            'R_SHANK_PROX_POST','R_SHANK_DIST_POST','R_SHANK_DIST_ANT', ...
            'R_HEEL_SUP','R_HEEL_MED','R_HEEL_LAT','R_TOE','R_1ST_MET', ...
            'R_5TH_MET'};
        
% Markers attached to the prosthesis        
prosMarkerNames = {'L_SHANK_PROX_POST', ...
            'L_SHANK_PROX_ANT','L_SHANK_DIST_ANT','L_SHANK_DIST_POST', ...
            'L_HEEL_SUP','L_HEEL_MED','L_HEEL_LAT', ...
            'L_TOE','L_1ST_MET','L_5TH_MET'};
        
% RoB markers and prosthesis markers in one set.        
robProsMarkerNames = {'R_AC','L_AC','R_ASIS','L_ASIS','R_PSIS', ...
            'L_PSIS','R_THIGH_PROX_POST','R_THIGH_PROX_ANT', ...
            'R_THIGH_DIST_POST','R_THIGH_DIST_ANT','R_SHANK_PROX_ANT', ...
            'R_SHANK_PROX_POST','R_SHANK_DIST_POST','R_SHANK_DIST_ANT', ...
            'R_HEEL_SUP','R_HEEL_MED','R_HEEL_LAT','R_TOE','R_1ST_MET', ...
            'R_5TH_MET','L_SHANK_PROX_POST', ...
            'L_SHANK_PROX_ANT','L_SHANK_DIST_ANT','L_SHANK_DIST_POST', ...
            'L_HEEL_SUP','L_HEEL_MED','L_HEEL_LAT', ...
            'L_TOE','L_1ST_MET','L_5TH_MET'};

% Thigh markers on the prosthesis side        
prosThighMarkerNames = {'L_THIGH_PROX_POST','L_THIGH_PROX_ANT', ...
            'L_THIGH_DIST_POST','L_THIGH_DIST_ANT'};
        
% Names of model joints whose placements (location and orientation) in the 
% parent segment are also to be optimized
jointNames = {'socket'};
socketAlignment = {'SOCKET_JOINT_LOC_IN_BODY','SOCKET_JOINT_ORIENT'};

%% Setup and run initial RoB marker placement

iteration = 1;

% Create new file for log of marker search
fileID = fopen(['coarseMarkerSearch_log_' subject '_' prosType '_' char(datetime('now','TimeZone','local','Format','d-MMM-y_HH.mm.ss_Z')) '.txt'], 'w');

newName = [subject '_' prosType '_ROBPROS_auto_marker_place_' char(datetime('now','TimeZone','local','Format','d-MMM-y_HH.mm.ss')) '.osim'];
newModelName = [modelDir newName];  % set name for new .osim model created after placing markers

model = 'A01_Left_TTAmp_SR1_scaled.osim'; % Provide name of input model (scaled, standard marker placement) 
myModel = [inputModelDir model];

% Set model and algorithm options:
options.IKsetup = [ikSetupPath genericSetupForIK];  % IK setup file
options.model = myModel;                            % Input model
options.subjectMass = 67.3046;                      % Subject mass in kg
options.newName = newModelName;                     % Output model name
options.modelWorker = modelFile;                    % Worker model name
options.motionWorker = outputMotionFile;            % Output motion name

% Choose the lock state of each coordinate in the socket joint
options.txLock = false;
options.tyLock = false;
options.tzLock = false;
options.flexLock = false;
options.adducLock = false;
options.rotLock = false;

% Choose which set of markers is being placed.
options.markerNames = robProsMarkerNames;

% Choose which model joints are being placed.
options.jointNames = {};

% List marker coordinates to be locked - algorithm cannot move them from
% hand-picked location:
options.fixedMarkerCoords = {'L_HEEL_SUP y','L_TOE x','L_TOE y','L_TOE z'}; 
% options.fixedMarkerCoords = {'STERN x','STERN y','STERN z','L_HEEL_SUP y','L_TOE x','L_TOE y','L_TOE z'}; % use sternum marker if available
% options.fixedMarkerCoords = {'R_AC x','L_AC x','L_HEEL_SUP y','L_TOE x','L_TOE y','L_TOE z'};% can optionally lock AC markers in X if no sternum

% Specify frame from .trc file at which socket flexion should be minimized
% (only applies for prosthesis-side thigh markers and socket joint placement)
options.flexionZero = 40; 

% Flag to tell algorithm to minimize socket flexion and pistoning at
% specific points during stride in addition to marker error.
options.optZerosFlag = false;

% Specify marker search convergence threshold. All markers must move less 
% than convThresh mm from start position at each markerset iteration to 
% converge. If 1, a full pass with no marker changes must take place:
options.convThresh = 1; 

tic     %Start timer

X_robpros = coarseMarkerSearch(options);    % Run autoplace algorithm

% Save output model to specified name.
model = Model('autoPlaceWorker.osim');
model.initSystem();
model.print(newModelName);

% Set name of input model for next phase as output model of this phase
preSocketJointModel = newModelName; 

%% Setup and run thigh cluster and socket joint placement

% % Set this to desired input model if running this section independently
% preSocketJointModel = [modelDir 'A01_passive_ROBPROS_auto_marker_place.osim'];

myModel = preSocketJointModel;
newName = [subject '_' prosType '_FULL_auto_marker_place_4DOF' char(datetime('now','TimeZone','local','Format','d-MMM-y_HH.mm.ss')) '.osim'];
newModelName = [modelDir newName];  % set name for new .osim model created after placing markers

% Set model and algorithm options:
options.IKsetup = [ikSetupPath genericSetupForIK];  % IK setup file
options.model = myModel;                            % Input model
options.subjectMass = 67.3046;                      % Subject mass in kg
options.newName = newModelName;                     % Output model name
options.modelWorker = modelFile;                    % Worker model name
options.motionWorker = outputMotionFile;            % Output motion name

% Choose the lock state of each coordinate in the socket joint
options.txLock = true;
options.tyLock = false;
options.tzLock = true;
options.flexLock = false;
options.adducLock = false;
options.rotLock = false;

% Choose which set of markers is being placed.
options.markerNames = prosThighMarkerNames;

% Choose which model joints are being placed.
options.jointNames = jointNames;

% List marker coordinates to be locked - algorithm cannot move them from
% hand-picked location:
% options.fixedMarkerCoords = {'socket_JOINT_CENTER z'};
options.fixedMarkerCoords = {'socket_JOINT_CENTER z','socket_JOINT_ORIENT x','socket_JOINT_ORIENT y'};

% Specify frame from .trc file at which socket flexion should be minimized
% (only applies for prosthesis-side thigh markers and socket joint placement)
options.flexionZero = 40; 

% Flag to tell algorithm to minimize socket flexion and pistoning at
% specific points during stride in addition to marker error.
options.optZerosFlag = true;

% Specify marker search convergence threshold. All markers must move less 
% than convThresh mm from start position at each markerset iteration to 
% converge. If 1, a full pass with no marker changes must take place:
options.convThresh = 1; 

X_prosThigh = coarseMarkerSearch(options);

% Save output model to specified name.
model = Model('autoPlaceWorker.osim');
model.initSystem();
model.print(newModelName);

fclose(fileID);     % Close log.