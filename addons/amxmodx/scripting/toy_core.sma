#define TOY_CORE_PLUGIN

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <engine>
#include <hamsandwich>
#include <toys_system>

#define PLUGIN_NAME     "[Adventures] Toy Core"
#define PLUGIN_VERSION  "2.0"
#define PLUGIN_AUTHOR   "medusa"

#define MAX_TOYS        64
#define MAX_POSITIONS   512
#define MAX_MODEL_LEN   128
#define MAX_NAME_LEN    64
#define MAX_SOUND_LEN   64
#define MAX_EDICTS      2048

new g_toy_model[MAX_TOYS][MAX_MODEL_LEN]
new g_toy_name[MAX_TOYS][MAX_NAME_LEN]
new g_toy_sound[MAX_TOYS][MAX_SOUND_LEN]
new g_toy_skin[MAX_TOYS]
new g_toy_body[MAX_TOYS]
new g_toy_sequence[MAX_TOYS]
new Float:g_toy_framerate[MAX_TOYS]
new g_toy_rarity[MAX_TOYS]
new g_toy_count = 0

new Float:g_pos_origin[MAX_POSITIONS][3]
new Float:g_pos_yaw[MAX_POSITIONS]
// Привязка точки спавна к ТИРУ (не конкретной игрушке):
//   -1 = любой тир (случайно по весам g_weight_*)
//   0  = common, 1 = rare, 2 = epic, 3 = legendary
// В ini пишется как строка: common / rare / epic / legendary / any (или пусто).
new g_pos_bound_rarity[MAX_POSITIONS]
new g_pos_spawn_mode[MAX_POSITIONS]
new g_pos_count = 0

new bool:g_is_toy_ent[MAX_EDICTS]
new bool:g_is_alive[MAX_PLAYERS + 1]

new g_fullpack_fwd = -1

new g_ent_list[MAX_POSITIONS]
new g_ent_toy_idx[MAX_POSITIONS]
new g_ent_pos_idx[MAX_POSITIONS]
new g_ent_count = 0

new g_legendary_spawned = 0
new g_map_count_from_file = -1

new g_weight_common    = TOY_RARITY_WEIGHT_COMMON
new g_weight_rare      = TOY_RARITY_WEIGHT_RARE
new g_weight_epic      = TOY_RARITY_WEIGHT_EPIC
new g_weight_legendary = TOY_RARITY_WEIGHT_LEGENDARY

new cvar_enabled
new cvar_count
new cvar_logging
new cvar_hide_dead

new Trie:g_picked_ids = Invalid_Trie
new bool:g_picked_slot[33]
new bool:g_spawn_busy
new bool:g_pickup_busy
new bool:g_positions_readonly
new bool:g_positions_loaded
new g_fwd_collected
new g_fwd_pickup
new g_fwd_spawned
new g_fwd_map_complete

new bool:g_spawn_used_toy[MAX_TOYS]

new g_logfile[192]

public plugin_natives()
{
    register_library("toys_system")
    register_native("toy_get_pos_mode", "native_get_pos_mode")
    register_native("toy_get_pos_count_by_mode", "native_get_pos_count_by_mode")
    register_native("toy_set_pos_mode", "native_set_pos_mode")
    register_native("toy_can_set_position", "native_can_set_position")

    register_native("toy_get_toy_idx",       "native_get_toy_idx",       0)
    register_native("toy_get_name",          "native_get_name",          0)
    register_native("toy_get_rarity",        "native_get_rarity",        0)
    register_native("toy_get_model",         "native_get_model",         0)
    register_native("toy_get_body",          "native_get_body",          0)
    register_native("toy_get_skin",          "native_get_skin",          0)
    register_native("toy_get_type_count",    "native_get_type_count",    0)
    register_native("toy_get_spawned_count", "native_get_spawned_count", 0)
    register_native("toy_get_pos_count",     "native_get_pos_count",     0)
    register_native("toy_get_pos_data",      "native_get_pos_data",      0)
    register_native("toy_add_position",      "native_add_position",      0)
    register_native("toy_remove_position",   "native_remove_position",   0)
    register_native("toy_update_position",   "native_update_position",   0)
    register_native("toy_save_positions",    "native_save_positions",    0)
    register_native("toy_reload_positions",  "native_reload_positions",  0)
    register_native("toy_remove_entity",     "native_remove_entity",     0)
    register_native("toy_spawn_at_position", "native_spawn_at_position", 0)
    register_native("toy_respawn_all",       "native_respawn_all",       0)
    register_native("toy_trigger_pickup",    "native_trigger_pickup",    0)
    register_native("toy_get_map_file_count","native_get_map_file_count",0)
    register_native("toy_set_map_file_count","native_set_map_file_count",0)
    register_native("toy_clear_positions",   "native_clear_positions",   0)
}

#define toy_log(%0) if(get_pcvar_num(cvar_logging)) log_to_file(g_logfile, %0)

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR)

    cvar_enabled   = register_cvar("toy_enabled",   "1")
    cvar_count     = register_cvar("toy_count",     "5")
    cvar_hide_dead = register_cvar("toy_hide_dead", "1")
    hook_cvar_change(cvar_hide_dead, "on_hide_dead_change")
    if(!cvar_logging)
        cvar_logging = register_cvar("toy_logging", "0")
    register_cvar("toy_admin_flags", "g") //acces amx_cvar

    register_dictionary("toy_system.txt")
    g_picked_ids = TrieCreate()

    RegisterHam(Ham_Spawn,  "player", "ham_player_spawn_post",  1)
    RegisterHam(Ham_Killed, "player", "ham_player_killed_post", 1)

    g_fwd_collected = CreateMultiForward("toy_on_collected", ET_IGNORE, FP_CELL, FP_CELL)
    g_fwd_pickup       = CreateMultiForward("toy_on_pickup",            ET_STOP,   FP_CELL, FP_CELL, FP_CELL)
    g_fwd_spawned      = CreateMultiForward("toy_on_spawned",           ET_IGNORE, FP_CELL, FP_CELL, FP_CELL)
    g_fwd_map_complete = CreateMultiForward("toy_on_map_spawn_complete", ET_IGNORE, FP_CELL)

    new logsdir[128]
    get_localinfo("amxx_logs", logsdir, charsmax(logsdir))
    formatex(g_logfile, charsmax(g_logfile), "%s/toy_system.log", logsdir)

    toy_log("[ToyCore] Initialized v%s", PLUGIN_VERSION)
}

