<?php
/**
 * Highscores
 *
 * @package    MyAAC
 * @author     Gesior <jerzyskalski@wp.pl>
 * @author     Slawkens <slawkens@gmail.com>
 * @copyright  2019 MyAAC
 * @link       https://my-aac.org
 */

use MyAAC\Cache\Cache;
use MyAAC\Models\Player;
use MyAAC\Models\PlayerDeath;
use MyAAC\Models\PlayerKillers;

defined('MYAAC') or die('Direct access not allowed!');
$title = 'Highscores';

//<editor-fold desc="LADOWANIE DANYCH I LOGIKA" defaultstate="collapsed">
$settingHighscoresCountryBox = setting('core.highscores_country_box');
if(config('account_country') && $settingHighscoresCountryBox) {
    require SYSTEM . 'countries.conf.php';
}

$highscoresTTL = setting('core.highscores_cache_ttl');

$list = urldecode($_GET['list'] ?? 'experience');
$page = $_GET['page'] ?? 1;
$vocation = urldecode($_GET['vocation'] ?? 'all');

if(!is_numeric($page) || $page < 1 || $page > PHP_INT_MAX) {
    $page = 1;
}

$query = Player::query();

$configVocations = config('vocations');
$configVocationsAmount = config('vocations_amount');

// START of modification to add Monk
if (!isset($configVocations[9])) {
    $configVocations[9] = 'Monk';
}
// END of modification

$vocationId = null;
if($vocation !== 'all') {
    foreach($configVocations as $id => $name) {
        if(strtolower($name) == $vocation) {
            $vocationId = $id;
            $add_vocs = [$id];

            if ($id !== 0) {
                $i = $id + $configVocationsAmount;
                while (isset($configVocations[$i])) {
                    $add_vocs[] = $i;
                    $i += $configVocationsAmount;
                }
            }

            $query->whereIn('players.vocation', $add_vocs);
            break;
        }
    }
}

$skill = POT::SKILL__LEVEL;
if(is_numeric($list))
{
    $list = (int) $list;
    if($list >= POT::SKILL_FIRST && $list <= POT::SKILL__LAST)
        $skill = $list;
}
else
{
    switch($list)
    {
        case 'fist': $skill = POT::SKILL_FIST; break;
        case 'club': $skill = POT::SKILL_CLUB; break;
        case 'sword': $skill = POT::SKILL_SWORD; break;
        case 'axe': $skill = POT::SKILL_AXE; break;
        case 'distance': $skill = POT::SKILL_DIST; break;
        case 'shield': $skill = POT::SKILL_SHIELD; break;
        case 'fishing': $skill = POT::SKILL_FISH; break;
        case 'level':
        case 'experience': $skill = POT::SKILL_LEVEL; break;
        case 'magic': $skill = POT::SKILL__MAGLEVEL; break;
        case 'frags': if(setting('core.highscores_frags')) $skill = SKILL_FRAGS; break;
        case 'balance': if(setting('core.highscores_balance')) $skill = SKILL_BALANCE; break;
    }
}

$promotion = '';
if($db->hasColumn('players', 'promotion'))
    $promotion = ',players.promotion';

$outfit_addons = false;
$outfit = '';

$settingHighscoresOutfit = setting('core.highscores_outfit');

if($settingHighscoresOutfit) {
    $outfit = ', lookbody, lookfeet, lookhead, looklegs, looktype';
    if($db->hasColumn('players', 'lookaddons')) {
        $outfit .= ', lookaddons';
        $outfit_addons = true;
    }
}

$configHighscoresPerPage = setting('core.highscores_per_page');
$limit = $configHighscoresPerPage + 1;

$highscores = [];
$needReCache = true;
$cacheKey = 'highscores_' . $skill . '_' . $vocation . '_' . $page . '_' . $configHighscoresPerPage;

$cache = Cache::getInstance();
if ($cache->enabled() && $highscoresTTL > 0) {
    $tmp = '';
    if ($cache->fetch($cacheKey, $tmp)) {
        $highscores = unserialize($tmp);
        $needReCache = false;
    }
}

$offset = ($page - 1) * $configHighscoresPerPage;
$query->join('accounts', 'accounts.id', '=', 'players.account_id')
    ->withOnlineStatus()
    ->whereNotIn('players.id', setting('core.highscores_ids_hidden'))
    ->notDeleted()
    ->where('players.group_id', '<', setting('core.highscores_groups_hidden'))
    ->limit($limit)
    ->offset($offset)
    ->selectRaw('accounts.country, players.id, players.name, players.account_id, players.level, players.vocation' . $outfit . $promotion)
    ->orderByDesc('value');

