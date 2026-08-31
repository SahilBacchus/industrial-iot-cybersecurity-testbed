module FlowInsight;

export {
    # Create an ID for the new Log stream
    redef enum Log::ID += { LOG };

    # Record holding the statistical summary of a numeric vector.
    # Field names are kept stable since they become nested log columns
    # (e.g. fwd_pkts_payload.min, fwd_pkts_payload.avg, ...).
    type StatSummary: record {
        min: double &log;
        max: double &log;
        tot: double &log;
        avg: double &log;
        std: double &log;
    };

    # Record written to the log file for every finished connection.
    # Field names are kept stable since they are the CSV/log columns
    # consumed downstream (e.g. by the feature loader / ML pipeline).
    type FlowRecord: record {
        uid:               string  &log;
        flow_duration:     interval &log;
        fwd_pkts_tot:      count &log;
        bwd_pkts_tot:      count &log;
        fwd_pkts_per_sec:  double &log;
        bwd_pkts_per_sec:  double &log;
        flow_pkts_per_sec: double &log;
        down_up_ratio:     double &log;
        fwd_header_size_tot:    count &log;
        fwd_header_size_min:    count &log;
        fwd_header_size_max:    count &log;
        bwd_header_size_tot:    count &log;
        bwd_header_size_min:    count &log;
        bwd_header_size_max:    count &log;
        flow_FIN_flag_count:    count &log;
        flow_SYN_flag_count:    count &log;
        flow_RST_flag_count:    count &log;
        fwd_PSH_flag_count:    count &log;
        bwd_PSH_flag_count:    count &log;
        flow_ACK_flag_count:    count &log;
        fwd_URG_flag_count:    count &log;
        bwd_URG_flag_count:    count &log;
        flow_CWR_flag_count:    count &log;
        flow_ECE_flag_count:    count &log;
        fwd_pkts_payload:  FlowInsight::StatSummary &log;
        bwd_pkts_payload:  FlowInsight::StatSummary &log;
        flow_pkts_payload: FlowInsight::StatSummary &log;

        flow_iat:          FlowInsight::StatSummary &log;
        payload_bytes_per_second:  double &log;

        fwd_bulk_bytes:    double &log;
        bwd_bulk_bytes:    double &log;
        fwd_bulk_packets:  double &log;
        bwd_bulk_packets:  double &log;
        fwd_bulk_rate:     double &log;
        bwd_bulk_rate:     double &log;
        active:            FlowInsight::StatSummary &log;
        idle:              FlowInsight::StatSummary &log;
        fwd_init_window_size: count &log;
        bwd_init_window_size: count &log;
        fwd_last_window_size: count &log;
        bwd_last_window_size: count &log;
        orig_h:        addr         &log;
        resp_h:        addr         &log;
        ts:            time         &log;
        duration:      interval     &log;

        history:       string       &log &optional;

    };

}

# --- Per-connection state, keyed by connection uid --------------------------

# uid -> direction ("fwd"/"bwd") -> running packet count
global pkt_count_by_dir: table[string] of table[string] of count;
# uid -> flag name -> running count of that TCP flag
global tcp_flag_counts: table[string] of table[string] of count;
# uid -> "<dir>,<tot|min|max>" -> running header-size aggregate
global hdr_size_stats: table[string] of table[string] of count;
# uid -> direction -> count of packets that carried payload
global payload_pkt_count: table[string] of table[string] of count;
# uid -> direction -> vector of payload sizes seen so far
global payload_size_samples: table[string] of table[string] of vector of count;
# uid -> direction -> timestamp of the last packet seen in that direction
global last_pkt_ts: table[string] of table[string] of time;