public plugin_precache()
{
    if(!cvar_logging)
        cvar_logging = register_cvar("toy_logging", "0")

    new logsdir[128]
    get_localinfo("amxx_logs", logsdir, charsmax(logsdir))
    formatex(g_logfile, charsmax(g_logfile), "%s/toy_system.log", logsdir)
    precache_sound(TOY_DEFAULT_PICKUP_SOUND)
    load_toys_config()

    new i
    for(i = 0; i < g_toy_count; i++)
    {
        if(g_toy_model[i][0])
        {
            if(file_exists(g_toy_model[i], true)) precache_model(g_toy_model[i])
            else
            {
                log_amx("Missing toy model: %s (type %d disabled)", g_toy_model[i], i)
                g_toy_model[i][0] = EOS
            }
        }
        if(g_toy_sound[i][0])
        {
            new soundpath[192]
            formatex(soundpath, charsmax(soundpath), "sound/%s", g_toy_sound[i])
            if(file_exists(soundpath, true)) precache_sound(g_toy_sound[i])
            else g_toy_sound[i][0] = EOS
        }
    }
}

public plugin_cfg()
{
    load_positions()
    set_task(0.1, "task_map_start")
}

public task_map_start()
{
    new mapname[64]
    get_mapname(mapname, charsmax(mapname))
    toy_log("--- %s ---", mapname)
    if(!g_positions_loaded) load_positions()
    spawn_toys()
}

public plugin_end()
{
    if(g_picked_ids != Invalid_Trie) TrieDestroy(g_picked_ids)
}

public client_connect(id)
{
    g_picked_slot[id] = false
    g_is_alive[id] = false
}

public client_authorized(id, const authid[])
{
    if(!has_stable_authid(authid)) return
    if(g_picked_slot[id]) TrieSetCell(g_picked_ids, authid, 1)
    else if(TrieKeyExists(g_picked_ids, authid)) g_picked_slot[id] = true
}

public client_disconnected(id)
{
    g_picked_slot[id] = false
    g_is_alive[id] = false
}



public client_putinserver(id)
{
    g_is_alive[id] = false
}

public ham_player_spawn_post(id)
{
    g_is_alive[id] = bool:is_user_alive(id)
}

public ham_player_killed_post(victim, attacker, shouldgib)
{
    g_is_alive[victim] = false
}

public on_hide_dead_change(pcvar, const old_value[], const new_value[])
{
    refresh_fullpack_hook()
}

refresh_fullpack_hook()
{
    new bool:want = (get_pcvar_num(cvar_hide_dead) != 0 && g_ent_count > 0)

    if(want && g_fullpack_fwd == -1)
        g_fullpack_fwd = register_forward(FM_AddToFullPack, "fw_add_to_full_pack", 0)
    else if(!want && g_fullpack_fwd != -1)
    {
        unregister_forward(FM_AddToFullPack, g_fullpack_fwd, 0)
        g_fullpack_fwd = -1
    }
}

public fw_add_to_full_pack(es_handle, e, ent, host, hostflags, player, pSet)
{
    if(player || ent < 0 || ent >= MAX_EDICTS || !g_is_toy_ent[ent])
        return FMRES_IGNORED

    if(host < 1 || host > MAX_PLAYERS || g_is_alive[host])
        return FMRES_IGNORED

    forward_return(FMV_CELL, 0)
    return FMRES_SUPERCEDE
}

load_toys_config()
{
    g_toy_count = 0

    new cfgdir[128], filepath[256]
    get_configsdir(cfgdir, charsmax(cfgdir))
    formatex(filepath, charsmax(filepath), "%s/toy_models.ini", cfgdir)

    if(!file_exists(filepath))
    {
        write_default_config(filepath)
        toy_log("[ToyCore] Created default configs/toy_models.ini")
    }

    new f = fopen(filepath, "rt")
    if(!f)
    {
        toy_log("[ToyCore] Failed to open configs/toy_models.ini")
        return
    }

    g_weight_common    = TOY_RARITY_WEIGHT_COMMON
    g_weight_rare      = TOY_RARITY_WEIGHT_RARE
    g_weight_epic      = TOY_RARITY_WEIGHT_EPIC
    g_weight_legendary = TOY_RARITY_WEIGHT_LEGENDARY

    new line[256], in_block = 0, cur = -1
    new bool:in_weights = false 

    while(!feof(f))
    {
        fgets(f, line, charsmax(line))
        trim(line)
        if(!line[0] || line[0] == '/' || line[0] == ';') continue

        if(line[0] == '"' && !in_block)
        {
            new section_name[32]
            parse_quoted(line, section_name, charsmax(section_name))

            if(equali(section_name, "weights"))
            {
                in_weights = true
                cur = -1
            }
            else
            {
                in_weights = false
                if(g_toy_count >= MAX_TOYS) { cur = -1; continue; }

                cur = g_toy_count++
                g_toy_skin[cur]      = 0
                g_toy_body[cur]      = 0
                g_toy_sequence[cur]  = 0
                g_toy_framerate[cur] = 1.0
                g_toy_rarity[cur]    = TOY_RARITY_COMMON
                g_toy_model[cur][0]  = EOS
                g_toy_sound[cur][0]  = EOS
                copy(g_toy_name[cur], charsmax(g_toy_name[]), section_name)
            }
        }
        else if(line[0] == '{')
        {
            in_block = 1
        }
        else if(line[0] == '}')
        {
            in_block = 0
            in_weights = false
            cur = -1
        }
        else if(in_block && in_weights)
        {
            new key[32], val[32]
            parse_kv(line, key, charsmax(key), val, charsmax(val))
            new w = str_to_num(val)
            if(w < 0) w = 0

            if     (equali(key, "common"))    g_weight_common    = w
            else if(equali(key, "rare"))      g_weight_rare      = w
            else if(equali(key, "epic"))      g_weight_epic      = w
            else if(equali(key, "legendary")) g_weight_legendary = w
        }
        else if(in_block && cur >= 0)
        {
            new key[32], val[MAX_MODEL_LEN]
            parse_kv(line, key, charsmax(key), val, charsmax(val))

            if     (equali(key, "model"))     copy(g_toy_model[cur], charsmax(g_toy_model[]),   val)
            else if(equali(key, "sound"))     copy(g_toy_sound[cur], charsmax(g_toy_sound[]),   val)
            else if(equali(key, "skin"))      g_toy_skin[cur]      = str_to_num(val)
            else if(equali(key, "body"))      g_toy_body[cur]      = str_to_num(val)
            else if(equali(key, "sequence"))  g_toy_sequence[cur]  = str_to_num(val)
            else if(equali(key, "framerate")) g_toy_framerate[cur] = str_to_float(val)
            else if(equali(key, "rarity"))    g_toy_rarity[cur]    = str_to_rarity(val)
        }
    }
    fclose(f)
    toy_log("[ToyCore] Loaded toy types: %d (weights: C%d R%d E%d L%d)", g_toy_count, g_weight_common, g_weight_rare, g_weight_epic, g_weight_legendary)
}

