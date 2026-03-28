<?php
// Mounted at /data/config/config.php — the official image includes this path from /opt/librenms/config.php.

// Docker Compose .env passes quotes literally — strip them.
function env(string $key, string $default = ''): string {
    return trim(getenv($key) ?: $default, "\"' ");
}

$appUrl = env('APP_URL');
if ($appUrl !== '') {
    $config['base_url'] = rtrim($appUrl, '/');
}

$config['snmp']['community'] = [env('SNMP_COMMUNITY', 'public')];

foreach (array_filter(explode(' ', env('DISCOVERY_SUBNET', '10.0.0.0/24'))) as $subnet) {
    $config['nets'][] = trim($subnet);
}

$config['enable_syslog'] = 1;
$config['show_services'] = 1;
$config['ping_rrd'] = 1;
$config['syslog_purge'] = (int) env('SYSLOG_PURGE_DAYS', '30');
