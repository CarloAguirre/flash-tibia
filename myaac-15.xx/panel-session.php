<?php

require_once 'common.php';
require_once SYSTEM . 'functions.php';
require_once SYSTEM . 'init.php';
require_once SYSTEM . 'login.php';
require_once SYSTEM . 'libs/panel_auth.php';

header('Content-Type: application/json');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');

die(json_encode([
	'logged' => $logged && isset($account_logged) && $account_logged->isLoaded(),
	'panel_url' => myaacPanelAuthDefaultRedirect(),
]));