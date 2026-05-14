<?php

require_once 'common.php';
require_once SYSTEM . 'functions.php';
require_once SYSTEM . 'init.php';
require_once SYSTEM . 'libs/panel_auth.php';

$redirect = myaacPanelAuthDefaultRedirect();
$payload = myaacPanelAuthConsume($_GET['token'] ?? '');

if (is_array($payload) && !empty($payload['account_id'])) {
	$redirect = myaacPanelAuthNormalizeRedirect($payload['redirect'] ?? $redirect);
	$account = new OTS_Account();
	$account->load((int)$payload['account_id']);

	if ($account->isLoaded()) {
		session_regenerate_id();
		setSession([
			'account' => $account->getId(),
			'password' => $account->getPassword(),
			'remember_me' => !empty($payload['remember_me']) ? true : null,
			'last_visit' => time(),
			'last_uri' => $redirect,
		]);

		if (fieldExist('web_lastlogin', 'accounts')) {
			$account->setCustomField('web_lastlogin', time());
		}
	}
}

header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('Location: ' . $redirect);
exit;