write_default_config(const filepath[])
{
    new f = fopen(filepath, "wt")
    if(!f) return
    fputs(f, "// Adventures Toy System — конфиг игрушек^n")
    fputs(f, "// rarity: common | rare | epic | legendary^n")
    fputs(f, "// sequence: номер анимации модели (0 = статика)^n^n")
    fputs(f, "^"ExampleToy^"^n")
    fputs(f, "{^n")
    fputs(f, "    ^"model^"     ^"models/player/gordon/gordon.mdl^"^n")
    fputs(f, "    ^"rarity^"    ^"common^"^n")
    fputs(f, "    ^"sound^"     ^"items/gunpickup2.wav^"^n")
    fputs(f, "    ^"skin^"      ^"0^"^n")
    fputs(f, "    ^"body^"      ^"0^"^n")
    fputs(f, "    ^"sequence^"  ^"0^"^n")
    fputs(f, "    ^"framerate^" ^"1.0^"^n")
    fputs(f, "}^n")
    fclose(f)
}

build_pos_path(filepath[], maxlen)
{
    new datadir[128], mapname[64]
    get_datadir(datadir, charsmax(datadir))
    get_mapname(mapname, charsmax(mapname))
    formatex(filepath, maxlen, "%s/toy_spawn/%s.ini", datadir, mapname)
}

load_positions()
{
    g_positions_loaded = true
    g_positions_readonly = false
    g_pos_count = 0
    g_map_count_from_file = -1

    new filepath[256]
    build_pos_path(filepath, charsmax(filepath))

    if(!file_exists(filepath))
    {
        toy_log("[ToyCore] Position file not found: %s", filepath)
        return
    }

    new f = fopen(filepath, "rt")
    if(!f)
    {
        g_positions_readonly = true
        log_amx("Cannot read existing position file: %s. Saving disabled to protect it.", filepath)
        return
    }

    new line[256]
    while(!feof(f))
    {
        fgets(f, line, charsmax(line))
        trim(line)
        if(!line[0] || line[0] == '/' || line[0] == ';') continue

        if((line[0] >= 'a' && line[0] <= 'z') || (line[0] >= 'A' && line[0] <= 'Z'))
        {
            new kv_key[16], kv_val[16]
            if(parse(line, kv_key, charsmax(kv_key), kv_val, charsmax(kv_val)) >= 2
            && equali(kv_key, "count"))
                g_map_count_from_file = str_to_num(kv_val)
            continue
        }

        new parts[8][MAX_NAME_LEN]
        new n = parse(line,
            parts[0], charsmax(parts[]),
            parts[1], charsmax(parts[]),
            parts[2], charsmax(parts[]),
            parts[3], charsmax(parts[]),
            parts[4], charsmax(parts[]),
            parts[5], charsmax(parts[]),
            parts[6], charsmax(parts[]),
            parts[7], charsmax(parts[]))

        if(n < 4 || g_pos_count >= MAX_POSITIONS)
        {
            g_positions_readonly = true
            continue
        }
        new bool:valid = true
        for(new field = 0; field < 4; field++)
            if(!valid_position_number(parts[field])) valid = false
        if(!valid)
        {
            g_positions_readonly = true
            continue
        }

        new idx = g_pos_count
        g_pos_origin[idx][0] = str_to_float(parts[0])
        g_pos_origin[idx][1] = str_to_float(parts[1])
        g_pos_origin[idx][2] = str_to_float(parts[2])
        g_pos_yaw[idx]        = str_to_float(parts[3])

        new bound_col = 4
        if(n >= 5 && (equali(parts[4], "easy") || equali(parts[4], "medium")
                   || equali(parts[4], "hard") || equali(parts[4], "secret")))
            bound_col = 5

        if(n > bound_col && parts[bound_col][0])
        {
            // Поддерживаем 2 формы 5-й колонки:
            //   string: common/rare/epic/legendary/any → rarity binding
            //   число (legacy, индекс конкретной игрушки): из него берём её rarity
            new val = rarity_from_str(parts[bound_col])
            if(val >= 0)
                g_pos_bound_rarity[idx] = val
            else if(val == TOY_RARITY_ANY)
                g_pos_bound_rarity[idx] = TOY_RARITY_ANY
            else if(parts[bound_col][0] >= '0' && parts[bound_col][0] <= '9')
            {
                // Legacy fallback: был записан индекс игрушки → берём её тир
                new toy_idx = str_to_num(parts[bound_col])
                g_pos_bound_rarity[idx] = (toy_idx >= 0 && toy_idx < g_toy_count)
                    ? g_toy_rarity[toy_idx] : -1
            }
            else
            {
                // Older maps may contain a quoted toy name instead of its index.
                new toy_idx = find_toy_by_name(parts[bound_col])
                g_pos_bound_rarity[idx] = (toy_idx >= 0) ? g_toy_rarity[toy_idx] : -1
            }
        }
        else
            g_pos_bound_rarity[idx] = -1
        // New metadata is AFTER the legacy binding. No metadata means random.
        g_pos_spawn_mode[idx] = TOY_SPAWN_RANDOM
        new bool:seen_mode
        for(new col = bound_col + 1; col < n; col++)
        {
            if(parts[col][0] == ';' || parts[col][0] == '/') break
            if(containi(parts[col], "spawn=") != 0) continue
            new mode = parse_spawn_mode(parts[col])
            if(seen_mode || mode < 0)
            {
                g_positions_readonly = true
                log_amx("Invalid spawn metadata at position %d in %s", idx + 1, filepath)
            }
            else g_pos_spawn_mode[idx] = mode
            seen_mode = true
        }
        g_pos_count++
    }
    fclose(f)
    if(g_positions_readonly)
        log_amx("Invalid/too many positions in %s. Valid points loaded; saving disabled to protect the original.", filepath)
    toy_log("[ToyCore] Loaded positions: %d", g_pos_count)
}

