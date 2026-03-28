<?php
/**
 * Import service checks from services.json into LibreNMS.
 * POSTs each entry to /api/v0/services/{device}.
 * Skips services whose desc already exists on that device — safe to re-run.
 *
 * Env:
 *   LNMS_API_TOKEN (required)
 *   LNMS_URL      (optional) — default http://127.0.0.1:8000
 *   SERVICES_JSON (optional) — default /data/init-scripts/services.json
 */
declare(strict_types=1);

$token = getenv('LNMS_API_TOKEN') ?: '';
if ($token === '') {
    fwrite(STDERR, "LNMS_API_TOKEN is not set.\n");
    exit(1);
}

$base = rtrim(getenv('LNMS_URL') ?: 'http://127.0.0.1:8000', '/');
$path = getenv('SERVICES_JSON') ?: '/data/init-scripts/services.json';

if (! is_readable($path)) {
    fwrite(STDERR, "No services.json found at {$path} — skipping.\n");
    exit(0);
}

$data    = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
$devices = $data['devices'] ?? [];

$headers = [
    'Content-Type: application/json',
    'X-Auth-Token: ' . $token,
];

function api_get(string $url, array $headers): array
{
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_HTTPHEADER     => $headers,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 30,
    ]);
    $body = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($code !== 200) {
        return [];
    }
    $decoded = json_decode($body, true);
    return $decoded['services'] ?? [];
}

function api_post(string $url, array $headers, string $body): array
{
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_HTTPHEADER     => $headers,
        CURLOPT_POSTFIELDS     => $body,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 30,
    ]);
    $resp = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    return [$code, $resp];
}

$total_ok   = 0;
$total_skip = 0;
$total_fail = 0;

foreach ($devices as $device) {
    if (! isset($device['device'], $device['services'])) {
        continue;
    }

    $dev = $device['device'];
    echo "\nDevice: {$dev}\n";

    $existing       = api_get("{$base}/api/v0/services/{$dev}", $headers);
    $existing_descs = array_column($existing, 'service_desc');

    foreach ($device['services'] as $svc) {
        $desc = $svc['desc'] ?? '';

        if (in_array($desc, $existing_descs, true)) {
            echo "  SKIP {$desc}\n";
            $total_skip++;
            continue;
        }

        $payload = json_encode([
            'type'     => $svc['type'],
            'name'     => $svc['name'] ?? $svc['type'],
            'desc'     => $desc,
            'param'    => $svc['param'] ?? '',
            'ip'       => $svc['ip'] ?? '',
            'disabled' => $svc['disabled'] ?? 0,
            'ignore'   => $svc['ignore'] ?? 0,
        ], JSON_THROW_ON_ERROR);

        [$code, $resp] = api_post("{$base}/api/v0/services/{$dev}", $headers, $payload);

        if ($code >= 200 && $code < 300) {
            echo "  OK   {$desc}\n";
            $total_ok++;
        } else {
            $msg = json_decode($resp, true)['message'] ?? $resp;
            echo "  FAIL {$desc} (HTTP {$code}: {$msg})\n";
            $total_fail++;
        }
    }
}

echo "\nDone: {$total_ok} added, {$total_skip} skipped, {$total_fail} failed.\n";
