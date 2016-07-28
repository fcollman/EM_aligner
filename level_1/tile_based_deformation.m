function [mL, minconf, maxconf] = tile_based_deformation(mL, j, minconf, maxconf, A, xout)
% assuming affine

% average the error
for ix = 1:numel(mL.tiles)
    deformation = abs(1- det(mL.tiles(ix).tform.T(1:2, 1:2)));
    mL.tiles(ix).confidence = deformation;
end




%% split into z and display
ml = split_z(mL);
figure;
subplot(3,1,1);
[obj, h, rh, Ar, minconf, maxconf] = show_map_confidence(ml(j), [1], minconf, maxconf); title('Deformation');
subplot(3,1,2);
show_map(ml(j)); title('edge tiles vs. internal tiles');
subplot(3,1,3);
[mL2, tpr2] = tile_based_point_pair_errors(mL, A, xout, j, [], []);title('Point-match residuals');
