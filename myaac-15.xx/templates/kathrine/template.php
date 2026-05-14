<?php
defined('MYAAC') or die('Direct access not allowed!');

$isPanelMode = isset($_GET['panel']) && $_GET['panel'] === '1';

function kathrine_panel_url(): string
{
	$uri = $_SERVER['REQUEST_URI'] ?? '/';
	if(strpos($uri, 'panel=') !== false) {
		return $uri;
	}

	return $uri . (strpos($uri, '?') === false ? '?' : '&') . 'panel=1';
}

if(!$isPanelMode) {
	$panelUrlRaw = kathrine_panel_url();
	$panelUrl = htmlspecialchars($panelUrlRaw, ENT_QUOTES, 'UTF-8');
?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" class="shell-root">
	<head>
		<?php echo template_place_holder('head_start'); ?>
		<link rel="stylesheet" href="<?php echo $template_path; ?>/style.css?v=myaac-shell22" type="text/css" />
		<?php echo template_place_holder('head_end'); ?>
	</head>
	<body class="shell-mode">
		<div id="game-background">
			<iframe id="game-frame" src="/game/?embedded=1&amp;v=myaac-fullscreen21" title="Canary 15 live game background" allow="cross-origin-isolated; fullscreen" tabindex="-1"></iframe>
		</div>
		<div id="game-click-catcher"></div>
		<div id="panel-shell">
			<iframe id="panel-frame" src="<?php echo $panelUrl; ?>" title="OTServBR-Global 15 website panel" allowtransparency="true"></iframe>
			<div id="panel-loader" aria-hidden="true">
				<div class="panel-loader-box">
					<span class="panel-loader-spinner" aria-hidden="true"></span>
					<span>Cargando</span>
				</div>
			</div>
		</div>
		<button id="layout-toggle" type="button" aria-controls="panel-frame" aria-expanded="true" title="Ocultar panel">
			<span class="layout-toggle-icon" aria-hidden="true">&#9660;</span>
		</button>
		<script type="text/javascript">
		(function() {
			var storageKey = 'myaac-kathrine-shell-collapsed';
			var fullPanelTop = -50;
			var compactPanelReferenceTop = 50;
			var button = document.getElementById('layout-toggle');
			var icon = button ? button.getElementsByTagName('span')[0] : null;
			var gameFrame = document.getElementById('game-frame');
			var panelShell = document.getElementById('panel-shell');
			var panelFrame = document.getElementById('panel-frame');
			var panelSyncFrame = null;
			var panelLoader = document.getElementById('panel-loader');
			var panelLoaderTimer = null;
			var panelLoaderStartedAt = 0;
			var panelInitialUrl = <?php echo json_encode($panelUrlRaw); ?>;
			var panelScrollTop = 0;
			var panelCompactEligible = isLatestNewsUrl(panelInitialUrl);
			var startupCompactDismissed = !panelCompactEligible;
			var panelSessionLogged = null;
			var panelSessionPolling = false;
			var panelSessionAutoOpened = false;
			var reloadGuardEnabled = false;

			window.addEventListener('beforeunload', function(event) {
				if(!reloadGuardEnabled) {
					return;
				}

				event.preventDefault();
				event.returnValue = '';
				return '';
			});

			function isLatestNewsUrl(href) {
				var url;
				try {
					url = new URL(href, window.location.origin);
				} catch(error) {
					return false;
				}

				if(url.origin !== window.location.origin) {
					return false;
				}

				var path = url.pathname.replace(/\/+$/, '');
				if(path === '') {
					path = '/';
				}

				var isRoot = path === '/' || path === '/index.php';
				var isLatestNews = /\/news$/.test(path) || /\/index\.php\/news$/.test(path);
				var isNewsArchive = /\/news\/archive$/.test(path) || /\/index\.php\/news\/archive$/.test(path);
				var isChangeLog = /\/change-log$/.test(path) || /\/index\.php\/change-log$/.test(path);

				return (isRoot || isLatestNews) && !isNewsArchive && !isChangeLog;
			}

			function isCollapsed() {
				return document.body.className.indexOf('layout-collapsed') !== -1;
			}

			function isStartupCompactState() {
				return !isCollapsed() && panelCompactEligible && !startupCompactDismissed;
			}

			function syncToggleState() {
				if(!button || !icon) {
					return;
				}

				var canExpand = isCollapsed() || isStartupCompactState();
				button.setAttribute('aria-expanded', canExpand ? 'false' : 'true');
				button.setAttribute('title', canExpand ? 'Mostrar panel' : 'Ocultar panel');
				icon.innerHTML = canExpand ? '&#9650;' : '&#9660;';
			}

			function getCompactPanelTop() {
				var viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
				var compactExpandedHeight = Math.max(0, viewportHeight - compactPanelReferenceTop);
				return compactPanelReferenceTop + Math.round(compactExpandedHeight * 0.5);
			}

			function applyPanelShellTop() {
				if(!panelShell) {
					syncToggleState();
					return;
				}

				if(isCollapsed()) {
					panelShell.style.top = fullPanelTop + 'px';
					syncToggleState();
					return;
				}

				var nextTop = fullPanelTop;
				if(panelCompactEligible && !startupCompactDismissed) {
					var compactTop = getCompactPanelTop();
					var travel = Math.max(1, compactTop - fullPanelTop);
					var progress = Math.min(1, Math.max(0, panelScrollTop) / travel);
					nextTop = Math.round(compactTop - (travel * progress));
					if(progress >= 1) {
						startupCompactDismissed = true;
						nextTop = fullPanelTop;
					}
				}

				panelShell.style.top = nextTop + 'px';
				syncToggleState();
			}

			function syncPanelShellState(compactEligible, scrollTop) {
				if(panelCompactEligible && !compactEligible) {
					startupCompactDismissed = true;
				}
				if(typeof scrollTop === 'number' && scrollTop > 0) {
					startupCompactDismissed = true;
				}

				panelCompactEligible = !!compactEligible;
				panelScrollTop = Math.max(0, scrollTop || 0);
				applyPanelShellTop();
			}

			function focusElement(element) {
				if(!element || !element.focus) {
					return;
				}

				try {
					element.focus({ preventScroll: true });
				} catch(error) {
					try {
						element.focus();
					} catch(innerError) {}
				}
			}

			function focusGame() {
				focusElement(gameFrame);

				try {
					var gameWindow = gameFrame && gameFrame.contentWindow;
					var gameDocument = gameWindow && gameWindow.document;
					var canvas = gameDocument && (gameDocument.getElementById('canvas') || gameDocument.querySelector('canvas'));

					if(canvas) {
						if(!canvas.hasAttribute('tabindex')) {
							canvas.setAttribute('tabindex', '0');
						}
						focusElement(canvas);
					}

					if(gameWindow && gameWindow.focus) {
						gameWindow.focus();
					}
				} catch(error) {}
			}

			function setCollapsed(collapsed) {
				document.body.className = document.body.className.replace(/\blayout-collapsed\b/g, '').replace(/\s+/g, ' ');
				if(collapsed) {
					document.body.className += (document.body.className ? ' ' : '') + 'layout-collapsed';
				}

				try {
					localStorage.setItem(storageKey, collapsed ? '1' : '0');
				} catch(error) {}

				applyPanelShellTop();

				if(collapsed) {
					setTimeout(focusGame, 80);
				}
			}

			function collapseFromInteraction() {
				if(!isCollapsed()) {
					setCollapsed(true);
				}
			}

			function syncPanelLoaderBounds() {
				if(!panelLoader || !panelFrame) {
					return;
				}

				var top = 245;

				try {
					var frameHeight = panelFrame.getBoundingClientRect().height;
					var panelDocument = panelFrame.contentDocument || (panelFrame.contentWindow && panelFrame.contentWindow.document);
					var panelStart = panelDocument && (panelDocument.getElementById('tabs') || panelDocument.getElementById('content'));

					if(panelStart) {
						top = Math.round(panelStart.getBoundingClientRect().top);
					}

					if(frameHeight > 80) {
						top = Math.min(top, frameHeight - 80);
					}
				} catch(error) {}

				panelLoader.style.top = Math.max(0, top) + 'px';
			}

			function setPanelLoading(loading) {
				if(!panelShell) {
					return;
				}

				if(panelLoaderTimer) {
					clearTimeout(panelLoaderTimer);
					panelLoaderTimer = null;
				}

				panelShell.className = panelShell.className.replace(/\bpanel-loading\b/g, '').replace(/\s+/g, ' ');
				if(loading) {
					syncPanelLoaderBounds();
					panelLoaderStartedAt = Date.now();
					panelShell.className += (panelShell.className ? ' ' : '') + 'panel-loading';
					return;
				}

				panelLoaderStartedAt = 0;
			}

			function hidePanelLoader() {
				var elapsed = panelLoaderStartedAt ? Date.now() - panelLoaderStartedAt : 0;
				var delay = elapsed > 0 && elapsed < 220 ? 220 - elapsed : 0;
				panelLoaderTimer = setTimeout(function() {
					setPanelLoading(false);
				}, delay);
			}

			function openPanelUrl(url) {
				if(!panelFrame || !url) {
					return;
				}

				startupCompactDismissed = true;
				panelCompactEligible = false;
				panelScrollTop = 0;
				setCollapsed(false);
				setPanelLoading(true);
				panelFrame.src = url;
			}

			function syncPanelUrl(url) {
				if(!url) {
					return;
				}

				if(!panelSyncFrame) {
					panelSyncFrame = document.createElement('iframe');
					panelSyncFrame.id = 'panel-sync-frame';
					panelSyncFrame.title = 'Panel session sync';
					panelSyncFrame.setAttribute('aria-hidden', 'true');
					panelSyncFrame.style.position = 'absolute';
					panelSyncFrame.style.width = '1px';
					panelSyncFrame.style.height = '1px';
					panelSyncFrame.style.left = '-9999px';
					panelSyncFrame.style.top = '-9999px';
					panelSyncFrame.style.opacity = '0';
					panelSyncFrame.style.border = '0';
					panelSyncFrame.style.pointerEvents = 'none';
					document.body.appendChild(panelSyncFrame);
				}

				panelSessionAutoOpened = true;
				panelSyncFrame.src = url;
				setTimeout(pollPanelSession, 500);
			}

			function isMalformedShellUrl(url) {
				return /[\u0000-\u001f\u007f\ufffd]/.test(url);
			}

			function isAllowedShellUrl(url) {
				return /^(https?:\/\/|\/|\?|#|index\.php\b|panel-auth\.php\b)/i.test(url);
			}

			function isGetCoinsShellToken(url) {
				return url === 'icon-offset' || url === '/icon-offset' || url === '$hover !disabled' || url === 'UIWidget:onStyleApply' || url.indexOf('$hover') !== -1;
			}

			function pollPanelSession() {
				if(panelSessionPolling || !panelFrame || !window.fetch) {
					return;
				}

				panelSessionPolling = true;
				fetch('/panel-session.php', {
					cache: 'no-store',
					credentials: 'same-origin'
				}).then(function(response) {
					if(!response.ok) {
						return null;
					}

					return response.json();
				}).then(function(data) {
					panelSessionPolling = false;
					if(!data || typeof data.logged !== 'boolean') {
						return;
					}

					var previousLogged = panelSessionLogged;
					panelSessionLogged = data.logged;

					if(!data.logged) {
						panelSessionAutoOpened = false;
						return;
					}

					if(previousLogged === false && !panelSessionAutoOpened && typeof data.panel_url === 'string' && data.panel_url !== '') {
						panelSessionAutoOpened = true;
					}
				}).catch(function() {
					panelSessionPolling = false;
				});
			}

			window.__myaacCollapsePanel = collapseFromInteraction;

			window.addEventListener('message', function(event) {
				if(event.origin !== window.location.origin) {
					return;
				}

				if(event.data && event.data.type === 'myaac-panel-transparent-click') {
					collapseFromInteraction();
				}

				if(event.data && event.data.type === 'myaac-panel-loading-start') {
					if(event.data.skipLoader) {
						return;
					}
					setPanelLoading(true);
				}

				if(event.data && event.data.type === 'myaac-panel-loading-stop') {
					hidePanelLoader();
				}

				if(event.data && event.data.type === 'myaac-panel-shell-state') {
					syncPanelShellState(!!event.data.compactEligible, Number(event.data.scrollTop) || 0);
					syncPanelLoaderBounds();
				}

				if(event.data && event.data.type === 'myaac-shell-open-url') {
					var rawUrl = typeof event.data.url === 'string' ? event.data.url : '';
					if(!rawUrl) {
						return;
					}

					if(isGetCoinsShellToken(rawUrl)) {
						rawUrl = '/index.php/points';
					}

					if(isMalformedShellUrl(rawUrl)) {
						if(panelSessionLogged === true) {
							rawUrl = '/index.php/points';
						} else {
							setTimeout(pollPanelSession, 100);
							return;
						}
					}

					if(!isAllowedShellUrl(rawUrl)) {
						if(panelSessionLogged === true && rawUrl.length <= 64) {
							rawUrl = '/index.php/points';
						} else {
							setTimeout(pollPanelSession, 100);
							return;
						}
					}

					if(!isAllowedShellUrl(rawUrl)) {
						setTimeout(pollPanelSession, 100);
						return;
					}

					try {
						var parsedUrl = new URL(rawUrl, window.location.origin);
						var panelAuthToken = parsedUrl.searchParams.get('token');
						if(panelAuthToken && parsedUrl.pathname !== '/panel-auth.php' && /uth\.php$/i.test(parsedUrl.pathname)) {
							var fixedPanelAuthUrl = new URL('/panel-auth.php', window.location.origin);
							fixedPanelAuthUrl.searchParams.set('token', panelAuthToken);
							if(parsedUrl.searchParams.get('panel_sync') === '1') {
								fixedPanelAuthUrl.searchParams.set('panel_sync', '1');
							}
							parsedUrl = fixedPanelAuthUrl;
						}

						if(parsedUrl.origin === window.location.origin) {
							var isPanelSync = parsedUrl.searchParams.get('panel_sync') === '1';
							parsedUrl.searchParams.set('panel', '1');
							if(isPanelSync) {
								parsedUrl.searchParams.delete('panel_sync');
								syncPanelUrl(parsedUrl.pathname + parsedUrl.search + parsedUrl.hash);
								return;
							}
							startupCompactDismissed = true;
							panelCompactEligible = false;
							panelScrollTop = 0;
							if(!isPanelSync || !isCollapsed()) {
								setCollapsed(false);
								setPanelLoading(true);
							}
							if(panelFrame) {
								panelFrame.src = parsedUrl.pathname + parsedUrl.search + parsedUrl.hash;
							}
							return;
						}

						if(event.data.now) {
							window.location.assign(parsedUrl.toString());
						} else {
							window.open(parsedUrl.toString(), '_blank', 'noopener');
						}
					} catch(error) {}
				}
			});

			// Click anywhere on game area (transparent overlay) collapses panel
			var clickCatcher = document.getElementById('game-click-catcher');
			if(clickCatcher) {
				clickCatcher.addEventListener('pointerdown', collapseFromInteraction);
			}

			if(button) {
				button.onclick = function() {
					if(isCollapsed()) {
						startupCompactDismissed = true;
						panelScrollTop = 0;
						setCollapsed(false);
						return;
					}

					if(isStartupCompactState()) {
						startupCompactDismissed = true;
						panelScrollTop = 0;
						applyPanelShellTop();
						return;
					}

					setCollapsed(true);
				};
			}

			if(gameFrame) {
				gameFrame.onload = function() {
					reloadGuardEnabled = true;
					if(document.body.className.indexOf('layout-collapsed') !== -1) {
						setTimeout(focusGame, 300);
					}
				};
			}

			if(panelFrame) {
				panelFrame.addEventListener('load', function() {
					try {
						syncPanelShellState(isLatestNewsUrl(panelFrame.contentWindow.location.href), 0);
					} catch(error) {
						applyPanelShellTop();
					}
					syncPanelLoaderBounds();
					hidePanelLoader();
				});
			}

			window.addEventListener('resize', function() {
				applyPanelShellTop();
				syncPanelLoaderBounds();
			});

			setTimeout(pollPanelSession, 900);
			setInterval(pollPanelSession, 1500);

			try {
				// Always start with panel tab visible (not collapsed)
				// Ignore localStorage on page load to reset to default state each time
				setCollapsed(false);
			} catch(error) {
				setCollapsed(false);
			}

			applyPanelShellTop();
		})();
		</script>
	</body>
</html>
<?php
	return;
}
?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" class="panel-root">
	<head>
		<?php echo template_place_holder('head_start'); ?>
		<link rel="stylesheet" href="<?php echo $template_path; ?>/style.css?v=myaac-shell21" type="text/css" />
		<script type="text/javascript">
			<?php
				$twig->display('menu.js.html.twig', array('categories' => $config['menu_categories']));
			?>
		</script>
		<script type="text/javascript" src="tools/basic.js"></script>
		<script type="text/javascript">
			<?php require 'javascript.php'; ?>
		</script>
		<?php echo template_place_holder('head_end'); ?>
	</head>

	<body class="panel-mode" onload="initMenu();">
		<?php echo template_place_holder('body_start'); ?>
		<div id="top"></div>
		<div id="page">
		<!-- Keep all on center of browser -->

			<!-- Header Section -->
			<div id="header"></div>
			<!-- End -->

			<!-- Menu Section -->
			<div id="tabs">
				<?php
				foreach($config['menu_categories'] as $id => $cat) {
					if($id != MENU_CATEGORY_SHOP || $config['gifts_system']) { ?>
				<span id="<?php echo $cat['id']; ?>" onclick="menuSwitch('<?php echo $cat['id']; ?>');"><?php echo $cat['name']; ?></span>
				<?php
					}
				}
				?>
			</div>

			<div id="mainsubmenu">
				<?php
				foreach($menus as $category => $menu) {
					if(!isset($menus[$category])) {
						continue;
					}

					echo '<div id="' . $config['menu_categories'][$category]['id'] . '-submenu">';

					$size = count($menus[$category]);
					$i = 0;

					foreach($menus[$category] as $link) {
						echo '<a href="' . $link['link_full'] . '" ' . $link['target_blank'] . ' ' . $link['style_color'] . '>' . $link['name'] . '</a>';

						if(++$i != $size) {
							echo '<span class="separator"></span>';
						}
					}

					echo '</div>';
				}
				?>
			</div>
			<!-- End -->

			<!-- Content Section -->
			<div id="content">
				<div id="margins">
					<table cellpadding="0" cellspacing="0" border="0" width="100%">
						<tr>
							<td><a href="<?php echo getLink('news'); ?>"><?php echo $config['lua']['serverName']; ?></a> &raquo; <?php echo $title; ?></td>
							<td>
							<?php
							if($status['online'])
								echo '
								<span style="color: green"><b>Server Online</b></span> &raquo;
								Players Online: ' . $status['players'] . ' / ' . $status['playersMax'] . ' &raquo;
								Monsters: ' . $status['monsters'] . ' &raquo; Uptime: ' . (isset($status['uptimeReadable']) ? $status['uptimeReadable'] : 'Unknown') . '';
							else
								echo '<span style="color: red"><b>Server Offline</b></span>';
							?>
							</td>
						</tr>
					</table>
					<hr noshade="noshade" size="1" />
					<div class="Content"><div id="ContentHelper">
					<?php echo tickers() . template_place_holder('center_top') . $content; ?>
					</div></div>
				</div>
			</div>
			<div id="content-bot"></div>
			<!-- End -->

		<!-- End -->
		</div>
		<script type="text/javascript">
		(function() {
			var stickyTrigger = null;

			function getScroller() {
				return document.scrollingElement || document.documentElement || document.body;
			}

			function measureStickyTrigger() {
				var tabs = document.getElementById('tabs');
				var scroller = getScroller();
				if(!tabs || !scroller) {
					return 0;
				}

				var wasStuck = document.body.classList.contains('panel-header-stuck');
				if(wasStuck) {
					document.body.classList.remove('panel-header-stuck');
				}

				var trigger = tabs.getBoundingClientRect().top + scroller.scrollTop;

				if(wasStuck) {
					document.body.classList.add('panel-header-stuck');
				}

				return Math.max(0, Math.round(trigger));
			}

			function syncStickyHeader() {
				var scroller = getScroller();
				if(!scroller) {
					return;
				}

				if(stickyTrigger === null) {
					stickyTrigger = measureStickyTrigger();
				}

				var stuck = scroller.scrollTop >= stickyTrigger;
				document.body.classList.toggle('panel-header-stuck', stuck);
			}

			function syncStickyHeaderOnResize() {
				stickyTrigger = measureStickyTrigger();
				syncStickyHeader();
			}

			// Detect layout changes and recalculate sticky trigger
			if(window.ResizeObserver) {
				try {
					var tabs = document.getElementById('tabs');
					if(tabs) {
						var resizeObserver = new ResizeObserver(function() {
							syncStickyHeaderOnResize();
						});
						resizeObserver.observe(tabs);
					}
				} catch(error) {}
			}

			function panelizeUrl(href) {
				var url;
				try {
					url = new URL(href, window.location.href);
				} catch(error) {
					return null;
				}

				if(url.origin !== window.location.origin) {
					return null;
				}
				if(url.pathname.indexOf('/game/') === 0 || url.pathname.indexOf('/install/') === 0) {
					return null;
				}
				url.searchParams.set('panel', '1');
				return url.href;
			}

			function notifyPanelLoadingStart() {
				try {
					window.parent.postMessage({ type: 'myaac-panel-loading-start' }, window.location.origin);
				} catch(error) {}
			}

			function notifyPanelLoadingStop() {
				try {
					window.parent.postMessage({ type: 'myaac-panel-loading-stop' }, window.location.origin);
				} catch(error) {}
			}

			function isLatestNewsPanel() {
				var path = window.location.pathname.replace(/\/+$/, '');
				if(path === '') {
					path = '/';
				}

				var isRoot = path === '/' || path === '/index.php';
				var isLatestNews = /\/news$/.test(path) || /\/index\.php\/news$/.test(path);
				var isNewsArchive = /\/news\/archive$/.test(path) || /\/index\.php\/news\/archive$/.test(path);
				var isChangeLog = /\/change-log$/.test(path) || /\/index\.php\/change-log$/.test(path);

				return (isRoot || isLatestNews) && !isNewsArchive && !isChangeLog;
			}

			function notifyShellState() {
				try {
					var scroller = getScroller();
					window.parent.postMessage({
						type: 'myaac-panel-shell-state',
						compactEligible: isLatestNewsPanel(),
						scrollTop: scroller ? scroller.scrollTop : 0
					}, window.location.origin);
				} catch(error) {}
			}

			document.addEventListener('click', function(event) {
				var anchor = event.target;
				while(anchor && anchor.tagName !== 'A') {
					anchor = anchor.parentNode;
				}
				if(!anchor) {
					return;
				}

				var href = anchor.getAttribute('href');
				if(!href || href.charAt(0) === '#' || href.indexOf('javascript:') === 0) {
					return;
				}
				if(anchor.target && anchor.target !== '_self') {
					return;
				}

				var panelUrl = panelizeUrl(href);
				if(panelUrl) {
					notifyPanelLoadingStart();
					anchor.href = panelUrl;
				}
			}, true);

			document.addEventListener('submit', function(event) {
				var form = event.target;
				if(!form || form.tagName !== 'FORM') {
					return;
				}

				var target = (form.getAttribute('target') || '_self').toLowerCase();
				var skipLoader = form.getAttribute('data-skip-panel-loader') === '1' || target !== '_self';

				var panelUrl = panelizeUrl(form.getAttribute('action') || window.location.href);
				if(!panelUrl) {
					return;
				}

				form.action = panelUrl;
				if(!skipLoader) {
					notifyPanelLoadingStart();
				} else {
					notifyPanelLoadingStop();
				}
				if(!form.querySelector('input[name="panel"]')) {
					var input = document.createElement('input');
					input.type = 'hidden';
					input.name = 'panel';
					input.value = '1';
					form.appendChild(input);
				}
			}, true);

			window.name = 'myaac-panel';

			function notifyTransparentPanelClick(event) {
				var tabs = document.getElementById('tabs');
				if(!tabs) {
					return;
				}

				if(event.clientY < tabs.getBoundingClientRect().top) {
					try {
						window.parent.postMessage({ type: 'myaac-panel-transparent-click' }, window.location.origin);
					} catch(error) {}
				}
			}

			document.addEventListener('pointerdown', notifyTransparentPanelClick, true);
			document.addEventListener('mousedown', notifyTransparentPanelClick, true);
			document.addEventListener('touchstart', function(event) {
				if(event.touches && event.touches.length > 0) {
					notifyTransparentPanelClick(event.touches[0]);
				}
			}, { passive: true, capture: true });

			syncStickyHeader();
			notifyShellState();
			window.addEventListener('scroll', syncStickyHeader, { passive: true });
			window.addEventListener('scroll', notifyShellState, { passive: true });
			window.addEventListener('resize', syncStickyHeaderOnResize);
			window.addEventListener('resize', notifyShellState);
		})();
		</script>
		<?php echo template_place_holder('body_end'); ?>
	</body>
</html>
