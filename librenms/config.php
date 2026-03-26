<?php
// LibreNMS custom config - loaded on every startup.
// Sensitive values are read from environment variables set in .env via docker-compose.

$config['snmp']['community'] = [getenv('SNMP_COMMUNITY') ?: 'public'];

foreach (array_filter(explode(' ', getenv('DISCOVERY_SUBNET') ?: '10.0.0.0/24')) as $subnet) {
    $config['nets'][] = trim($subnet);
}

$config['enable_syslog'] = 1;

$config['ping_rrd'] = 1;

$config['syslog_purge'] = (int)(getenv('SYSLOG_PURGE_DAYS') ?: 30);
