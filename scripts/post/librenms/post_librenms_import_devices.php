<?php
/**
 * Import devices from devices.json into LibreNMS.
 * POSTs each entry to /api/v0/devices. Skips hostnames that already exist.
 *
 * Env:
 *   LNMS_API_TOKEN (required)
 *   LNMS_URL       (optional) — default http://127.0.0.1:8000
 *   DEVICES_JSON   (optional) — default /data/init-scripts/devices.json
 */
declare(strict_types=1);

$token = getenv('LNMS_API_TOKEN') ?: '';
if ($token === '') {
    fwrite(STDERR, "LNMS_API_TOKEN is not set.\n");
    exit(1);
}

$base = rtrim(getenv('LNMS_URL') ?: 'http://127.0.0.1:8000', '/');
$path = getenv('DEVICES_JSON') ?: '/data/init-scripts/devices.json';

if (! is_readable($path)) {
    fwrite(STDERR, "No devices.json found at {$path} — skipping.\n");
    exit(0);
}

$data    = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
$devices = $data['devices'] ?? [];

$headers = [
    'Content-Type: application/json',
    'X-Auth-Token: ' . $token,
];

$existing = [];
$ch = curl_init("{$base}/api/v0/devices");
curl_setopt_array($ch, [
    CURLOPT_HTTPHEADER     => $headers,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT        => 30,
]);
$body = curl_exec($ch);
curl_close($ch);
$decoded = json_decode($body, true);
foreach (($decoded['devices'] ?? []) as $d) {
    $existing[] = $d['hostname'] ?? '';
}

$ok = 0;
$skip = 0;
$fail = 0;

foreach ($devices as $dev) {
    $host = $dev['hostname'] ?? '';
    if ($host === '') continue;

    if (in_array($host, $existing, true)) {
        echo "SKIP {$host}\n";
        $skip++;
        continue;
    }

    $payload = json_encode([
        'hostname'      => $host,
        'display'       => $dev['display'] ?? $host,
        'snmp_disable'  => !empty($dev['snmp_disable']),
        'ping_fallback' => !empty($dev['ping_fallback']),
    ], JSON_THROW_ON_ERROR);

    $ch = curl_init("{$base}/api/v0/devices");
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_HTTPHEADER     => $headers,
        CURLOPT_POSTFIELDS     => $payload,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 30,
    ]);
    $resp = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($code >= 200 && $code < 300) {
        echo "OK   {$host} ({$dev['display']})\n";
        $ok++;
    } else {
        $msg = json_decode($resp, true)['message'] ?? $resp;
        echo "FAIL {$host} (HTTP {$code}: {$msg})\n";
        $fail++;
    }
}

echo "\nDone: {$ok} added, {$skip} skipped, {$fail} failed.\n";
