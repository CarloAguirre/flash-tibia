<?php
defined('MYAAC') or die('Direct access not allowed!');

function myaacPanelAuthStorageDir(): string
{
	$dir = rtrim(sys_get_temp_dir(), DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . 'myaac-panel-auth';
	if (!is_dir($dir)) {
		@mkdir($dir, 0700, true);
	}

	return $dir;
}

function myaacPanelAuthCleanup(): void
{
	$dir = myaacPanelAuthStorageDir();
	$now = time();

	foreach (glob($dir . DIRECTORY_SEPARATOR . '*.json') ?: [] as $file) {
		if (!is_file($file)) {
			continue;
		}

		if (@filemtime($file) !== false && @filemtime($file) < ($now - 900)) {
			@unlink($file);
		}
	}
}

function myaacPanelAuthTokenPath(string $token): ?string
{
	$normalized = strtolower(preg_replace('/[^a-f0-9]/', '', $token));
	if (strlen($normalized) !== 64) {
		return null;
	}

	return myaacPanelAuthStorageDir() . DIRECTORY_SEPARATOR . $normalized . '.json';
}

function myaacPanelAuthDefaultRedirect(): string
{
	return myaacPanelAuthNormalizeRedirect(getLink('account/manage'));
}

function myaacPanelAuthNormalizeRedirect($redirect): string
{
	if (!is_string($redirect) || trim($redirect) === '') {
		$redirect = getLink('account/manage');
	}

	$redirect = trim((string)$redirect);
	if ($redirect === '') {
		$redirect = getLink('account/manage');
	}

	if (preg_match('/^https?:\/\//i', $redirect)) {
		$absoluteParts = parse_url($redirect);
		if ($absoluteParts === false || !isset($absoluteParts['path'])) {
			return '/?panel=1';
		}

		$redirect = $absoluteParts['path'];
		if (isset($absoluteParts['query']) && $absoluteParts['query'] !== '') {
			$redirect .= '?' . $absoluteParts['query'];
		}
		if (isset($absoluteParts['fragment']) && $absoluteParts['fragment'] !== '') {
			$redirect .= '#' . $absoluteParts['fragment'];
		}
	}
	elseif (!preg_match('/^\//', $redirect)) {
		$redirect = '/' . ltrim($redirect, '/');
	}

	$parts = parse_url($redirect);
	if ($parts === false || !isset($parts['path'])) {
		return '/?panel=1';
	}

	$query = [];
	if (isset($parts['query'])) {
		parse_str($parts['query'], $query);
	}

	$query['panel'] = '1';
	$normalized = $parts['path'];
	$queryString = http_build_query($query);
	if ($queryString !== '') {
		$normalized .= '?' . $queryString;
	}
	if (isset($parts['fragment']) && $parts['fragment'] !== '') {
		$normalized .= '#' . $parts['fragment'];
	}

	return $normalized;
}

function myaacPanelAuthIssue(array $payload): string
{
	myaacPanelAuthCleanup();

	$token = bin2hex(random_bytes(32));
	$path = myaacPanelAuthTokenPath($token);
	if ($path === null) {
		throw new RuntimeException('Unable to create panel auth token.');
	}

	if (!isset($payload['expires_at'])) {
		$payload['expires_at'] = time() + 120;
	}

	if (@file_put_contents($path, json_encode($payload), LOCK_EX) === false) {
		throw new RuntimeException('Unable to persist panel auth token.');
	}

	@chmod($path, 0600);
	return $token;
}

function myaacPanelAuthConsume(string $token): ?array
{
	$path = myaacPanelAuthTokenPath($token);
	if ($path === null || !is_file($path)) {
		return null;
	}

	$raw = @file_get_contents($path);
	@unlink($path);
	if ($raw === false || $raw === '') {
		return null;
	}

	$payload = json_decode($raw, true);
	if (!is_array($payload)) {
		return null;
	}

	if (!isset($payload['expires_at']) || time() > (int)$payload['expires_at']) {
		return null;
	}

	if (!empty($payload['ip']) && $payload['ip'] !== get_browser_real_ip()) {
		return null;
	}

	return $payload;
}