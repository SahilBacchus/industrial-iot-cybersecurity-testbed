@load base/frameworks/logging

# Rotate logs every hour, same cadence as your aggregator/edge server
redef Log::default_rotation_interval = 1hr;

# Default log directory is going to be /zeek-logs
redef Log::default_logdir = "/zeek-logs";

# Write logs in JSON format instead of TSV for easier loading into pandas/Python
redef LogAscii::use_json = T;

# Automatically compress rotated logs with gzip to preserve disk space over time
redef Log::default_rotation_postprocessor_cmd = "gzip";

# Load custom FlowInsight network analysis script
@load ./FlowInsight.zeek