# uid -> whether we are currently at the start of a new active phase
global active_phase_started: table[string] of bool;
# uid -> vector of durations (usec) of completed/ongoing active phases
global active_durations: table[string] of vector of double;
# uid -> vector of durations (usec) of idle phases
global idle_durations: table[string] of vector of double;
# uid -> "fwd"/"bwd"/"flow" -> vector of inter-arrival times (usec)
global iat_samples: table[string] of table[string] of vector of double;
# uid -> direction -> number of confirmed bulk transfers
global bulk_flow_count: table[string] of table[string] of count;
# uid -> "<dir>[,tmp]" -> running byte total for bulk transfers
global bulk_byte_total: table[string] of table[string] of count;
# uid -> "<dir>[,tmp]" -> running packet total for bulk transfers
global bulk_pkt_total: table[string] of table[string] of count;
# uid -> "<dir>[,tmp]" -> running duration total for bulk transfers
global bulk_duration_total: table[string] of table[string] of double;
# uid -> whether the previous packet on this connection was forward-direction
global last_pkt_was_fwd: table[string] of bool;
# uid -> "<init|last>,<dir>" -> TCP window size observed
global tcp_window_sizes: table[string] of table[string] of count;


# --- TCP flag bitmasks -------------------------------------------------------

const TCP_FIN = 1;
const TCP_SYN = 2;
const TCP_RST = 4;
const TCP_PSH = 8;
const TCP_ACK = 16;
const TCP_URG = 32;
const TCP_ECE = 64;
const TCP_CWR = 128;


# --- Tunable thresholds -------------------------------------------------------

# Max inter-arrival time between two packets to still count as the same active phase.
const active_phase_gap = 5 sec &redef;

# Max inter-arrival time between two packets to still count as the same bulk transfer.
const bulk_pkt_gap = 1 sec &redef;

# Minimum number of packets required for a run to be counted as a bulk transfer.
const bulk_min_pkts = 5 &redef;

# Result of an inter-arrival-time calculation. A record is used (rather than a
# plain double) so we can test which of fwd/bwd/flow actually have a value yet.
type IatResult: record {
    fwd: interval &optional;
    bwd: interval &optional;
    flow: interval &optional;
};

# Computes the inter-arrival times for the packet currently being processed.
# NOTE: relies on last_pkt_ts holding the timestamp of the *previous* packet,
#       so call this BEFORE updating last_pkt_ts for the current packet.
#       This function does not update last_pkt_ts itself.
# uid: connection uid to compute IATs for
# returns: an IatResult where fwd/bwd are the gaps since the last fwd/bwd
#          packet (if any), and flow is the gap since the last packet overall.
function compute_iat(uid: string): FlowInsight::IatResult {
    local gap = FlowInsight::IatResult();

    # gap since the last fwd packet, if one has been seen yet
    if ("fwd" in last_pkt_ts[uid]) {
        gap$fwd = network_time() - last_pkt_ts[uid]["fwd"];
    }

    # gap since the last bwd packet, if one has been seen yet
    if ("bwd" in last_pkt_ts[uid]) {
        gap$bwd = network_time() - last_pkt_ts[uid]["bwd"];
    }

    # flow-level gap is the smaller of fwd/bwd gaps if both exist,
    # otherwise whichever one does exist
    if (gap?$fwd && gap?$bwd) {
        gap$flow = gap$fwd > gap$bwd ? gap$bwd : gap$fwd;
    }
    else if (gap?$fwd) {
        gap$flow = gap$fwd;
    }
    else if (gap?$bwd) {
        gap$flow = gap$bwd;
    }

    return gap;
}

# Checks whether a given TCP flag bit is set on a packet header.
# pkt:       the packet header (pkt_hdr) to inspect
# flag_mask: bitmask of the flag to test (see TCP_* constants above)
# returns:   T if the flag is set, F otherwise
function tcp_flag_set(pkt: pkt_hdr, flag_mask: count): bool {
    return (pkt$tcp$flags & flag_mask > 0);
}

# Computes min/max/sum/mean/stddev over a vector of counts.
# vec:     vector of counts to summarize
# returns: FlowInsight::StatSummary; all fields are 0 if the vector is empty
function summarize_counts(vec: vector of count): FlowInsight::StatSummary {
    local summary = FlowInsight::StatSummary($min=0, $max=0, $tot=0, $avg=0, $std=0);
    local n = |vec|;

    if (n == 0) {
        return summary;
    }

    # seed min with the first entry so it isn't stuck at 0
    summary$min = vec[0];

    for (idx in vec) {
        summary$tot += vec[idx];
        if (vec[idx] < summary$min) {
            summary$min = vec[idx];
        }
        if (vec[idx] > summary$max) {
            summary$max = vec[idx];
        }
    }

    summary$avg = summary$tot / n;

    if (n == 1) {
        return summary;
    }

    local mean_diff: double;
    for (idx in vec) {
        mean_diff = vec[idx] - summary$avg;
        summary$std += mean_diff * mean_diff;
    }
    summary$std = summary$std / (n - 1);
    summary$std = sqrt(summary$std);

    return summary;
}

