function status = run_all_figures()
%RUN_ALL_FIGURES Regenerate every code-based manuscript figure in order.
% Each figure script runs in the MATLAB base workspace so that its existing
% clear/close commands cannot erase this runner's progress information.

repo_root = fileparts(mfilename('fullpath'));
scripts = {
    'shiptravel_in_paper.m'
    'shiptravel_windband.m'
    'match_check_for_whole_paper_time.m'
    'match_check_for_point_daily_paper_time.m'
    'reliable_lidar_data_threecase.m'
    'shiptravel_rmse_1plus3plus3.m'
    'windband_new.m'
    'wind_dependence.m'
    'distance_to_shore_each_windband.m'
    'for_WS_nightday.m'
    };

figure_ids = {
    'Fig01a'
    'Fig01b'
    'Fig03a'
    'Fig03b'
    'Fig04'
    'Fig05'
    'Fig06'
    'Fig07'
    'Fig08'
    'Fig09'
    };

n_scripts = numel(scripts);
success = false(n_scripts, 1);
elapsed_seconds = nan(n_scripts, 1);
messages = strings(n_scripts, 1);

for k = 1:n_scripts
    script_path = fullfile(repo_root, scripts{k});
    started = tic;
    try
        escaped_path = strrep(script_path, '''', '''''');
        evalin('base', sprintf('run(''%s'')', escaped_path));
        success(k) = true;
        messages(k) = "OK";
    catch ME
        messages(k) = string(getReport(ME, 'extended', 'hyperlinks', 'off'));
    end
    elapsed_seconds(k) = toc(started);
end

status = table(string(figure_ids), string(scripts), success, ...
    elapsed_seconds, messages, ...
    'VariableNames', {'Figure', 'Script', 'Success', ...
    'ElapsedSeconds', 'Message'});

cfg = project_config();
if ~exist(cfg.outputRoot, 'dir')
    mkdir(cfg.outputRoot);
end
status_file = fullfile(cfg.outputRoot, 'run_status.csv');
writetable(status, status_file);

disp(status(:, 1:4));
fprintf('Run status saved to:\n%s\n', status_file);
end
