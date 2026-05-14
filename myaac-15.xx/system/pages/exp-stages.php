<?php
/**
 * Experience stages
 *
 * @package   MyAAC
 * @author    Gesior <jerzyskalski@wp.pl>
 * @author    Slawkens <slawkens@gmail.com>
 * @copyright 2019 MyAAC
 * @link      https://my-aac.org
 */
defined('MYAAC') or die('Direct access not allowed!');
$title = 'Experience Stages';

function elderaReadLuaConfigValue($file, $key) {
	if(!file_exists($file)) {
		return null;
	}

	$content = file_get_contents($file);
	if($content === false) {
		return null;
	}

	if(!preg_match('/^\s*' . preg_quote($key, '/') . '\s*=\s*([^\r\n]+)/m', $content, $match)) {
		return null;
	}

	$value = preg_replace('/\s*--.*$/', '', trim($match[1]));
	return trim($value, " \t\n\r\0\x0B\"'");
}

function elderaToBoolean($value) {
	if(is_bool($value)) {
		return $value;
	}

	if(is_numeric($value)) {
		return (int)$value > 0;
	}

	if($value === null) {
		return false;
	}

	$value = strtolower(trim((string)$value, " \t\n\r\0\x0B\"'"));
	return $value === 'true' || $value === 'yes' || $value === '1';
}

function elderaExtractLuaTable($content, $tableName) {
	$start = strpos($content, $tableName);
	if($start === false) {
		return null;
	}

	$open = strpos($content, '{', $start);
	if($open === false) {
		return null;
	}

	$depth = 0;
	$length = strlen($content);
	for($index = $open; $index < $length; $index++) {
		$char = $content[$index];
		if($char === '{') {
			$depth++;
		} else if($char === '}') {
			$depth--;
			if($depth === 0) {
				return substr($content, $open, $index - $open + 1);
			}
		}
	}

	return null;
}

function elderaLoadLuaStages($file) {
	if(!file_exists($file)) {
		return [];
	}

	$content = file_get_contents($file);
	if($content === false) {
		return [];
	}

	$table = elderaExtractLuaTable($content, 'experienceStages');
	if($table === null) {
		return [];
	}

	$stages = [];
	if(preg_match_all('/\{\s*minlevel\s*=\s*(\d+)\s*,\s*(?:maxlevel\s*=\s*(\d+)\s*,\s*)?multiplier\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*,?\s*\}/', $table, $matches, PREG_SET_ORDER)) {
		foreach($matches as $stage) {
			$stages[] = [
				'levels' => $stage[1] . (isset($stage[2]) && $stage[2] !== '' ? '-' . $stage[2] : '+'),
				'multiplier' => $stage[3]
			];
		}
	}

	return $stages;
}

function elderaFindStagesFile($config) {
	$candidates = [
		$config['data_path'] . 'stages.lua',
		$config['server_path'] . 'data/stages.lua',
	];

	if(isset($config['lua']['coreDirectory'])) {
		$coreDirectory = trim($config['lua']['coreDirectory'], " \t\n\r\0\x0B\"'");
		if($coreDirectory !== '') {
			$candidates[] = $config['server_path'] . rtrim($coreDirectory, '/') . '/stages.lua';
		}
	}

	foreach($candidates as $candidate) {
		if(file_exists($candidate)) {
			return $candidate;
		}
	}

	return $candidates[0];
}

if(file_exists($config['data_path'] . 'XML/stages.xml')) {
	$stages = new DOMDocument();
	$stages->load($config['data_path'] . 'XML/stages.xml');
}

$configLuaPath = $config['server_path'] . 'config.lua';
$rateUseStages = elderaReadLuaConfigValue($configLuaPath, 'rateUseStages');
$stagesEnabled = $rateUseStages !== null ? elderaToBoolean($rateUseStages) : false;
if(!$stagesEnabled && isset($config['lua']['rateUseStages'])) {
	$stagesEnabled = elderaToBoolean($config['lua']['rateUseStages']);
}
if(!$stagesEnabled && isset($config['lua']['experienceStages'])) {
	$stagesEnabled = elderaToBoolean($config['lua']['experienceStages']);
}

$stagesArray = [];
if($stagesEnabled) {
	$stagesArray = elderaLoadLuaStages(elderaFindStagesFile($config));
}

if(!$stagesEnabled)
{
	$enabled = false;

	if(isset($stages)) {
		foreach($stages->getElementsByTagName('config') as $node) {
			/** @var DOMElement $node */
			if($node->getAttribute('enabled'))
				$enabled = true;
		}
	}

	if(!$enabled) {
		$rate_exp = 'not set';
		$configRateExp = elderaReadLuaConfigValue($configLuaPath, 'rateExp');
		if($configRateExp !== null)
			$rate_exp = $configRateExp;
		else if(isset($config['lua']['rateExperience']))
			$rate_exp = $config['lua']['rateExperience'];
		else if(isset($config['lua']['rateExp']))
			$rate_exp = $config['lua']['rateExp'];
		else if(isset($config['lua']['rate_exp']))
			$rate_exp = $config['lua']['rate_exp'];

		echo 'Server is not configured to use experience stages.<br/>Current experience rate is: <b>x' .  $rate_exp . '</b>';
		return;
	}
}

if(empty($stagesArray) && isset($stages))
{
	foreach($stages->getElementsByTagName('stage') as $stage)
	{
		/** @var DOMElement $stage */
		$maxLevel = $stage->getAttribute('maxlevel');
		$stagesArray[] = [
			'levels' => $stage->getAttribute('minlevel') . (isset($maxLevel[0]) ? '-' . $maxLevel : '+'),
			'multiplier' => $stage->getAttribute('multiplier')
		];
	}
}

if(empty($stagesArray))
{
	echo 'Error: cannot load experience stages from <b>data/stages.lua</b> or <b>stages.xml</b>!';
	return;
}

$twig->display('experience_stages.html.twig', ['stages' => $stagesArray]);