if (empty($highscores)) {
    if ($skill >= POT::SKILL_FIRST && $skill <= POT::SKILL_LAST) { // skills
        if ($db->hasColumn('players', 'skill_fist')) {// tfs 1.0
            $skill_ids = array(
                POT::SKILL_FIST => 'skill_fist', POT::SKILL_CLUB => 'skill_club', POT::SKILL_SWORD => 'skill_sword',
                POT::SKILL_AXE => 'skill_axe', POT::SKILL_DIST => 'skill_dist', POT::SKILL_SHIELD => 'skill_shielding',
                POT::SKILL_FISH => 'skill_fishing',
            );
            $query->addSelect($skill_ids[$skill] . ' as value');
        } else {
            $query->join('player_skills', 'player_skills.player_id', '=', 'players.id')->where('skillid', $skill)->addSelect('player_skills.value as value');
        }
    } else if ($skill == SKILL_FRAGS) {
        if ($db->hasTable('player_killers')) {
            $query->addSelect(['value' => PlayerKillers::whereColumn('player_killers.player_id', 'players.id')->selectRaw('COUNT(*)')]);
        } else {
            $query->addSelect(['value' => PlayerDeath::unjustified()->whereColumn('player_deaths.killed_by', 'players.name')->selectRaw('COUNT(*)')]);
        }
    } else if ($skill == SKILL_BALANCE) {
        $query->addSelect('players.balance as value');
    } else {
        if ($skill == POT::SKILL__MAGLEVEL) {
            $query->addSelect('players.maglevel as value', 'players.manaspent')->orderBy('manaspent', 'desc');
        } else { // level
            $query->addSelect('players.level as value', 'players.experience')->orderBy('experience', 'desc');
            $list = 'experience';
        }
    }

    $highscores = $query->get()->map(function($row) {
        $tmp = $row->toArray();
        $tmp['online'] = $row->online_status;
        $tmp['vocation_name'] = $row->vocation_name;
        $tmp['outfit_url'] = $row->outfit_url;
        unset($tmp['online_table']);
        return $tmp;
    })->toArray();
}

if ($highscoresTTL > 0 && $cache->enabled() && $needReCache) {
    $cache->set($cacheKey, serialize($highscores), $highscoresTTL * 60);
}

$show_link_to_next_page = false;
$i = 0;

foreach($highscores as $id => &$player) {
    if(++$i <= $configHighscoresPerPage) {
        $player['link'] = getPlayerLink($player['name'], false);
        $player['flag'] = getFlagImage($player['country']);
        if($settingHighscoresOutfit) {
            $player['outfit_img'] = '<img class="outfit-image" src="' . $player['outfit_url'] . '" alt="" />';
        }
        $player['rank'] = $offset + $i;

        // Failsafe to make sure vocation name is always set
        if(!isset($player['vocation_name'])) {
            $player['vocation_name'] = $configVocations[$player['vocation']] ?? 'Unknown';
        }
    } else {
        unset($highscores[$id]);
        $show_link_to_next_page = true;
        break;
    }
}

$linkPreviousPage = '';
if($page > 1) {
    $linkPreviousPage = getLink('highscores') . '/' . $list . ($vocation !== 'all' ? '/' . $vocation : '') . '/' . ($page - 1);
}

$linkNextPage = '';
if($show_link_to_next_page) {
    $linkNextPage = getLink('highscores') . '/' . $list . ($vocation !== 'all' ? '/' . $vocation : '') . '/' . ($page + 1);
}

$types = array(
    'experience' => 'Experience', 'magic' => 'Magic', 'shield' => 'Shielding', 'distance' => 'Distance',
    'club' => 'Club', 'sword' => 'Sword', 'axe' => 'Axe', 'fist' => 'Fist', 'fishing' => 'Fishing',
);

if(setting('core.highscores_frags')) $types['frags'] = 'Frags';
if(setting('core.highscores_balance')) $types['balance'] = 'Balance';

$template_vocations = [];
foreach($configVocations as $id => $name) {
    if($id > 0 && ($id <= $configVocationsAmount || $id == 9)) {
        $template_vocations[$id] = $name;
    }
}

if ($highscoresTTL > 0 && $cache->enabled()) {
    echo '<small>*Note: Highscores are updated every' . ($highscoresTTL > 1 ? ' ' . $highscoresTTL : '') . ' minute' . ($highscoresTTL > 1 ? 's' : '') . '.</small><br/><br/>';
}

$skillName = ($skill == SKILL_FRAGS ? 'Frags' : ($skill == SKILL_BALANCE ? 'Balance' : getSkillName($skill)));
$levelName = ($skill != SKILL_FRAGS && $skill != SKILL_BALANCE ? 'Level' : ($skill == SKILL_BALANCE ? 'Balance' : 'Frags'));
//</editor-fold>
?>