save_positions()
{
    if(g_positions_readonly)
    {
        log_amx("Position save refused: reload a valid map file first")
        return 0
    }
    new filepath[256], dir[192]
    build_pos_path(filepath, charsmax(filepath))

    new datadir[128]
    get_datadir(datadir, charsmax(datadir))
    formatex(dir, charsmax(dir), "%s/toy_spawn", datadir)
    if(!dir_exists(dir)) mkdir(dir)

    new temp[272], backup[272]
    formatex(temp, charsmax(temp), "%s.tmp", filepath)
    formatex(backup, charsmax(backup), "%s.bak", filepath)
    new bool:write_failed
    new f = fopen(temp, "wt")
    if(!f)
    {
        log_amx("Cannot write position file: %s", temp)
        return 0
    }

    if(fputs(f, "// Adventures Toy System — позиции карты^n") < 0) write_failed = true
    if(fputs(f, "// Формат: x y z yaw [rarity [spawn=random|spawn=guaranteed]]^n") < 0) write_failed = true
    if(fputs(f, "//   rarity: common | rare | epic | legendary | any (или пусто)^n") < 0) write_failed = true
    if(fputs(f, "// count N — число СЛУЧАЙНЫХ игрушек; гарантированные добавляются отдельно^n^n") < 0) write_failed = true

    if(g_map_count_from_file >= 0) 
    {
        new count_line[32]
        formatex(count_line, charsmax(count_line), "count %d^n^n", g_map_count_from_file)
        if(fputs(f, count_line) < 0) write_failed = true
    }

    new line[256]
    for(new i = 0; i < g_pos_count; i++)
    {
        format_position_line(i, line, charsmax(line))
        if(fputs(f, line) < 0) write_failed = true
    }
    if(fflush(f) < 0) write_failed = true
    fclose(f)
    if(write_failed)
    {
        delete_file(temp)
        log_amx("Failed to flush position file: %s", temp)
        return 0
    }
    if(file_exists(filepath))
    {
        if(file_exists(backup) && !delete_file(backup)) return 0
        if(!rename_file(filepath, backup, 1)) return 0
    }
    if(!rename_file(temp, filepath, 1))
    {
        if(file_exists(backup)) rename_file(backup, filepath, 1)
        log_amx("Cannot replace position file: %s", filepath)
        return 0
    }
    toy_log("[ToyCore] Saved positions: %d", g_pos_count)
    return 1
}

remove_all_toys()
{
    new i
    for(i = 0; i < g_ent_count; i++)
    {
        if(pev_valid(g_ent_list[i]))
            engfunc(EngFunc_RemoveEntity, g_ent_list[i])
        mark_toy_ent(g_ent_list[i], false)
        g_ent_list[i] = 0
    }
    g_ent_count = 0
    refresh_fullpack_hook()
    g_legendary_spawned = 0
    arrayset(g_spawn_used_toy, 0, sizeof(g_spawn_used_toy))
}

spawn_toys()
{
    if(g_pickup_busy || g_spawn_busy) return
    g_spawn_busy = true
    remove_all_toys()
    new ret
    if(!get_pcvar_num(cvar_enabled) || !g_pos_count || !g_toy_count)
    {
        ExecuteForward(g_fwd_map_complete, ret, 0)
        g_spawn_busy = false
        return
    }

    // Reserve fixed legendary points before an ANY point can consume the cap.
    new guaranteed_spawned
    for(new pass = 0; pass < 2; pass++)
    {
        for(new pos = 0; pos < g_pos_count; pos++)
        {
            if(g_pos_spawn_mode[pos] != TOY_SPAWN_GUARANTEED) continue
            new bool:legendary = (g_pos_bound_rarity[pos] == TOY_RARITY_LEGENDARY)
            if((pass == 0) != legendary) continue
            if(spawn_one_position(pos)) guaranteed_spawned++
            else log_amx("Guaranteed point #%d could not spawn: check models, rarity weights, legendary cap and entity limit", pos + 1)
        }
    }

    new wanted = (g_map_count_from_file >= 0) ? g_map_count_from_file : get_pcvar_num(cvar_count)
    new bool:used_pos[MAX_POSITIONS], avail
    for(new pos = 0; pos < g_pos_count; pos++)
    {
        used_pos[pos] = (g_pos_spawn_mode[pos] == TOY_SPAWN_GUARANTEED)
        if(!used_pos[pos]) avail++
    }
    wanted = clamp(wanted, 0, avail)
    new random_spawned
    while(random_spawned < wanted && avail > 0)
    {
        new pos = pick_random_unused(used_pos, avail)
        if(pos < 0) break
        used_pos[pos] = true
        avail--
        if(spawn_one_position(pos)) random_spawned++
    }
    ExecuteForward(g_fwd_map_complete, ret, guaranteed_spawned + random_spawned)
    toy_log("[ToyCore] Spawned guaranteed=%d/%d random=%d/%d total=%d", guaranteed_spawned, count_positions_by_mode(TOY_SPAWN_GUARANTEED), random_spawned, wanted, g_ent_count)
    g_spawn_busy = false
}

