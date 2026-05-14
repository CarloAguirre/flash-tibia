<?php

defined('MYAAC') or die('Direct access not allowed!');

require_once SYSTEM . 'pages/points/common.php';

$title = 'Buy Points';

if (!$logged) {
	warning('You need to be logged in to buy points.');
	return;
}

myaacPointsEnsurePaymentsTable();

$accountId = (int)$account_logged->getId();
$donateColumn = myaacPointsDonateColumn();
$donateLabel = myaacPointsDonateLabel();
$currentPoints = myaacPointsGetAccountBalance($accountId);
$paypalEnabled = myaacPointsPaypalEnabled();
$paypalEmail = myaacPointsPaypalReceiverEmail();
$currency = myaacPointsPaypalCurrency();
$packages = myaacPointsPaypalPackages();

if (isRequestMethod('post')) {
	csrfProtect();

	$packageKey = isset($_POST['package']) ? (string)$_POST['package'] : '';
	$selectedPackage = null;
	foreach ($packages as $package) {
		if ($package['key'] === $packageKey) {
			$selectedPackage = $package;
			break;
		}
	}

	if (!$paypalEnabled) {
		error('PayPal top up is disabled right now.');
	}
	else if ($paypalEmail === '') {
		error('PayPal receiver e-mail is not configured yet. Contact an administrator.');
	}
	else if ($selectedPackage === null) {
		error('Invalid package selected.');
	}
	else {
		$order = myaacPointsCreatePendingOrder(
			$accountId,
			$selectedPackage['key'],
			(int)$selectedPackage['points'],
			(string)$selectedPackage['amount'],
			$currency
		);

		$notifyUrl = getLink('points/paypal-ipn');
		$returnUrl = getLink('points/paypal-return');
		$cancelUrl = getLink('points/paypal-cancel');
		$paypalEndpoint = myaacPointsPaypalEndpoint();
		$itemName = $selectedPackage['points'] . ' ' . ucfirst($donateLabel);

		echo '<div class="TableContainer">';
		echo '<div class="CaptionContainer"><div class="CaptionInnerContainer"><span class="CaptionEdgeLeftTop" style="background-image:url(' . $template_path . '/images/global/content/box-frame-edge.gif);"></span><span class="CaptionEdgeRightTop" style="background-image:url(' . $template_path . '/images/global/content/box-frame-edge.gif);"></span><span class="CaptionBorderTop" style="background-image:url(' . $template_path . '/images/global/content/table-headline-border.gif);"></span><span class="CaptionVerticalLeft" style="background-image:url(' . $template_path . '/images/global/content/box-frame-vertical.gif);"></span><div class="Text">Redirecting to PayPal</div><span class="CaptionVerticalRight" style="background-image:url(' . $template_path . '/images/global/content/box-frame-vertical.gif);"></span><span class="CaptionBorderBottom" style="background-image:url(' . $template_path . '/images/global/content/table-headline-border.gif);"></span><span class="CaptionEdgeLeftBottom" style="background-image:url(' . $template_path . '/images/global/content/box-frame-edge.gif);"></span><span class="CaptionEdgeRightBottom" style="background-image:url(' . $template_path . '/images/global/content/box-frame-edge.gif);"></span></div></div>';
		echo '<table class="Table1" cellpadding="0" cellspacing="0"><tbody><tr><td>';
		echo '<div class="InnerTableContainer">';
		echo '<p style="margin:0 0 10px 0;">You are being redirected to PayPal checkout.</p>';
		echo '<form id="paypal_checkout_form" action="' . htmlspecialchars($paypalEndpoint) . '" method="post" target="_self">';
		echo '<input type="hidden" name="cmd" value="_xclick" />';
		echo '<input type="hidden" name="business" value="' . htmlspecialchars($paypalEmail) . '" />';
		echo '<input type="hidden" name="item_name" value="' . htmlspecialchars($itemName) . '" />';
		echo '<input type="hidden" name="item_number" value="points-' . (int)$selectedPackage['points'] . '" />';
		echo '<input type="hidden" name="amount" value="' . htmlspecialchars($selectedPackage['amount']) . '" />';
		echo '<input type="hidden" name="currency_code" value="' . htmlspecialchars($currency) . '" />';
		echo '<input type="hidden" name="notify_url" value="' . htmlspecialchars($notifyUrl) . '" />';
		echo '<input type="hidden" name="return" value="' . htmlspecialchars($returnUrl) . '" />';
		echo '<input type="hidden" name="cancel_return" value="' . htmlspecialchars($cancelUrl) . '" />';
		echo '<input type="hidden" name="custom" value="' . (int)$order['id'] . '" />';
		echo '<input type="hidden" name="invoice" value="' . htmlspecialchars($order['invoice']) . '" />';
		echo '<input type="hidden" name="no_shipping" value="1" />';
		echo '<input type="hidden" name="no_note" value="1" />';
		echo '<noscript><button type="submit" class="Button">Continue to PayPal</button></noscript>';
		echo '</form>';
		echo '</div></td></tr></tbody></table></div>';
		echo '<script>document.getElementById("paypal_checkout_form").submit();</script>';
		return;
	}
}

