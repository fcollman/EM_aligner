function [L, tIds, PM, pm_mx, sectionId, z] = load_point_matches(nfirst, nlast, rc, pm, nbr, min_points, xs_weight)
% Input: nfirst and nlast are zvalue of sections in rc
%        rc and pm are structs with specifications for accessing
%        collections of tile-specs and point-matches (that are related)
% Output: Msection object L with field pm (which is a struct with fields M, adj, W and np), and tileIds
%         M: is a cell array of size npx2, e.g. a set of point matches is given by M{1,1} for xy of
%         the first set of points and M{1,2} for xy of the matching points
%
% requires a starting value for section zvalues (nfirst) and the zvalue of
% the last section (nlast). nfirst and nlast can be the same value
% First a sectionID list is created in the order of zvalues (most of those
% are already ordered, but we need to be sure). This is why we need rc.
% Second all point matches within the sections and across sections will be
% downloaded from the pm database.
% % Example rc and pm
% % rc.stack = 'v9_acquire_LC_merged_2';
% % rc.owner='flyTEM';
% % rc.project='FAFB00';
% % rc.server='http://tem-services.int.janelia.org:8080/render-ws/v1';
% %
% % pm.server = 'http://tem-services.int.janelia.org:8080/render-ws/v1';
% % pm.owner  = 'flyTEM';
% % pm.match_collection = 'v9_1';
%
% Author: Khaled Khairy. Janelia Research Campus 2016
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if nargin<5, nbr = 4;end  % number of neighbors to check
if nargin<6, min_points = 0;end
if nargin<7, xs_weight = 1;end
%% get the list of zvalues and section ids within the z range between nfirst and nlast (inclusive)
urlChar = sprintf('%s/owner/%s/project/%s/stack/%s/sectionData', ...
    rc.baseURL, rc.owner, rc.project, rc.stack);
js = webread(urlChar);
sectionId = {js(:).sectionId};
[z, ia]   = sort(([js(:).z]));
sectionId = sectionId(ia);


indx = find(z>=nfirst & z<=nlast);
sectionId = sectionId(indx);% determine the sectionId list we will work with
z         = z(indx);        % determine the zvalues (this is also the spatial order)

% we need unique values, and we need to know how many sectionId's correspond to each unique z value
% usually it is one, but sometimes we have hi/lo dose or other regions
[zu, ia, ic] = unique(z);
count = 1;
sID = {};
for zix = 1:numel(zu)
    ns(zix) =  numel(find(ic==zix));
    vec = {};
    for six = 1:ns(zix)
        vec{six} = sectionId{count};
        sID{zix} = vec; 
        count = count + 1;
    end
end
% [z, ia] = sort(z);
% sectionId = sectionId(ia);
%% get a list of all tiles for those sections


%  % <sosi---- > this is how it should be done in the future --
%  instantiation using rc and z has already been implemented, see
%  Msection.m
%  parfor ix = 1:numel(z)
%      L(ix) = Msection(rc,z(ix));
%  end
%  L = concatenate_tiles(L); % concatenate all sections
%  %%%% sosi />


options = weboptions;
options.Timeout = 20;
clear t;
parfor_progress(numel(zu));
parfor ix = 1:numel(zu)
    urlChar = sprintf('%s/owner/%s/project/%s/stack/%s/z/%d/tile-specs', ...
        rc.baseURL, rc.owner, rc.project, rc.stack, zu(ix));
    j = webread(urlChar, options);
    jt = tile;
    for jix = 1:numel(j)
        jt(jix) = tile(j(jix));
        jt(jix).z = zu(ix);
    end
    t(ix).jt = jt;
    parfor_progress;
end
parfor_progress(0);




% concatenate all tile ids
tIds = {};
tiles = [];
for ix = 1:numel(zu)
    tIds = [tIds {t(ix).jt.renderer_id}];
    tiles = [tiles t(ix).jt];
end

% loop over tiles to set tile id
parfor ix = 1:numel(tiles)
    tiles(ix).id = ix;
end
L = Msection(tiles);
L = update_tile_sources(L, rc);




