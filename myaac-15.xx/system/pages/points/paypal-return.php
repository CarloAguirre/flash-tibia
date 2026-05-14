<?php

defined('MYAAC') or die('Direct access not allowed!');

$title = 'PayPal Payment';

success('Payment was sent to PayPal. Your points will be credited automatically after payment confirmation.');
info('If points do not appear in a few minutes, contact staff with your PayPal transaction id.');

$content .= '
<script type="text/javascript">
(function() {
  // Notify opener (game panel) to refresh coins balance
  if (window.opener && !window.opener.closed) {
    try {
      // Reload the panel iframe if we are opened from the shell
      var opener = window.opener;
      // Try to reload the panel frame inside the shell
      if (opener.document && opener.document.getElementById("panel-frame")) {
        opener.document.getElementById("panel-frame").contentWindow.location.reload();
      } else {
        opener.location.reload();
      }
    } catch(e) {}
  }
  // Auto-close this tab after 5 seconds
  setTimeout(function() {
    window.close();
  }, 5000);
})();
</script>
<p style="text-align:center; margin-top: 10px; color: #666;">Esta pesta&ntilde;a se cerrar&aacute; autom&aacute;ticamente en 5 segundos.</p>
';