spawn_one_position(pos_idx)
{
    new toy_idx = resolve_toy_for_position(pos_idx)
    if(toy_idx < 0 || toy_idx >= g_toy_count || !g_toy_model[toy_idx][0]) return 0
    new ent = do_spawn_entity(toy_idx, pos_idx)
    if(!ent) return 0
    new ret
    ExecuteForward(g_fwd_spawned, ret, ent, toy_idx, pos_idx)
    return ent
}

pick_random_unused(const bool:used[], avail)
{
    if(avail <= 0) return -1

    new r = random_num(0, avail - 1)
    new seen = 0, i

    for(i = 0; i < g_pos_count; i++)
    {
        if(used[i]) continue
        if(seen == r) return i
        seen++
    }
    return -1
}

resolve_toy_for_position(pos_idx)
{
    new bound_rarity = g_pos_bound_rarity[pos_idx]

    // Точка зафиксирована на тире → выбираем случайную игрушку этого тира.
    if(bound_rarity >= 0 && bound_rarity <= TOY_RARITY_LEGENDARY)
    {
        // Не подменяем заданную редкость, если лимит легендарных уже достигнут.
        if(bound_rarity == TOY_RARITY_LEGENDARY
        && g_legendary_spawned >= TOY_MAX_LEGENDARY_PER_MAP)
            return -1

        new picked = pick_unused_of_rarity(bound_rarity)
        return picked
    }

    // any / не задано → случайно по весам всех тиров
    return pick_toy_by_rarity()
}

pick_toy_by_rarity()
{
    new rw[4], total = 0, i

    rw[TOY_RARITY_COMMON]    = g_weight_common
    rw[TOY_RARITY_RARE]      = g_weight_rare
    rw[TOY_RARITY_EPIC]      = g_weight_epic
    rw[TOY_RARITY_LEGENDARY] = (g_legendary_spawned < TOY_MAX_LEGENDARY_PER_MAP) ? g_weight_legendary : 0

    for(i = 0; i < 4; i++)
    {
        if(rw[i] > 0 && count_toys_of_rarity(i) == 0)
            rw[i] = 0
        total += rw[i]
    }

    if(total <= 0) return -1

    new r = random_num(0, total - 1)
    new cumul = 0, selected_rarity = 0
    for(i = 0; i < 4; i++)
    {
        cumul += rw[i]
        if(cumul > r) { selected_rarity = i; break; }
    }

    return pick_unused_of_rarity(selected_rarity)
}

count_toys_of_rarity(rarity)
{
    new n = 0, i
    for(i = 0; i < g_toy_count; i++)
        if(g_toy_rarity[i] == rarity && g_toy_model[i][0])
            n++
    return n
}

pick_unused_of_rarity(rarity)
{
    new avail[MAX_TOYS], count = 0, i

    for(i = 0; i < g_toy_count; i++)
    {
        if(g_toy_rarity[i] != rarity || !g_toy_model[i][0]) continue
        if(!g_spawn_used_toy[i]) avail[count++] = i
    }

    if(count == 0)
    {
        for(i = 0; i < g_toy_count; i++)
            if(g_toy_rarity[i] == rarity) g_spawn_used_toy[i] = false

        count = 0
        for(i = 0; i < g_toy_count; i++)
        {
            if(g_toy_rarity[i] != rarity || !g_toy_model[i][0]) continue
            avail[count++] = i
        }
    }

    if(count == 0) return -1

    new picked = avail[random_num(0, count - 1)]
    return picked
}

do_spawn_entity(toy_idx, pos_idx)
{
    if(g_ent_count >= MAX_POSITIONS || toy_idx < 0 || toy_idx >= g_toy_count) return 0
    if(!g_toy_model[toy_idx][0]) return 0
    for(new i = 0; i < g_ent_count; i++)
        if(g_ent_pos_idx[i] == pos_idx) return 0

    new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"))
    if(!pev_valid(ent)) return 0

    new Float:origin[3]
    origin[0] = g_pos_origin[pos_idx][0]
    origin[1] = g_pos_origin[pos_idx][1]
    origin[2] = g_pos_origin[pos_idx][2]

    engfunc(EngFunc_SetOrigin, ent, origin)
    engfunc(EngFunc_SetModel,  ent, g_toy_model[toy_idx])

    set_pev(ent, pev_classname, TOY_ENT_CLASSNAME)
    set_pev(ent, pev_iuser1,    toy_idx)
    set_pev(ent, pev_iuser2,    pos_idx)
    set_pev(ent, pev_skin,      g_toy_skin[toy_idx])
    set_pev(ent, pev_body,      g_toy_body[toy_idx])

    set_pev(ent, pev_solid,    SOLID_TRIGGER)
    set_pev(ent, pev_movetype, MOVETYPE_NONE)

    new Float:mins[3], Float:maxs[3]
    mins[0] = -8.0; mins[1] = -8.0; mins[2] =  0.0
    maxs[0] =  8.0; maxs[1] =  8.0; maxs[2] = 24.0
    engfunc(EngFunc_SetSize, ent, mins, maxs)

    new Float:angles[3]
    angles[0] = 0.0
    angles[1] = g_pos_yaw[pos_idx]
    angles[2] = 0.0
    set_pev(ent, pev_angles, angles)

    set_pev(ent, pev_sequence,  g_toy_sequence[toy_idx])
    set_pev(ent, pev_framerate, g_toy_framerate[toy_idx])
    set_pev(ent, pev_animtime,  get_gametime())

    g_spawn_used_toy[toy_idx] = true
    mark_toy_ent(ent, true)

    g_ent_list[g_ent_count]    = ent
    g_ent_toy_idx[g_ent_count] = toy_idx
    g_ent_pos_idx[g_ent_count] = pos_idx
    g_ent_count++
    refresh_fullpack_hook()

    if(g_toy_rarity[toy_idx] == TOY_RARITY_LEGENDARY)
        g_legendary_spawned++

    return ent
}

