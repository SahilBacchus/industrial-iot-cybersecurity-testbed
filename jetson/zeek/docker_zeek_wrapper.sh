#!/bin/bash

HOST_CONFIG="$HOME/zeek-config"
HOST_LOGS="$HOME/zeek-logs"

docker run -it --rm \
  --net=host \
  --privileged \
  -v "$HOST_CONFIG":/zeek-config \
  -v "$HOST_LOGS":/zeek-logs \
  zeek/zeek:lts \
  zeek -i wlan0 /zeek-config/custom_logging.zeek