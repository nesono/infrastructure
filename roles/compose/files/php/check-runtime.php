<?php
// Run before deploying an image, with the same ini mount as the web service.
$fixed = ['8.2' => '8.2.35', '8.3' => '8.3.36', '8.4' => '8.4.27', '8.5' => '8.5.12'];
$branch = PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;
if (!isset($fixed[$branch]) || version_compare(PHP_VERSION, $fixed[$branch], '<')) {
    fwrite(STDERR, "Unverified or vulnerable PHP runtime: " . PHP_VERSION . PHP_EOL);
    exit(1);
}
if (ini_get('session.upload_progress.enabled')) {
    fwrite(STDERR, "Session upload progress must be disabled before request parsing." . PHP_EOL);
    exit(1);
}
echo "PHP " . PHP_VERSION . ": security checks passed" . PHP_EOL;