mark_toy_ent(ent, bool:is_toy)
{
    if(ent < 0 || ent >= MAX_EDICTS)
    {
        if(is_toy) toy_log("[ToyCore] Entity index %d out of MAX_EDICTS (%d), toy_hide_dead skips it", ent, MAX_EDICTS)
        return
    }
    g_is_toy_ent[ent] = is_toy
}

remove_from_tracking(ent)
{
    mark_toy_ent(ent, false)

    new i
    for(i = 0; i < g_ent_count; i++)
    {
        if(g_ent_list[i] != ent) continue
        if(g_toy_rarity[g_ent_toy_idx[i]] == TOY_RARITY_LEGENDARY && g_legendary_spawned > 0)
            g_legendary_spawned--

        new j
        for(j = i; j < g_ent_count - 1; j++)
        {
            g_ent_list[j]    = g_ent_list[j+1]
            g_ent_toy_idx[j] = g_ent_toy_idx[j+1]
            g_ent_pos_idx[j] = g_ent_pos_idx[j+1]
        }
        g_ent_count--
        refresh_fullpack_hook()
        return
    }
}


str_to_rarity(const s[])
{
    if     (equali(s, "rare"))      return TOY_RARITY_RARE
    else if(equali(s, "epic"))      return TOY_RARITY_EPIC
    else if(equali(s, "legendary")) return TOY_RARITY_LEGENDARY
    return TOY_RARITY_COMMON
}

find_toy_by_name(const name[])
{
    new i
    for(i = 0; i < g_toy_count; i++)
        if(equali(g_toy_name[i], name))
            return i
    return -1
}

// Возвращает rarity-id по слугу: "common"/"rare"/"epic"/"legendary" → 0..3.
// "any" или неизвестная строка → -1 (= случайный по весам).
rarity_from_str(const s[])
{
    if(!s[0] || equali(s, "any")) return -1
    if(equali(s, "common"))       return TOY_RARITY_COMMON
    if(equali(s, "rare"))         return TOY_RARITY_RARE
    if(equali(s, "epic"))         return TOY_RARITY_EPIC
    if(equali(s, "legendary"))    return TOY_RARITY_LEGENDARY
    return -2  // не слаг — пусть парсер пробует legacy-числовой путь
}

// Обратная операция: rarity-id → слуг (для save_positions).
rarity_to_str(rarity, out[], maxlen)
{
    switch(rarity)
    {
        case TOY_RARITY_COMMON:    copy(out, maxlen, "common")
        case TOY_RARITY_RARE:      copy(out, maxlen, "rare")
        case TOY_RARITY_EPIC:      copy(out, maxlen, "epic")
        case TOY_RARITY_LEGENDARY: copy(out, maxlen, "legendary")
        default:                   copy(out, maxlen, "any")
    }
}

parse_quoted(const line[], out[], maxlen)
{
    new i = 0
    while(line[i] && line[i] != '"') i++
    if(!line[i]) return
    i++
    new o = 0
    while(line[i] && line[i] != '"' && o < maxlen - 1)
        out[o++] = line[i++]
    out[o] = EOS
}

parse_kv(const line[], key[], keylen, val[], vallen)
{
    new i = 0
    while(line[i] && line[i] != '"') i++
    if(!line[i]) return
    i++
    new k = 0
    while(line[i] && line[i] != '"' && k < keylen - 1) key[k++] = line[i++]
    key[k] = EOS
    if(line[i]) i++
    while(line[i] && line[i] != '"') i++
    if(!line[i]) return
    i++
    new v = 0
    while(line[i] && line[i] != '"' && v < vallen - 1) val[v++] = line[i++]
    val[v] = EOS
}

public native_get_toy_idx(plugin_id, num_params)
{
    new ent = get_param(1)
    if(!pev_valid(ent)) return -1

    new classname[32]
    pev(ent, pev_classname, classname, charsmax(classname))
    if(!equal(classname, TOY_ENT_CLASSNAME)) return -1
    for(new i = 0; i < g_ent_count; i++)
        if(g_ent_list[i] == ent) return g_ent_toy_idx[i]
    return -1
}

public native_get_name(plugin_id, num_params)
{
    new idx = get_param(1)
    if(idx < 0 || idx >= g_toy_count) return 0
    new len = get_param(3)
    set_string(2, g_toy_name[idx], len)
    return 1
}

public native_get_rarity(plugin_id, num_params)
{
    new idx = get_param(1)
    if(idx < 0 || idx >= g_toy_count) return TOY_RARITY_COMMON
    return g_toy_rarity[idx]
}

public native_get_model(plugin_id, num_params)
{
    new idx = get_param(1)
    if(idx < 0 || idx >= g_toy_count) return 0
    new len = get_param(3)
    set_string(2, g_toy_model[idx], len)
    return 1
}

public native_get_body(plugin_id, num_params)
{
    new idx = get_param(1)
    if(idx < 0 || idx >= g_toy_count) return 0
    return g_toy_body[idx]
}

public native_get_skin(plugin_id, num_params)
{
    new idx = get_param(1)
    if(idx < 0 || idx >= g_toy_count) return 0
    return g_toy_skin[idx]
}

public native_get_type_count(plugin_id, num_params)
{
    return g_toy_count
}

public native_get_spawned_count(plugin_id, num_params)
{
    return g_ent_count
}

public native_get_pos_count(plugin_id, num_params)
{
    return g_pos_count
}

public native_get_pos_data(plugin_id, num_params)
{
    new idx = get_param(1)
    if(idx < 0 || idx >= g_pos_count) return 0

    new Float:origin[3]
    origin[0] = g_pos_origin[idx][0]
    origin[1] = g_pos_origin[idx][1]
    origin[2] = g_pos_origin[idx][2]

    set_array(2, _:origin, 3)
    set_param_byref(3, _:g_pos_yaw[idx])
    set_param_byref(4, g_pos_bound_rarity[idx])
    return 1
}

