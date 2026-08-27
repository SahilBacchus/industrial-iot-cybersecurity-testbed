@load base/frameworks/logging

redef Log::default_rotation_interval = 1min;

redef Log::default_logdir = "/zeek-logs";