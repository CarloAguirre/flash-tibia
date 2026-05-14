<?php

defined('MYAAC') or die('Direct access not allowed!');

function myaacPointsPaypalEnabled(): bool
{
	return getBoolean(setting('core.shop_paypal_enabled'));
}

function myaacPointsPaypalReceiverEmail(): string
{
	return trim((string)setting('core.shop_paypal_email'));
}

function myaacPointsPaypalMode(): string
{
	$mode = strtolower(trim((string)setting('core.shop_paypal_mode')));
	return $mode === 'live' ? 'live' : 'sandbox';
}

function myaacPointsPaypalCurrency(): string
{
	$currency = strtoupper(trim((string)setting('core.shop_paypal_currency')));
	if ($currency === '') {
		$currency = 'USD';
	}

	return $currency;
}

function myaacPointsPaypalEndpoint(): string
{
	return myaacPointsPaypalMode() === 'live'
		? 'https://www.paypal.com/cgi-bin/webscr'
		: 'https://www.sandbox.paypal.com/cgi-bin/webscr';
}

function myaacPointsPaypalIpnVerifyEndpoint(): string
{
	return myaacPointsPaypalMode() === 'live'
		? 'https://ipnpb.paypal.com/cgi-bin/webscr'
		: 'https://ipnpb.sandbox.paypal.com/cgi-bin/webscr';
}

function myaacPointsPaypalPackages(): array
{
	$raw = trim((string)setting('core.shop_paypal_packages'));
	if ($raw === '') {
		return [];
	}

	$rows = preg_split('/\r\n|\r|\n/', $raw);
	$packages = [];

	foreach ($rows as $row) {
		$row = trim($row);
		if ($row === '' || str_starts_with($row, '#')) {
			continue;
		}

		$parts = preg_split('/\s*[:=|]\s*/', $row);
		if (!$parts || count($parts) < 2) {
			continue;
		}

		$points = (int)$parts[0];
		$amount = (float)str_replace(',', '.', trim($parts[1]));
		if ($points <= 0 || $amount <= 0) {
			continue;
		}

		$packages[] = [
			'key' => (string)count($packages),
			'points' => $points,
			'amount' => number_format($amount, 2, '.', ''),
		];
	}

	return $packages;
}

function myaacPointsDonateColumn(): string
{
	global $db;

	$column = (string)setting('core.donate_column');
	if ($column === 'coins' && $db->hasColumn('accounts', 'coins')) {
		return 'coins';
	}

	return 'premium_points';
}

function myaacPointsDonateLabel(): string
{
	return myaacPointsDonateColumn() === 'coins' ? 'coins' : 'premium points';
}

function myaacPointsGetAccountBalance(int $accountId): int
{
	global $db;

	$column = myaacPointsDonateColumn();
	$query = $db->query('SELECT `' . $column . '` AS `balance` FROM `accounts` WHERE `id` = ' . (int)$accountId . ' LIMIT 1');
	if (!$query || $query->rowCount() === 0) {
		return 0;
	}

	$row = $query->fetch();
	return isset($row['balance']) ? (int)$row['balance'] : 0;
}

function myaacPointsEnsurePaymentsTable(): void
{
	global $db;

	if ($db->hasTable('myaac_paypal_transactions')) {
		return;
	}

	$db->query("CREATE TABLE IF NOT EXISTS `myaac_paypal_transactions` (
		`id` INT NOT NULL AUTO_INCREMENT,
		`account_id` INT NOT NULL,
		`package_key` VARCHAR(32) NOT NULL,
		`points` INT NOT NULL,
		`amount` DECIMAL(10,2) NOT NULL,
		`currency` VARCHAR(8) NOT NULL,
		`status` VARCHAR(32) NOT NULL DEFAULT 'pending',
		`payment_status` VARCHAR(64) NOT NULL DEFAULT '',
		`txn_id` VARCHAR(64) NOT NULL DEFAULT '',
		`invoice` VARCHAR(64) NOT NULL DEFAULT '',
		`payer_email` VARCHAR(255) NOT NULL DEFAULT '',
		`raw_post` MEDIUMTEXT NULL,
		`created_at` INT NOT NULL,
		`updated_at` INT NOT NULL,
		PRIMARY KEY (`id`),
		KEY `idx_account_id` (`account_id`),
		KEY `idx_txn_id` (`txn_id`),
		KEY `idx_status` (`status`)
	) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8mb4");
}

function myaacPointsCreatePendingOrder(int $accountId, string $packageKey, int $points, string $amount, string $currency): array
{
	global $db;

	$now = time();
	$db->query('INSERT INTO `myaac_paypal_transactions` (`account_id`, `package_key`, `points`, `amount`, `currency`, `status`, `created_at`, `updated_at`) VALUES (' .
		(int)$accountId . ', ' . $db->quote($packageKey) . ', ' . (int)$points . ', ' . $db->quote($amount) . ', ' . $db->quote($currency) . ", 'pending', " . $now . ', ' . $now . ')');

	$id = (int)$db->lastInsertId();
	$invoice = 'MYAAC-' . $id . '-' . $now;

	$db->query('UPDATE `myaac_paypal_transactions` SET `invoice` = ' . $db->quote($invoice) . ', `updated_at` = ' . $now . ' WHERE `id` = ' . $id);

	return [
		'id' => $id,
		'invoice' => $invoice,
	];
}

function myaacPointsFindOrderById(int $id): ?array
{
	global $db;

	$query = $db->query('SELECT * FROM `myaac_paypal_transactions` WHERE `id` = ' . $id . ' LIMIT 1');
	if (!$query || $query->rowCount() === 0) {
		return null;
	}

	return $query->fetch();
}

function myaacPointsUpdateOrder(int $id, array $data): void
{
	global $db;

	$updates = [];
	foreach ($data as $column => $value) {
		$updates[] = '`' . $column . '` = ' . $db->quote((string)$value);
	}

	$updates[] = '`updated_at` = ' . time();
	$db->query('UPDATE `myaac_paypal_transactions` SET ' . implode(', ', $updates) . ' WHERE `id` = ' . $id . ' LIMIT 1');
}

function myaacPointsVerifyIpn(array $post): bool
{
	$payload = 'cmd=_notify-validate';
	foreach ($post as $key => $value) {
		$payload .= '&' . urlencode((string)$key) . '=' . urlencode((string)$value);
	}

	$url = myaacPointsPaypalIpnVerifyEndpoint();

	$ch = curl_init($url);
	curl_setopt($ch, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_POSTFIELDS, $payload);
	curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, 1);
	curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 2);
	curl_setopt($ch, CURLOPT_FORBID_REUSE, 1);
	curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10);
	curl_setopt($ch, CURLOPT_HTTPHEADER, ['Connection: Close']);

	$response = curl_exec($ch);
	$ok = ($response !== false && trim($response) === 'VERIFIED');
	curl_close($ch);

	if ($ok) {
		return true;
	}

	$context = stream_context_create([
		'http' => [
			'method' => 'POST',
			'header' => "Content-type: application/x-www-form-urlencoded\r\nConnection: Close\r\n",
			'content' => $payload,
			'timeout' => 15,
		],
	]);

	$response = @file_get_contents($url, false, $context);
	return $response !== false && trim($response) === 'VERIFIED';
}