public native_add_position(plugin_id, num_params)
{
    if(g_pickup_busy || g_spawn_busy) return -1
    if(g_pos_count >= MAX_POSITIONS) return -1

    new Float:origin[3]
    get_array(1, _:origin, 3)

    new rarity = clamp(get_param(3), TOY_RARITY_ANY, TOY_RARITY_LEGENDARY)
    new mode = (num_params >= 4) ? get_param(4) : TOY_SPAWN_RANDOM
    if(!can_set_position(rarity, mode, -1)) return -1
    new idx = g_pos_count
    g_pos_spawn_mode[idx] = mode
    g_pos_origin[idx][0] = origin[0]
    g_pos_origin[idx][1] = origin[1]
    g_pos_origin[idx][2] = origin[2]
    g_pos_yaw[idx]       = get_param_f(2)
    g_pos_bound_rarity[idx] = rarity
    g_pos_count++

    return idx
}

public native_remove_position(plugin_id, num_params)
{
    if(g_pickup_busy || g_spawn_busy) return 0
    new idx = get_param(1)
    if(idx < 0 || idx >= g_pos_count) return 0

    for(new e = g_ent_count - 1; e >= 0; e--)
    {
        if(g_ent_pos_idx[e] == idx)
        {
            new ent = g_ent_list[e]
            remove_from_tracking(ent)
            if(pev_valid(ent)) engfunc(EngFunc_RemoveEntity, ent)
        }
        else if(g_ent_pos_idx[e] > idx)
        {
            g_ent_pos_idx[e]--
            if(pev_valid(g_ent_list[e])) set_pev(g_ent_list[e], pev_iuser2, g_ent_pos_idx[e])
        }
    }
    new i
    for(i = idx; i < g_pos_count - 1; i++)
    {
        g_pos_origin[i][0] = g_pos_origin[i+1][0]
        g_pos_origin[i][1] = g_pos_origin[i+1][1]
        g_pos_origin[i][2] = g_pos_origin[i+1][2]
        g_pos_yaw[i]       = g_pos_yaw[i+1]
        g_pos_bound_rarity[i] = g_pos_bound_rarity[i+1]
        g_pos_spawn_mode[i] = g_pos_spawn_mode[i+1]
    }
    g_pos_count--
    return 1
}

public native_update_position(plugin_id, num_params)
{
    if(g_pickup_busy || g_spawn_busy) return 0
    new idx = get_param(1)
    if(idx < 0 || idx >= g_pos_count) return 0

    new rarity = clamp(get_param(4), TOY_RARITY_ANY, TOY_RARITY_LEGENDARY)
    new mode = (num_params >= 5 && get_param(5) >= 0) ? get_param(5) : g_pos_spawn_mode[idx]
    if(!can_set_position(rarity, mode, idx)) return 0
    new Float:origin[3]
    get_array(2, _:origin, 3)
    g_pos_origin[idx][0] = origin[0]
    g_pos_origin[idx][1] = origin[1]
    g_pos_origin[idx][2] = origin[2]
    g_pos_yaw[idx]       = get_param_f(3)
    g_pos_bound_rarity[idx] = rarity
    g_pos_spawn_mode[idx] = mode
    return 1
}

public native_save_positions(plugin_id, num_params)
{
    return save_positions()
}

public native_reload_positions(plugin_id, num_params)
{
    if(g_pickup_busy || g_spawn_busy) return 0
    remove_all_toys()
    load_positions()
    return 1
}

public native_remove_entity(plugin_id, num_params)
{
    new ent = get_param(1)
    if(g_pickup_busy || g_spawn_busy || !pev_valid(ent) || toy_get_toy_idx(ent) < 0) return 0

    remove_from_tracking(ent)
    engfunc(EngFunc_RemoveEntity, ent)
    return 1
}

public native_spawn_at_position(plugin_id, num_params)
{
    if(g_pickup_busy || g_spawn_busy || !get_pcvar_num(cvar_enabled)) return 0
    new pos_idx = get_param(1)
    if(pos_idx < 0 || pos_idx >= g_pos_count || !g_toy_count) return 0
    g_spawn_busy = true
    new ent = spawn_one_position(pos_idx)
    g_spawn_busy = false
    return ent
}

public native_respawn_all(plugin_id, num_params)
{
    if(g_pickup_busy || g_spawn_busy) return 0
    if(!g_positions_loaded) load_positions()
    spawn_toys()
    return 1
}

/**
 * toy_trigger_pickup — вызывается из toy_pickup.sma когда игрок нажал USE на игрушку.
 * Запускает forward toy_on_pickup. Если никто не заблокировал:
 *   — удаляет entity
 *   — воспроизводит звук подбора
 *   — запускает toy_on_collected для наград и объявлений
 * Возвращает 1 если подбор состоялся, 0 если заблокирован или ошибка.
 */
public native_trigger_pickup(plugin_id, num_params)
{
    new id = get_param(1), ent = get_param(2)
    if(g_pickup_busy || g_spawn_busy || !get_pcvar_num(cvar_enabled)) return 0
    if(id < 1 || id > 32 || !is_user_alive(id)) return 0
    new toy_idx = toy_get_toy_idx(ent)
    if(toy_idx < 0 || toy_idx >= g_toy_count) return 0

    new authid[32]
    get_user_authid(id, authid, charsmax(authid))
    new bool:stable_authid = has_stable_authid(authid)
    if(g_picked_slot[id] || (stable_authid && TrieKeyExists(g_picked_ids, authid)))
    {
        g_picked_slot[id] = true
        client_print_color(id, print_team_default, "%L", id, "TOY_ALREADY_PICKED")
        return 0
    }

    g_pickup_busy = true
    new ret
    ExecuteForward(g_fwd_pickup, ret, id, ent, toy_idx)
    if(ret >= PLUGIN_HANDLED || !is_user_alive(id) || !pev_valid(ent))
    {
        g_pickup_busy = false
        return 0
    }

    g_picked_slot[id] = true
    if(stable_authid) TrieSetCell(g_picked_ids, authid, 1)
    remove_from_tracking(ent)
    engfunc(EngFunc_RemoveEntity, ent)
    if(g_toy_sound[toy_idx][0])
        emit_sound(id, CHAN_AUTO, g_toy_sound[toy_idx], 1.0, ATTN_NORM, 0, PITCH_NORM)
    else
        emit_sound(id, CHAN_AUTO, TOY_DEFAULT_PICKUP_SOUND, 1.0, ATTN_NORM, 0, PITCH_NORM)
    ExecuteForward(g_fwd_collected, ret, id, toy_idx)
    g_pickup_busy = false
    return 1
}