# Computes min/max/sum/mean/stddev over a vector of doubles.
# vec:     vector of doubles to summarize
# returns: FlowInsight::StatSummary; all fields are 0 if the vector is empty
function summarize_doubles(vec: vector of double): FlowInsight::StatSummary {
    local summary = FlowInsight::StatSummary($min=0, $max=0, $tot=0, $avg=0, $std=0);
    local n = |vec|;

    if (n == 0) {
        return summary;
    }

    summary$min = vec[0];

    for (idx in vec) {
        summary$tot += vec[idx];
        if (vec[idx] < summary$min) {
            summary$min = vec[idx];
        }
        if (vec[idx] > summary$max) {
            summary$max = vec[idx];
        }
    }

    summary$avg = summary$tot / n;

    if (n == 1) {
        return summary;
    }

    local mean_diff: double;
    for (idx in vec) {
        mean_diff = vec[idx] - summary$avg;
        summary$std += mean_diff * mean_diff;
    }
    summary$std = summary$std / (n - 1);
    summary$std = sqrt(summary$std);

    return summary;
}

# Create the log stream at startup.
event zeek_init() &priority=5 {
    Log::create_stream(FlowInsight::LOG, [$columns=FlowRecord, $path="Flowfeature"]);
}

# Update the running per-connection stats for every packet seen.
event new_packet(c: connection, p: pkt_hdr) {

    local pkt_is_fwd  = (p?$ip && p$ip$src == c$id$orig_h || p?$ip6 && p$ip6$src == c$id$orig_h);
    local pkt_is_tcp  = p?$tcp;
    local pkt_is_udp  = p?$udp;
    local pkt_is_icmp = p?$icmp;
    local pkt_is_ip6  = p?$ip6;

    # lazily initialize all per-connection state on first sight of this uid
    if (!(c$uid in pkt_count_by_dir)) {
        pkt_count_by_dir[c$uid] = table(["fwd"]=0, ["bwd"]=0);
    }
    if (!(c$uid in tcp_flag_counts)) {
        tcp_flag_counts[c$uid] = table(
            ["FIN"]=0, ["SYN"]=0, ["RST"]=0,
            ["fwd,PSH"]=0, ["bwd,PSH"]=0, ["ACK"]=0,
            ["fwd,URG"]=0, ["bwd,URG"]=0, ["ECE"]=0, ["CWR"]=0
        );
    }
    if (!(c$uid in hdr_size_stats)) {
        hdr_size_stats[c$uid] = table(
            ["fwd,tot"]=0, ["fwd,min"]=0, ["fwd,max"]=0,
            ["bwd,tot"]=0, ["bwd,min"]=0, ["bwd,max"]=0
        );
    }
    if (!(c$uid in payload_size_samples)) {
        payload_size_samples[c$uid] = table(["fwd"]=vector(), ["bwd"]=vector());
    }
    if (!(c$uid in payload_pkt_count)) {
        payload_pkt_count[c$uid] = table(["fwd"]=0, ["bwd"]=0);
    }
    # left empty so membership tests can tell whether a fwd/bwd packet has been seen yet
    if (!(c$uid in last_pkt_ts)) {
        last_pkt_ts[c$uid] = table();
    }

    # any packet received starts us out in an active phase
    if (!(c$uid in active_phase_started)) {
        active_phase_started[c$uid] = T;
    }
    if (!(c$uid in active_durations)) {
        active_durations[c$uid] = vector();
    }
    if (!(c$uid in idle_durations)) {
        idle_durations[c$uid] = vector();
    }
    if (!(c$uid in iat_samples)) {
        iat_samples[c$uid] = table(["fwd"]=vector(), ["bwd"]=vector(), ["flow"]=vector());
    }
    if (!(c$uid in bulk_flow_count)) {
        bulk_flow_count[c$uid] = table(["fwd"]=0, ["bwd"]=0);
    }
    if (!(c$uid in bulk_byte_total)) {
        bulk_byte_total[c$uid] = table(["fwd"]=0, ["fwd,tmp"]=0, ["bwd"]=0, ["bwd,tmp"]=0);
    }
    if (!(c$uid in bulk_pkt_total)) {
        bulk_pkt_total[c$uid] = table(["fwd"]=0, ["fwd,tmp"]=0, ["bwd"]=0, ["bwd,tmp"]=0);
    }
    if (!(c$uid in bulk_duration_total)) {
        bulk_duration_total[c$uid] = table(["fwd"]=0.0, ["fwd,tmp"]=0.0, ["bwd"]=0.0, ["bwd,tmp"]=0.0);
    }
    if (!(c$uid in last_pkt_was_fwd)) {
        last_pkt_was_fwd[c$uid] = F;
    }
    if (!(c$uid in tcp_window_sizes)) {
        tcp_window_sizes[c$uid] = table(["init,fwd"]=0, ["last,fwd"]=0, ["init,bwd"]=0, ["last,bwd"]=0);
    }

    if (pkt_is_fwd) {
        ++pkt_count_by_dir[c$uid]["fwd"];
    }
    else {
        ++pkt_count_by_dir[c$uid]["bwd"];
    }

    local hdr_len = 0;
    if (pkt_is_tcp) {
        hdr_len = p$tcp$hl;
    }
    # UDP and ICMP both use a fixed 8-byte header here
    if (pkt_is_udp || pkt_is_icmp) {
        hdr_len = 8;
    }

    if (pkt_is_fwd) {
        hdr_size_stats[c$uid]["fwd,tot"] += hdr_len;

        if (hdr_size_stats[c$uid]["fwd,min"] > hdr_len || hdr_size_stats[c$uid]["fwd,min"] == 0) {
            hdr_size_stats[c$uid]["fwd,min"] = hdr_len;
        }
        if (hdr_size_stats[c$uid]["fwd,max"] < hdr_len) {
            hdr_size_stats[c$uid]["fwd,max"] = hdr_len;
        }
    }
    else {
        hdr_size_stats[c$uid]["bwd,tot"] += hdr_len;

        if (hdr_size_stats[c$uid]["bwd,min"] > hdr_len || hdr_size_stats[c$uid]["bwd,min"] == 0) {
            hdr_size_stats[c$uid]["bwd,min"] = hdr_len;
        }
        if (hdr_size_stats[c$uid]["bwd,max"] < hdr_len) {
            hdr_size_stats[c$uid]["bwd,max"] = hdr_len;
        }
    }

    local payload_len = 0;

    if (pkt_is_ip6) {
        payload_len = p$ip6$len - hdr_len;
    }
    else {
        payload_len = p$ip$len - p$ip$hl - hdr_len;
    }

    if (pkt_is_fwd) {
        payload_size_samples[c$uid]["fwd"] += payload_len;
        if (payload_len > 0) {
            ++payload_pkt_count[c$uid]["fwd"];
        }
    }
    else {
        payload_size_samples[c$uid]["bwd"] += payload_len;
        if (payload_len > 0) {
            ++payload_pkt_count[c$uid]["bwd"];
        }
    }

    if (pkt_is_tcp) {
        if (tcp_flag_set(p, TCP_FIN)) {
            ++tcp_flag_counts[c$uid]["FIN"];
        }
        if (tcp_flag_set(p, TCP_SYN)) {
            ++tcp_flag_counts[c$uid]["SYN"];
        }
        if (tcp_flag_set(p, TCP_PSH)) {
            if (pkt_is_fwd) {
                ++tcp_flag_counts[c$uid]["fwd,PSH"];
            }
            else {
                ++tcp_flag_counts[c$uid]["bwd,PSH"];
            }
        }
        if (tcp_flag_set(p, TCP_ACK)) {
            ++tcp_flag_counts[c$uid]["ACK"];
        }
        if (tcp_flag_set(p, TCP_URG)) {
            if (pkt_is_fwd) {
                ++tcp_flag_counts[c$uid]["fwd,URG"];
            }
            else {
                ++tcp_flag_counts[c$uid]["bwd,URG"];
            }
        }
        if (tcp_flag_set(p, TCP_ECE)) {
            ++tcp_flag_counts[c$uid]["ECE"];
        }
        if (tcp_flag_set(p, TCP_CWR)) {
            ++tcp_flag_counts[c$uid]["CWR"];
        }
        if (tcp_flag_set(p, TCP_RST)) {
            ++tcp_flag_counts[c$uid]["RST"];
        }
    }

    local gap = compute_iat(c$uid);

    # only meaningful once we've seen at least one prior packet on this flow
    if (gap?$flow) {

        # gap longer than active_phase_gap means we just finished an idle
        # phase -> record it, and mark that we're entering a new active phase
        # (converted to microseconds)
        if (gap$flow > active_phase_gap) {
            idle_durations[c$uid] += (|gap$flow| * 1000000.0);
            active_phase_started[c$uid] = T;
        }
        # second packet of a new active phase -> open a new entry for it
        else if (active_phase_started[c$uid]) {
            active_durations[c$uid] += (|gap$flow| * 1000000.0);
            active_phase_started[c$uid] = F;
        }
        # still within an existing active phase -> extend its duration
        else {
            active_durations[c$uid][|active_durations[c$uid]| - 1] += |gap$flow| * 1000000.0;
        }

        iat_samples[c$uid]["flow"] += |gap$flow| * 1000000.0;
    }

    if (pkt_is_fwd && gap?$fwd) {
        iat_samples[c$uid]["fwd"] += |gap$fwd| * 1000000.0;
    }

    if (!pkt_is_fwd && gap?$bwd) {
        iat_samples[c$uid]["bwd"] += |gap$bwd| * 1000000.0;
    }

    # bulk-transfer tracking only considers packets that actually carry payload
    if (payload_len > 0) {
        if (pkt_is_fwd) {
            if (last_pkt_was_fwd[c$uid]) {
                if (gap?$fwd && gap$fwd < bulk_pkt_gap) {
                    # still within the current possible fwd bulk transfer
                    ++bulk_pkt_total[c$uid]["fwd,tmp"];
                    bulk_byte_total[c$uid]["fwd,tmp"] += payload_len;
                    bulk_duration_total[c$uid]["fwd,tmp"] += |gap$fwd|;
                }
                else {
                    # gap too large -> close out the previous run, if long enough to count
                    if (bulk_pkt_total[c$uid]["fwd,tmp"] >= bulk_min_pkts) {
                        ++bulk_flow_count[c$uid]["fwd"];
                        bulk_pkt_total[c$uid]["fwd"] += bulk_pkt_total[c$uid]["fwd,tmp"];
                        bulk_byte_total[c$uid]["fwd"] += bulk_byte_total[c$uid]["fwd,tmp"];
                        bulk_duration_total[c$uid]["fwd"] += bulk_duration_total[c$uid]["fwd,tmp"];
                    }
                    # start tracking a fresh possible run, seeded with this packet
                    bulk_pkt_total[c$uid]["fwd,tmp"] = 1;
                    bulk_byte_total[c$uid]["fwd,tmp"] = payload_len;
                    bulk_duration_total[c$uid]["fwd,tmp"] = 0.0;
                }
            }
            else {
                # direction switched to fwd -> close out any pending bwd run
                if (bulk_pkt_total[c$uid]["bwd,tmp"] >= bulk_min_pkts) {
                    ++bulk_flow_count[c$uid]["bwd"];
                    bulk_pkt_total[c$uid]["bwd"] += bulk_pkt_total[c$uid]["bwd,tmp"];
                    bulk_byte_total[c$uid]["bwd"] += bulk_byte_total[c$uid]["bwd,tmp"];
                    bulk_duration_total[c$uid]["bwd"] += bulk_duration_total[c$uid]["bwd,tmp"];
                }
                bulk_pkt_total[c$uid]["fwd,tmp"] = 1;
                bulk_byte_total[c$uid]["fwd,tmp"] = payload_len;
                bulk_duration_total[c$uid]["fwd,tmp"] = 0.0;
            }
            last_pkt_was_fwd[c$uid] = T;
        }
        else {
            if (!last_pkt_was_fwd[c$uid]) {
                if (gap?$bwd && gap$bwd < bulk_pkt_gap) {
                    ++bulk_pkt_total[c$uid]["bwd,tmp"];
                    bulk_byte_total[c$uid]["bwd,tmp"] += payload_len;
                    bulk_duration_total[c$uid]["bwd,tmp"] += |gap$bwd|;
                }
                else {
                    if (bulk_pkt_total[c$uid]["bwd,tmp"] >= bulk_min_pkts) {
                        ++bulk_flow_count[c$uid]["bwd"];
                        bulk_pkt_total[c$uid]["bwd"] += bulk_pkt_total[c$uid]["bwd,tmp"];
                        bulk_byte_total[c$uid]["bwd"] += bulk_byte_total[c$uid]["bwd,tmp"];
                        bulk_duration_total[c$uid]["bwd"] += bulk_duration_total[c$uid]["bwd,tmp"];
                    }
                    bulk_pkt_total[c$uid]["bwd,tmp"] = 1;
                    bulk_byte_total[c$uid]["bwd,tmp"] = payload_len;
                    bulk_duration_total[c$uid]["bwd,tmp"] = 0.0;
                }
            }
            else {
                # direction switched to bwd -> close out any pending fwd run
                if (bulk_pkt_total[c$uid]["fwd,tmp"] >= bulk_min_pkts) {
                    ++bulk_flow_count[c$uid]["fwd"];
                    bulk_pkt_total[c$uid]["fwd"] += bulk_pkt_total[c$uid]["fwd,tmp"];
                    bulk_byte_total[c$uid]["fwd"] += bulk_byte_total[c$uid]["fwd,tmp"];
                    bulk_duration_total[c$uid]["fwd"] += bulk_duration_total[c$uid]["fwd,tmp"];
                }
                bulk_pkt_total[c$uid]["bwd,tmp"] = 1;
                bulk_byte_total[c$uid]["bwd,tmp"] = payload_len;
                bulk_duration_total[c$uid]["bwd,tmp"] = 0.0;
            }
            last_pkt_was_fwd[c$uid] = F;
        }
    }

    # record the initial/last TCP window size seen in each direction
    if (pkt_is_tcp && pkt_is_fwd) {
        if (pkt_count_by_dir[c$uid]["fwd"] == 1) {
            tcp_window_sizes[c$uid]["init,fwd"] = p$tcp$win;
        }
        tcp_window_sizes[c$uid]["last,fwd"] = p$tcp$win;
    }
    if (pkt_is_tcp && !pkt_is_fwd) {
        if (pkt_count_by_dir[c$uid]["bwd"] == 1) {
            tcp_window_sizes[c$uid]["init,bwd"] = p$tcp$win;
        }
        tcp_window_sizes[c$uid]["last,bwd"] = p$tcp$win;
    }

    if (pkt_is_fwd) {
        last_pkt_ts[c$uid]["fwd"] = network_time();
    }
    else {
        last_pkt_ts[c$uid]["bwd"] = network_time();
    }
}

