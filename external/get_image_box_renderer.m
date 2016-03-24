function [im, v] = get_image_box_renderer(rc, z, Wbox, scale, dir_temp_render, renderer_id)
% Returns the image of a specified box in collection rc
% use Renderer client for complete box
%   /v1/owner/{owner}/project/{project}/stack/{stack}/z/{z}/box/{x},{y},{width},{height},{scale}/jpeg-image
%
% Author: Khaled Khairy
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
v = [];
fn = [dir_temp_render '/tile_image_' num2str(randi(1000)) '_' renderer_id '.jpg'];
url = sprintf('%s/owner/%s/project/%s/stack/%s/z/%s/box/%.0f,%.0f,%.0f,%.0f,%s/render-parameters?filter=true',...
    rc.baseURL, rc.owner, rc.project, rc.stack, num2str(z),Wbox(1), ...
    Wbox(2), ...
    Wbox(3), ...
    Wbox(4), ...
    num2str(scale));



% we will try multiple times
cmd = sprintf('/groups/flyTEM/flyTEM/render/bin/render.sh --memory 7g --out %s --parameters_url "%s"', fn, url);
[a, resp_str] = system(cmd);
file_ready = 0;
count = 1;
while ~(file_ready) && count<200
    pause(0.05);
    file_ready = [exist(fn,'file')==2];
    count = count + 1;
end
try
    pause(1.0);
    im = imread(fn, 'jpeg');
    %if nargout>1, v = webread(url);end
catch err_reading_image
    kk_disp_err(err_reading_image);
    disp('Retrying');
    pause(1.0);
    im = imread(fn, 'jpeg');
end
im = rgb2gray(im);
delete(fn);