<!-- USUNIĘTO SEKCJĘ TOP 5 GRACZY -->
<style type="text/css">
    /* --- STYLE DLA GŁÓWNEGO RANKINGU --- */
    .highscores-main-container {
        background-color: #191c21;
        border: 1px solid rgb(19,20,23);
        border-radius: 8px;
        padding: 20px;
    }
    .highscores-title {
        text-align: center;
        font-size: 1.5em;
        color: #b39062;
        margin: 0 0 20px 0;
        font-weight: bold;
    }
    .highscores-filters {
        display: flex;
        justify-content: center;
        gap: 20px;
        margin-bottom: 25px;
        flex-wrap: wrap;
    }
    .highscores-filters .filter-group {
        display: flex;
        flex-direction: column;
        gap: 5px;
    }
    .highscores-filters label {
        font-size: 0.9em;
        color: #aaa;
        text-align: center;
    }
    .highscores-filters select {
        background-color: rgb(30,33,40);
        color: rgb(155,162,177);
        border: 1px solid rgb(19,20,23);
        border-radius: 4px;
        padding: 8px;
    }
    .highscores-table-header, .highscores-row {
        display: flex;
        align-items: center;
        padding: 10px 15px;
        border-bottom: 1px solid rgb(19,20,23);
    }
    .highscores-table-header {
        color: #b39062;
        font-weight: bold;
        background-color: rgba(30,33,40, 0.5);
    }
    .highscores-row {
        background-color: rgb(30,33,40);
        transition: background-color 0.2s ease;
    }
    .highscores-row:hover {
        background-color: #252930;
    }
    .highscores-row:last-child {
        border-bottom: none;
    }
    .col-rank { width: 8%; }
    .col-outfit { width: 10%; text-align: center; }
    .col-name { flex-grow: 1; }
    .col-level { width: 15%; text-align: center; }
    .col-vocation { width: 15%; text-align: center; }
    .outfit-image {
        width: 32px;
        height: 32px;
        image-rendering: pixelated;
    }
    .player-name-link {
        text-decoration: none;
        font-weight: bold;
    }
    .player-name-link.online { color: #28a745; }
    .player-name-link.offline { color: #dc3545; }
    .pagination-links {
        display: flex;
        justify-content: space-between;
        margin-top: 20px;
    }
    .pagination-links a {
        color: #b39062;
        text-decoration: none;
        font-weight: bold;
    }
</style>

<!-- GŁÓWNA TABELA RANKINGU -->
<div class="highscores-main-container">
    <h2 class="highscores-title">Ranking for <?php echo $skillName; ?><?php if ($vocation !== 'all') echo ' (' . htmlspecialchars($vocation) . ')'; ?></h2>

    <div class="highscores-filters">
        <div class="filter-group">
            <label for="skillFilter">Choose a Skill</label>
            <select onchange="location = this.value;" id="skillFilter">
                <?php foreach ($types as $link => $name): ?>
                    <option value="<?php echo getLink('highscores') . '/' . urlencode($link) . ($vocation !== 'all' ? '/' . urlencode(strtolower($vocation)) : ''); ?>" <?php if ($list == $link) echo 'selected'; ?>><?php echo $name; ?></option>
                <?php endforeach; ?>
            </select>
        </div>
        <div class="filter-group">
            <label for="vocationFilter">Choose a Vocation</label>
            <select onchange="location = this.value;" id="vocationFilter">
                <option value="<?php echo getLink('highscores') . '/' . urlencode($list); ?>">[ALL]</option>
                <?php foreach ($template_vocations as $id => $name): ?>
                    <option value="<?php echo getLink('highscores') . '/' . urlencode($list) . '/' . urlencode(strtolower($name)); ?>" <?php if ($vocationId !== null && $vocationId == $id) echo 'selected'; ?>><?php echo $name; ?></option>
                <?php endforeach; ?>
            </select>
        </div>
    </div>

    <div class="highscores-list-container">
        <div class="highscores-table-header">
            <div class="col-rank">Rank</div>
            <?php if (setting('core.highscores_outfit')): ?><div class="col-outfit">Outfit</div><?php endif; ?>
            <div class="col-name">Name</div>
            <div class="col-level"><?php echo $levelName; ?></div>
            <div class="col-vocation">Vocation</div>
        </div>

        <?php if (empty($highscores)): ?>
            <div class="highscores-row" style="justify-content: center;">No records yet.</div>
        <?php else: ?>
            <?php foreach ($highscores as $player): ?>
            <div class="highscores-row">
                <div class="col-rank"><?php echo $player['rank']; ?>.</div>
                <?php if (setting('core.highscores_outfit')): ?>
                    <div class="col-outfit"><?php echo str_replace('position:absolute;margin-top:-45px;margin-left:-25px;', '', $player['outfit_img']); ?></div>
                <?php endif; ?>
                <div class="col-name">
                    <a href="<?php echo $player['link']; ?>" class="player-name-link <?php echo ($player['online'] > 0 ? 'online' : 'offline'); ?>">
                        <?php echo htmlspecialchars($player['name']); ?>
                    </a>
                </div>
                <div class="col-level">
                    <?php
                        if ($skill == POT::SKILL__LEVEL) {
                            echo $player['level'];
                        } else {
                            echo $player['value'];
                        }
                    ?>
                </div>
                <div class="col-vocation"><?php echo $player['vocation_name']; ?></div>
            </div>
            <?php endforeach; ?>
        <?php endif; ?>
    </div>

    <div class="pagination-links">
        <div>
            <?php if (!empty($linkPreviousPage)): ?>
                <a href="<?php echo $linkPreviousPage; ?>">« Previous Page</a>
            <?php endif; ?>
        </div>
        <div>
            <?php if (!empty($linkNextPage)): ?>
                <a href="<?php echo $linkNextPage; ?>">Next Page »</a>
            <?php endif; ?>
        </div>
    </div>
</div>