# When a connection finishes, finalize all features and write the log entry.
event connection_state_remove(c: connection) {

    # flush any pending bulk-transfer run that was still open at connection end
    if (bulk_pkt_total[c$uid]["fwd,tmp"] >= bulk_min_pkts) {
        ++bulk_flow_count[c$uid]["fwd"];
        bulk_pkt_total[c$uid]["fwd"] += bulk_pkt_total[c$uid]["fwd,tmp"];
        bulk_byte_total[c$uid]["fwd"] += bulk_byte_total[c$uid]["fwd,tmp"];
        bulk_duration_total[c$uid]["fwd"] += bulk_duration_total[c$uid]["fwd,tmp"];
    }
    if (bulk_pkt_total[c$uid]["bwd,tmp"] >= bulk_min_pkts) {
        ++bulk_flow_count[c$uid]["bwd"];
        bulk_pkt_total[c$uid]["bwd"] += bulk_pkt_total[c$uid]["bwd,tmp"];
        bulk_byte_total[c$uid]["bwd"] += bulk_byte_total[c$uid]["bwd,tmp"];
        bulk_duration_total[c$uid]["bwd"] += bulk_duration_total[c$uid]["bwd,tmp"];
    }

    local payload_stats_fwd = summarize_counts(payload_size_samples[c$uid]["fwd"]);
    local payload_stats_bwd = summarize_counts(payload_size_samples[c$uid]["bwd"]);

    # merge fwd samples into bwd to get the whole-flow view (fwd vector no longer needed after this)
    local fwd_payload_count = |payload_size_samples[c$uid]["fwd"]|;
    local bwd_payload_count = |payload_size_samples[c$uid]["bwd"]|;
    payload_size_samples[c$uid]["bwd"][bwd_payload_count:bwd_payload_count + fwd_payload_count] =
        payload_size_samples[c$uid]["fwd"];

    local payload_stats_flow = summarize_counts(payload_size_samples[c$uid]["bwd"]);

    # the vectors have now been mutated into the whole-flow view, so drop them
    # to avoid anyone accidentally reusing them as per-direction data
    delete payload_size_samples[c$uid];

    local rate_fwd_pkts     = 0.0;
    local rate_bwd_pkts     = 0.0;
    local rate_flow_pkts    = 0.0;
    local rate_payload_bytes = 0.0;

    # only computable once duration is non-zero; |c$duration| gives a double instead of an interval
    if (c$duration > 0 usec) {
        rate_fwd_pkts  = pkt_count_by_dir[c$uid]["fwd"] / |c$duration|;
        rate_bwd_pkts  = pkt_count_by_dir[c$uid]["bwd"] / |c$duration|;
        rate_flow_pkts = (pkt_count_by_dir[c$uid]["fwd"] + pkt_count_by_dir[c$uid]["bwd"]) / |c$duration|;
        rate_payload_bytes = payload_stats_flow$tot / |c$duration|;
    }

    local ratio_down_up = 0.0;

    # multiply by 1.0 so the division happens in doubles, not ints
    if (pkt_count_by_dir[c$uid]["fwd"] > 0) {
        ratio_down_up = pkt_count_by_dir[c$uid]["bwd"] / (1.0 * pkt_count_by_dir[c$uid]["fwd"]);
    }

    local bulk_avg_bytes_fwd = 0.0;
    local bulk_avg_pkts_fwd  = 0.0;
    local bulk_avg_bytes_bwd = 0.0;
    local bulk_avg_pkts_bwd  = 0.0;
    local bulk_rate_fwd      = 0.0;
    local bulk_rate_bwd      = 0.0;

    if (bulk_flow_count[c$uid]["fwd"] > 0) {
        bulk_avg_bytes_fwd = bulk_byte_total[c$uid]["fwd"] / (1.0 * bulk_flow_count[c$uid]["fwd"]);
        bulk_avg_pkts_fwd  = bulk_pkt_total[c$uid]["fwd"] / (1.0 * bulk_flow_count[c$uid]["fwd"]);
    }
    if (bulk_flow_count[c$uid]["bwd"] > 0) {
        bulk_avg_bytes_bwd = bulk_byte_total[c$uid]["bwd"] / (1.0 * bulk_flow_count[c$uid]["bwd"]);
        bulk_avg_pkts_bwd  = bulk_pkt_total[c$uid]["bwd"] / (1.0 * bulk_flow_count[c$uid]["bwd"]);
    }
    if (bulk_duration_total[c$uid]["fwd"] > 0.0) {
        bulk_rate_fwd = bulk_byte_total[c$uid]["fwd"] / bulk_duration_total[c$uid]["fwd"];
    }
    if (bulk_duration_total[c$uid]["bwd"] > 0.0) {
        bulk_rate_bwd = bulk_byte_total[c$uid]["bwd"] / bulk_duration_total[c$uid]["bwd"];
    }

    # assemble the final log record for this connection
    local flow_rec = FlowInsight::FlowRecord(
        $uid                  = c$uid,
        $ts                   = c$start_time,
        $orig_h               = c$id$orig_h,
        $resp_h               = c$id$resp_h,
        $duration             = c$duration,
        $history              = c$history,
        $flow_duration        = c$duration,
        $fwd_pkts_tot         = pkt_count_by_dir[c$uid]["fwd"],
        $bwd_pkts_tot         = pkt_count_by_dir[c$uid]["bwd"],
        $fwd_pkts_per_sec     = rate_fwd_pkts,
        $bwd_pkts_per_sec     = rate_bwd_pkts,
        $flow_pkts_per_sec    = rate_flow_pkts,
        $down_up_ratio        = ratio_down_up,
        $fwd_header_size_tot  = hdr_size_stats[c$uid]["fwd,tot"],
        $fwd_header_size_min  = hdr_size_stats[c$uid]["fwd,min"],
        $fwd_header_size_max  = hdr_size_stats[c$uid]["fwd,max"],
        $bwd_header_size_tot  = hdr_size_stats[c$uid]["bwd,tot"],
        $bwd_header_size_min  = hdr_size_stats[c$uid]["bwd,min"],
        $bwd_header_size_max  = hdr_size_stats[c$uid]["bwd,max"],
        $flow_FIN_flag_count  = tcp_flag_counts[c$uid]["FIN"],
        $flow_SYN_flag_count  = tcp_flag_counts[c$uid]["SYN"],
        $flow_RST_flag_count  = tcp_flag_counts[c$uid]["RST"],
        $fwd_PSH_flag_count   = tcp_flag_counts[c$uid]["fwd,PSH"],
        $bwd_PSH_flag_count   = tcp_flag_counts[c$uid]["bwd,PSH"],
        $flow_ACK_flag_count  = tcp_flag_counts[c$uid]["ACK"],
        $fwd_URG_flag_count   = tcp_flag_counts[c$uid]["fwd,URG"],
        $bwd_URG_flag_count   = tcp_flag_counts[c$uid]["bwd,URG"],
        $flow_CWR_flag_count  = tcp_flag_counts[c$uid]["CWR"],
        $flow_ECE_flag_count  = tcp_flag_counts[c$uid]["ECE"],
        $fwd_pkts_payload     = payload_stats_fwd,
        $bwd_pkts_payload     = payload_stats_bwd,
        $flow_pkts_payload    = payload_stats_flow,
        $flow_iat             = summarize_doubles(iat_samples[c$uid]["flow"]),
        $payload_bytes_per_second = rate_payload_bytes,
        $fwd_bulk_bytes       = 1.0 * bulk_byte_total[c$uid]["fwd"],
        $bwd_bulk_bytes       = 1.0 * bulk_byte_total[c$uid]["bwd"],
        $fwd_bulk_packets     = 1.0 * bulk_pkt_total[c$uid]["fwd"],
        $bwd_bulk_packets     = 1.0 * bulk_pkt_total[c$uid]["bwd"],
        $fwd_bulk_rate        = bulk_rate_fwd,
        $bwd_bulk_rate        = bulk_rate_bwd,
        $active               = summarize_doubles(active_durations[c$uid]),
        $idle                 = summarize_doubles(idle_durations[c$uid]),
        $fwd_init_window_size = tcp_window_sizes[c$uid]["init,fwd"],
        $bwd_init_window_size = tcp_window_sizes[c$uid]["init,bwd"],
        $fwd_last_window_size = tcp_window_sizes[c$uid]["last,fwd"],
        $bwd_last_window_size = tcp_window_sizes[c$uid]["last,bwd"]
    );

    # clear out this connection's state, it's no longer needed
    delete pkt_count_by_dir[c$uid];
    delete tcp_flag_counts[c$uid];
    delete payload_pkt_count[c$uid];
    delete hdr_size_stats[c$uid];
    delete active_durations[c$uid];
    delete idle_durations[c$uid];
    delete active_phase_started[c$uid];
    delete bulk_flow_count[c$uid];
    delete bulk_byte_total[c$uid];
    delete bulk_duration_total[c$uid];
    delete last_pkt_was_fwd[c$uid];
    delete bulk_pkt_total[c$uid];
    delete tcp_window_sizes[c$uid];
    delete iat_samples[c$uid];

    Log::write(FlowInsight::LOG, flow_rec);
}
