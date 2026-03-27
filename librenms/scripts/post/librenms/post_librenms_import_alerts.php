<?php
/**
 * Import every rule from resources/definitions/alert_rules.json (same as
 * Alerts > Add rule from collection). POSTs each to /api/v0/rules.
 *
 * Env:
 *   LNMS_API_TOKEN (required) — must match a row in api_tokens (see bootstrap)
 *   LNMS_URL (optional) — default http://127.0.0.1:8000 (direct to app; avoids TLS)
 */
declare(strict_types=1);

$token = getenv('LNMS_API_TOKEN') ?: '';
if ($token === '') {
    fwrite(STDERR, "LNMS_API_TOKEN is not set.\n");
    exit(1);
}

$base = rtrim(getenv('LNMS_URL') ?: 'http://127.0.0.1:8000', '/');
$path = '/opt/librenms/resources/definitions/alert_rules.json';
if (! is_readable($path)) {
    fwrite(STDERR, "Cannot read {$path}\n");
    exit(1);
}

$raw = file_get_contents($path);
$rules = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);

$ok = 0;
$skip = 0;

foreach ($rules as $r) {
    $name = $r['name'] ?? '';
    $count = 15;
    if (! empty($r['extra'])) {
        $extra = json_decode((string) $r['extra'], true);
        if (is_array($extra) && isset($extra['count'])) {
            $count = (int) $extra['count'];
        }
    }

    $payload = [
        'devices' => [-1],
        'name' => $name,
        'builder' => $r['builder'] ?? [],
        'severity' => 'warning',
        'disabled' => 0,
        'count' => $count,
        'delay' => '5 m',
        'interval' => '5 m',
        'mute' => false,
        'notes' => $r['notes'] ?? '',
    ];

    $body = json_encode($payload, JSON_THROW_ON_ERROR);
    $ch = curl_init($base . '/api/v0/rules');
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/json',
            'X-Auth-Token: ' . $token,
        ],
        CURLOPT_POSTFIELDS => $body,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 60,
    ]);
    curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($code >= 200 && $code < 300) {
        echo "OK   {$name}\n";
        $ok++;
    } else {
        echo "SKIP {$name} (HTTP {$code})\n";
        $skip++;
    }
}

echo "Done: {$ok} imported, {$skip} skipped or failed.\n";