public native_get_map_file_count(plugin_id, num_params)
{
    return g_map_count_from_file
}

public native_set_map_file_count(plugin_id, num_params)
{
    new count = get_param(1)
    if(count < 0) count = -1
    g_map_count_from_file = count
    return 1
}

public native_clear_positions(plugin_id, num_params)
{
    if(g_pickup_busy || g_spawn_busy) return 0
    remove_all_toys()
    g_pos_count = 0
    return 1
}

// The legacy position format is decimal XYZ/yaw, optionally signed.
bool:valid_position_number(const value[])
{
    new i = 0, digits = 0, dots = 0
    if(value[i] == '+' || value[i] == '-') i++
    for(; value[i]; i++)
    {
        if(value[i] >= '0' && value[i] <= '9') digits++
        else if(value[i] == '.' && ++dots <= 1) continue
        else return false
    }
    return bool:digits
}

parse_spawn_mode(const token[])
{
    if(equali(token, "spawn=random")) return TOY_SPAWN_RANDOM
    if(equali(token, "spawn=guaranteed")) return TOY_SPAWN_GUARANTEED
    return -1
}

format_position_line(idx, line[], maxlen)
{
    new slug[16]
    rarity_to_str(g_pos_bound_rarity[idx], slug, charsmax(slug))
    if(g_pos_spawn_mode[idx] == TOY_SPAWN_GUARANTEED)
        formatex(line, maxlen, "%.4f %.4f %.4f %.4f %s spawn=guaranteed^n",
            g_pos_origin[idx][0], g_pos_origin[idx][1], g_pos_origin[idx][2], g_pos_yaw[idx], slug)
    else if(g_pos_bound_rarity[idx] >= 0)
        formatex(line, maxlen, "%.4f %.4f %.4f %.4f %s^n",
            g_pos_origin[idx][0], g_pos_origin[idx][1], g_pos_origin[idx][2], g_pos_yaw[idx], slug)
    else
        formatex(line, maxlen, "%.4f %.4f %.4f %.4f^n",
            g_pos_origin[idx][0], g_pos_origin[idx][1], g_pos_origin[idx][2], g_pos_yaw[idx])
}

count_positions_by_mode(mode)
{
    new count
    for(new pos = 0; pos < g_pos_count; pos++)
        if(g_pos_spawn_mode[pos] == mode) count++
    return count
}

bool:can_set_position(rarity, mode, exclude_pos)
{
    if(mode != TOY_SPAWN_RANDOM && mode != TOY_SPAWN_GUARANTEED) return false
    if(rarity < TOY_RARITY_ANY || rarity > TOY_RARITY_LEGENDARY) return false
    if(mode == TOY_SPAWN_RANDOM) return true
    if(rarity >= 0 && !count_toys_of_rarity(rarity)) return false
    new bool:weighted_normal = ((g_weight_common > 0 && count_toys_of_rarity(TOY_RARITY_COMMON) > 0)
        || (g_weight_rare > 0 && count_toys_of_rarity(TOY_RARITY_RARE) > 0)
        || (g_weight_epic > 0 && count_toys_of_rarity(TOY_RARITY_EPIC) > 0))
    if(rarity == TOY_RARITY_ANY && !weighted_normal
        && !(g_weight_legendary > 0 && count_toys_of_rarity(TOY_RARITY_LEGENDARY) > 0)) return false
    // With no weighted nonlegendary types, every ANY point also consumes the cap.
    new legends = (rarity == TOY_RARITY_LEGENDARY || (rarity == TOY_RARITY_ANY && !weighted_normal)) ? 1 : 0
    for(new pos = 0; pos < g_pos_count; pos++)
    {
        if(pos == exclude_pos || g_pos_spawn_mode[pos] != TOY_SPAWN_GUARANTEED) continue
        if(g_pos_bound_rarity[pos] == TOY_RARITY_LEGENDARY
            || (g_pos_bound_rarity[pos] == TOY_RARITY_ANY && !weighted_normal)) legends++
    }
    return bool:(legends <= TOY_MAX_LEGENDARY_PER_MAP)
}

public native_get_pos_mode(plugin_id, num_params)
{
    new idx = get_param(1)
    return (idx >= 0 && idx < g_pos_count) ? g_pos_spawn_mode[idx] : -1
}

public native_get_pos_count_by_mode(plugin_id, num_params)
{
    return count_positions_by_mode(get_param(1))
}

public native_can_set_position(plugin_id, num_params)
{
    return can_set_position(get_param(1), get_param(2), (num_params >= 3) ? get_param(3) : -1)
}

public native_set_pos_mode(plugin_id, num_params)
{
    if(g_pickup_busy || g_spawn_busy) return 0
    new idx = get_param(1), mode = get_param(2)
    if(idx < 0 || idx >= g_pos_count || !can_set_position(g_pos_bound_rarity[idx], mode, idx)) return 0
    g_pos_spawn_mode[idx] = mode
    return 1
}

bool:has_stable_authid(const authid[])
{
    return bool:(authid[0] && !equal(authid, "STEAM_ID_PENDING")
        && !equal(authid, "VALVE_ID_PENDING") && !equal(authid, "STEAM_ID_LAN")
        && !equal(authid, "VALVE_ID_LAN") && !equal(authid, "BOT")
        && !equal(authid, "HLTV") && !equal(authid, "STEAM_0:0:0")
        && !equal(authid, "VALVE_0:0:0"))
}