$modeText = myaacPointsPaypalMode() === 'live' ? 'LIVE' : 'SANDBOX';

echo '<div class="TableContainer">';
echo '<div class="CaptionContainer"><div class="CaptionInnerContainer"><span class="CaptionEdgeLeftTop" style="background-image:url(' . $template_path . '/images/global/content/box-frame-edge.gif);"></span><span class="CaptionEdgeRightTop" style="background-image:url(' . $template_path . '/images/global/content/box-frame-edge.gif);"></span><span class="CaptionBorderTop" style="background-image:url(' . $template_path . '/images/global/content/table-headline-border.gif);"></span><span class="CaptionVerticalLeft" style="background-image:url(' . $template_path . '/images/global/content/box-frame-vertical.gif);"></span><div class="Text">Buy Premium Points (PayPal)</div><span class="CaptionVerticalRight" style="background-image:url(' . $template_path . '/images/global/content/box-frame-vertical.gif);"></span><span class="CaptionBorderBottom" style="background-image:url(' . $template_path . '/images/global/content/table-headline-border.gif);"></span><span class="CaptionEdgeLeftBottom" style="background-image:url(' . $template_path . '/images/global/content/box-frame-edge.gif);"></span><span class="CaptionEdgeRightBottom" style="background-image:url(' . $template_path . '/images/global/content/box-frame-edge.gif);"></span></div></div>';
echo '<table class="Table1" cellpadding="0" cellspacing="0"><tbody><tr><td>';
echo '<div class="InnerTableContainer">';
echo '<p style="margin:0 0 8px 0;"><strong>Your current ' . htmlspecialchars($donateLabel) . ':</strong> ' . $currentPoints . '</p>';
echo '<p style="margin:0 0 12px 0;"><strong>Mode:</strong> ' . $modeText . ' | <strong>Currency:</strong> ' . htmlspecialchars($currency) . '</p>';

if (!$paypalEnabled) {
	echo warning('PayPal top up is currently disabled by administrator.', true);
}
else if ($paypalEmail === '') {
	echo error('PayPal receiver e-mail is missing in configuration.', true);
}
else if (count($packages) === 0) {
	echo error('No PayPal packages configured yet.', true);
}
else {
	echo '<table width="100%" border="0" cellspacing="1" cellpadding="4">';
	echo '<tr bgcolor="#F1E0C6"><td><b>Package</b></td><td><b>Price</b></td><td><b>Action</b></td></tr>';

	foreach ($packages as $i => $package) {
		$bg = (($i % 2) === 0 ? '#D4C0A1' : '#F1E0C6');
		echo '<tr bgcolor="' . $bg . '">';
		echo '<td>' . (int)$package['points'] . ' ' . htmlspecialchars(ucfirst($donateLabel)) . '</td>';
		echo '<td>' . htmlspecialchars($package['amount']) . ' ' . htmlspecialchars($currency) . '</td>';
		echo '<td>';
		echo '<form method="post" action="' . htmlspecialchars(getLink('points')) . '" target="_blank" data-skip-panel-loader="1" style="margin:0;">';
		echo csrf(true);
		echo '<input type="hidden" name="package" value="' . htmlspecialchars($package['key']) . '" />';
		echo '<button type="submit" class="Button">Buy with PayPal</button>';
		echo '</form>';
		echo '</td>';
		echo '</tr>';
	}

	echo '</table>';
	echo '<p style="margin:12px 0 0 0;">After payment confirmation, ' . htmlspecialchars($donateLabel) . ' are added automatically and can be spent in the in-game Store (Premium Time category).</p>';
}

echo '</div></td></tr></tbody></table></div>';
