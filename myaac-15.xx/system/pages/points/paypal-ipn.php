<?php

defined('MYAAC') or die('Direct access not allowed!');

require_once SYSTEM . 'pages/points/common.php';

if (!isRequestMethod('post')) {
	http_response_code(405);
	echo 'Method Not Allowed';
	exit;
}

myaacPointsEnsurePaymentsTable();

$rawPost = file_get_contents('php://input');
$post = $_POST;

if (!myaacPointsVerifyIpn($post)) {
	http_response_code(400);
	echo 'Invalid IPN';
	exit;
}

$orderId = isset($post['custom']) ? (int)$post['custom'] : 0;
$txnId = isset($post['txn_id']) ? trim((string)$post['txn_id']) : '';
$paymentStatus = isset($post['payment_status']) ? trim((string)$post['payment_status']) : '';
$receiverEmail = strtolower(trim((string)($post['receiver_email'] ?? '')));
$payerEmail = trim((string)($post['payer_email'] ?? ''));
$mcGross = isset($post['mc_gross']) ? (float)$post['mc_gross'] : 0.0;
$mcCurrency = strtoupper(trim((string)($post['mc_currency'] ?? '')));

if ($orderId <= 0 || $txnId === '') {
	http_response_code(400);
	echo 'Missing order or txn id';
	exit;
}

$order = myaacPointsFindOrderById($orderId);
if ($order === null) {
	http_response_code(404);
	echo 'Order not found';
	exit;
}

if ($order['status'] === 'completed') {
	echo 'OK';
	exit;
}

$expectedReceiver = strtolower(myaacPointsPaypalReceiverEmail());
if ($expectedReceiver === '' || $receiverEmail !== $expectedReceiver) {
	myaacPointsUpdateOrder($orderId, [
		'status' => 'rejected',
		'payment_status' => $paymentStatus,
		'txn_id' => $txnId,
		'payer_email' => $payerEmail,
		'raw_post' => $rawPost,
	]);

	http_response_code(400);
	echo 'Receiver mismatch';
	exit;
}

if ($paymentStatus !== 'Completed') {
	myaacPointsUpdateOrder($orderId, [
		'status' => 'pending',
		'payment_status' => $paymentStatus,
		'txn_id' => $txnId,
		'payer_email' => $payerEmail,
		'raw_post' => $rawPost,
	]);

	echo 'Pending';
	exit;
}

if ($mcCurrency !== strtoupper((string)$order['currency'])) {
	myaacPointsUpdateOrder($orderId, [
		'status' => 'rejected',
		'payment_status' => $paymentStatus,
		'txn_id' => $txnId,
		'payer_email' => $payerEmail,
		'raw_post' => $rawPost,
	]);

	http_response_code(400);
	echo 'Currency mismatch';
	exit;
}

$expectedAmount = (float)$order['amount'];
if (abs($mcGross - $expectedAmount) > 0.01) {
	myaacPointsUpdateOrder($orderId, [
		'status' => 'rejected',
		'payment_status' => $paymentStatus,
		'txn_id' => $txnId,
		'payer_email' => $payerEmail,
		'raw_post' => $rawPost,
	]);

	http_response_code(400);
	echo 'Amount mismatch';
	exit;
}

$donateColumn = myaacPointsDonateColumn();
$donateLabel = myaacPointsDonateLabel();

global $db;
$txnExists = $db->query('SELECT `id` FROM `myaac_paypal_transactions` WHERE `txn_id` = ' . $db->quote($txnId) . ' AND `id` != ' . $orderId . ' AND `status` = ' . $db->quote('completed') . ' LIMIT 1');
if ($txnExists && $txnExists->rowCount() > 0) {
	http_response_code(409);
	echo 'Duplicate transaction';
	exit;
}

$db->query('UPDATE `accounts` SET `' . $donateColumn . '` = `' . $donateColumn . '` + ' . (int)$order['points'] . ' WHERE `id` = ' . (int)$order['account_id'] . ' LIMIT 1');

myaacPointsUpdateOrder($orderId, [
	'status' => 'completed',
	'payment_status' => $paymentStatus,
	'txn_id' => $txnId,
	'payer_email' => $payerEmail,
	'raw_post' => $rawPost,
]);

$db->query('INSERT INTO `myaac_account_actions` (`account_id`, `ip`, `ipv6`, `date`, `action`) VALUES (' . (int)$order['account_id'] . ', 0, 0, ' . time() . ', ' . $db->quote('paypal_topup +' . (int)$order['points'] . ' ' . $donateLabel . ', txn: ' . $txnId) . ')');

echo 'OK';
exit;