%%%%%%%%%%%% check consistency
% check that all renderer_ids in L are unique (this means that all tiles are unique)
% if not then flag which ones are not
rids = {L.tiles(:).renderer_id};
[un idx_last idx] = unique(rids);
uqindx = accumarray(idx(:),(1:length(idx))',[],@(x) {sort(x)});
for ix = 1:numel(uqindx)
    if numel(uqindx{ix})>1, 
        id = L.tiles(uqindx{ix}(1)).renderer_id;
        disp([num2str(numel(uqindx{ix})) ' copies of id: ' id ' found.']);
    end
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%





% map renderer ids to their index position in L
clear count_vec ;
clear id_vec ;
parfor ix = 1:numel(tIds)
    count_vec(ix)= {ix};
    id_vec(ix) = tIds(ix);%tIds{ix};
end
map_id = containers.Map(id_vec, count_vec);

%% get point matches for each section
PM.M = {};
PM.adj = [];
PM.W = {};
PM.np = [];
n1 = [];
for ix = 1:numel(ns)
    %disp(ix);
    count = 1;
    n1(ix) = 0;
    for six = 1:ns(ix)
        %disp([six count]);
        urlChar = sprintf('%s/owner/%s/matchCollection/%s/group/%s/matchesWithinGroup', ...
            pm.server, pm.owner, pm.match_collection, sID{ix}{six});
        try
            jj = webread(urlChar, options);
        catch err_ip_address
            pause(1);
            jj = webread(urlChar,options); % try again
        end
        
        n1(ix) = n1(ix) + numel(jj);
        for jix = 1:numel(jj)
            if size(jj(jix).matches.p',1)>=min_points
                if isKey(map_id, jj(jix).pId) && isKey(map_id, jj(jix).qId)
                    PM(ix).M{count,1}   = jj(jix).matches.p';
                    PM(ix).M{count,2}   = jj(jix).matches.q';
                    PM(ix).adj(count,:) = [map_id(jj(jix).pId) map_id(jj(jix).qId)];
                    PM(ix).W{count,1}     = jj(jix).matches.w';         % relative weights of point matches within this group
                    PM(ix).np(count)    = size(jj(jix).matches.p',1);
                    count = count + 1;
                end
            end
        end
    end
end


%% SOSI: --- concatenate PM and xPM in the order that will be used for filling A in the solution
% the code below only allows up to three neighbors
% [xPM2, n2] = get_cross_section_pm(2, pm, sectionId, map_id, min_points, xs_weight);%% get point matches to immediate neighbor
% [xPM3, n3] = get_cross_section_pm(3, pm, sectionId, map_id, min_points, xs_weight);%% get point matches to immediate neighbor
% %[xPM4, n4] = get_cross_section_pm(4, pm, sectionId, map_id, min_points, xs_weight);%% get point matches to immediate neighbor
% 
% clear M adj W np;
% for ix = 1:numel(z)
%     
%     if ix ==1
%         M   = PM(ix).M;
%         adj = PM(ix).adj;
%         W   = PM(ix).W;
%         np = PM(ix).np(:);
%         
%     elseif ix ==2
%         M   = [M;   xPM2(ix-1).M;       PM(ix).M];
%         adj = [adj; xPM2(ix-1).adj;     PM(ix).adj];
%         W   = [W;   xPM2(ix-1).W;       PM(ix).W];
%         np =  [np;  xPM2(ix-1).np(:);   PM(ix).np(:)];
%         
%     elseif numel(xPM3)>=(ix-2)
%         M   = [M;   xPM3(ix-2).M;       xPM2(ix-1).M;      PM(ix).M];
%         adj = [adj; xPM3(ix-2).adj;     xPM2(ix-1).adj;    PM(ix).adj];
%         W   = [W;   xPM3(ix-2).W;       xPM2(ix-1).W;      PM(ix).W];
%         np =  [np;  xPM3(ix-2).np(:);   xPM2(ix-1).np(:);  PM(ix).np(:)];
%     else
%         M   = [M;   xPM2(ix-1).M;       PM(ix).M];
%         adj = [adj; xPM2(ix-1).adj;     PM(ix).adj];
%         W   = [W;   xPM2(ix-1).W;       PM(ix).W];
%         np =  [np;  xPM2(ix-1).np(:);   PM(ix).np(:)];
%     end
% end
% 
% pm_mx = diag(n1);
% if ~sum(n2==0) pm_mx = pm_mx + diag(n2,1);end
% if ~sum(n3==0) pm_mx = pm_mx + diag(n3,2);end



%% obtain cross-section point-matches
xPM = {};
n   = {};
for pmix = 1:nbr
    [xPM{pmix}, n{pmix}] = get_cross_section_pm(pmix+1, pm, sID, map_id, min_points, xs_weight);%% get point matches to immediate neighbor
end
M   = [];
adj = [];
W   = [];
np = [];
for ix = 1:numel(zu)   % loop over sections
    %disp(ix);
    M = [M;PM(ix).M];
    adj = [adj;PM(ix).adj];
    W   = [W;PM(ix).W];
    np   = [np;PM(ix).np(:)];
    for nix = 1:nbr   % loop over neighboring sections
        %disp([ix nix]);
        if  ~(numel(xPM{nix})==1 && isempty(xPM{nix}.M))
            if numel(xPM{nix})>=ix
                if ~isempty(xPM{nix}(ix).M)
                    M = [M;xPM{nix}(ix).M];
                    adj = [adj;xPM{nix}(ix).adj];
                    W = [W;xPM{nix}(ix).W];
                    np = [np;xPM{nix}(ix).np(:)];
                end
            end
        end
    end
end

L.pm.M = M;
L.pm.adj = adj;
L.pm.W = W;
L.pm.np = np;

%% %%%%%%%%%%%%%%%%%%%%%%%%% diagnostics %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% section adjacency point-match count matrix
pm_mx = diag(n1);
for nbrix = 1:nbr
    if ~isempty(n{nbrix})
        if ~(sum(n{nbrix}(:,1))==0),
            pm_mx = pm_mx + diag(n{nbrix}(:,1),nbrix);
        end
    end
end

%% %%%%%%%%%%%%%%%%%%%%%%%%%% Check consistency %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if any(sum(pm_mx)==0), disp('Warning: defective pm connectivity matrix');end
% L.pm.adj are unique: report error if not
% --------- sosi: invesitgate how duplicates could arise in the first place
[bb, indx] = unique(L.pm.adj,'rows');
if ~(size(bb,1)==size(L.pm.adj,1))
    error('Rows in L.pm.adj should be unique');
end



% All renderer_id pairs must correspond to an adjacency pair: if not then report error
L.G = graph(L.pm.adj(:,1), L.pm.adj(:,2), L.pm.np, {L.tiles(:).renderer_id});
CC = table2cell(L.G.Edges(:,1));
nCC = size(CC,1);
C = [CC{:}];
%C = reshape(C, nCC, 2);
C1 = C(1:2:end);
C2 = C(2:2:end);
Lmap_renderer_id = L.map_renderer_id;
Lpmadj = L.pm.adj;
for tix = 1:numel(C1)
    indxL      = find(ismember(Lpmadj,[Lmap_renderer_id(C1{tix}) Lmap_renderer_id(C2{tix})],'rows'));
    if isempty(indxL),
        indxL      = find(ismember(Lpmadj,[Lmap_renderer_id(C2{tix}) Lmap_renderer_id(C1{tix})],'rows'));
        % swap the two in this case
        temp = L.pm.adj(indx,1);L.pm.adj(indx,1) = L.pm.adj(indx,2);L.pm.adj(indx,2) = temp;
        temp = L.pm.M{indxL,1};L.pm.M{indxL,1} = L.pm.M{indxL,2};L.pm.M{indxL,2} = temp;
    end
    if isempty(indxL),
        disp(tix);
        disp([C1{tix} ' ' C2{tix}]);
        disp([Lmap_renderer_id(C1{tix}) Lmap_renderer_id(C2{tix})])
        error('indxL should never be empty');
    end
end


%%%%%%%%%%%%%%%%%%%%%%%%
function [xPM, np_vec] = get_cross_section_pm(n, pm, sID, map_id, min_points, xs_weight)
% assumes sectionId contains sections sorted by z
% small xs_weight means less weight for cross-layer point-match
if nargin<6, xs_weight = 1;end
np_vec = [];
xPM.M = {};
xPM.adj = [];
xPM.W = {};
xPM.np = [];
options = weboptions;
options.Timeout = 20;
sec_ix = 1;
if numel(sID)>=n
    np_vec = zeros(numel(n:numel(sID)),1);
    fac = (1/n * xs_weight);   % small fac ==> less weight for cross-layer point matches
    
    for ix = n:numel(sID)
        np_vec(sec_ix) = 0;
        count = 1;
        for six1 = 1:numel(sID{ix})
            for six2 = 1:numel(sID{ix-(n-1)})
                urlChar = sprintf('%s/owner/%s/matchCollection/%s/group/%s/matchesWith/%s', ...
                    pm.server, pm.owner, pm.match_collection, sID{ix-(n-1)}{six2}, sID{ix}{six1});
                j = webread(urlChar, options);
                
                %         np_vec(ix-(n-1)) = numel(j);
                for jix = 1:numel(j)
                    if size(j(jix).matches.p',1)>=min_points
                        if isKey(map_id, j(jix).pId) && isKey(map_id, j(jix).qId)
                            xPM(ix-(n-1)).M{count,1}   = j(jix).matches.p';
                            xPM(ix-(n-1)).M{count,2}   = j(jix).matches.q';
                            xPM(ix-(n-1)).adj(count,:) = [map_id(j(jix).pId) map_id(j(jix).qId)];
                            xPM(ix-(n-1)).W{count,1}   = fac * j(jix).matches.w';         % relative weights of point matches within this group
                            xPM(ix-(n-1)).np(count)  = size(j(jix).matches.p',1);    %  we are recording the number of point matches between those two tiles
                            count = count + 1;
                            np_vec(sec_ix) = np_vec(sec_ix) +  1;
                            
                        end
                    end
                end
                %pause(0.2);
            end
        end
        sec_ix = sec_ix + 1;
    end
end









































