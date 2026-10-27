#if defined _toys_system_included
    #endinput
#endif
#define _toys_system_included

#if !defined TOY_CORE_PLUGIN
    #pragma library toys_system
#endif

#define TOY_RARITY_COMMON       0
#define TOY_RARITY_RARE         1
#define TOY_RARITY_EPIC         2
#define TOY_RARITY_LEGENDARY    3
#define TOY_SPAWN_RANDOM        0
#define TOY_SPAWN_GUARANTEED    1

#define TOY_RARITY_ANY         -1   // "любой тир" при привязке точки

#define TOY_RARITY_WEIGHT_COMMON        100
#define TOY_RARITY_WEIGHT_RARE           30
#define TOY_RARITY_WEIGHT_EPIC           10
#define TOY_RARITY_WEIGHT_LEGENDARY       3

#define TOY_MAX_LEGENDARY_PER_MAP         1

#define TOY_DEFAULT_PICKUP_SOUND    "items/gunpickup2.wav"

#define TOY_ENT_CLASSNAME           "toy_ent"

// PRE: return PLUGIN_HANDLED to reject. Do not grant rewards here.
forward toy_on_pickup(id, ent, toy_idx);
// POST: accepted pickup only; entity has already been removed.
forward toy_on_collected(id, toy_idx);

forward toy_on_spawned(ent, toy_idx, pos_idx);

forward toy_on_map_spawn_complete(count);

native toy_get_toy_idx(ent);

native toy_get_name(idx, buf[], len);

native toy_get_rarity(idx);

native toy_get_model(idx, buf[], len);

native toy_get_body(idx);

native toy_get_skin(idx);

native toy_get_type_count();

native toy_get_spawned_count();

native toy_get_pos_count();
native toy_get_pos_count_by_mode(spawn_mode);
// Returns TOY_SPAWN_* or -1 for an invalid index.
native toy_get_pos_mode(pos_idx);
// Validate a proposed guaranteed point against models and the legendary cap.
native toy_can_set_position(bound_rarity, spawn_mode, exclude_pos = -1);
native toy_set_pos_mode(pos_idx, spawn_mode);

// pos_data возвращает rarity-биндинг точки спавна (TOY_RARITY_* или TOY_RARITY_ANY).
native toy_get_pos_data(pos_idx, Float:origin[3], &Float:yaw, &bound_rarity);

native toy_add_position(const Float:origin[3], Float:yaw, bound_rarity = TOY_RARITY_ANY, spawn_mode = TOY_SPAWN_RANDOM);

native toy_remove_position(pos_idx);

// Omitted mode preserves the point's existing mode (including old callers).
native toy_update_position(pos_idx, const Float:origin[3], Float:yaw, bound_rarity, spawn_mode = -1);

native toy_save_positions();

native toy_reload_positions();

native toy_remove_entity(ent);

native toy_spawn_at_position(pos_idx);

native toy_respawn_all();

native toy_trigger_pickup(id, ent);

native toy_get_map_file_count();

native toy_set_map_file_count(count);

native toy_clear_positions();

stock toy_rarity_to_str(id, rarity, buf[], len)
{
    static const keys[4][] = {
        "TOY_RARITY_COMMON",
        "TOY_RARITY_RARE",
        "TOY_RARITY_EPIC",
        "TOY_RARITY_LEGENDARY"
    }
    new key_idx = (rarity >= 0 && rarity <= 3) ? rarity : 0
    formatex(buf, len, "%L", id, keys[key_idx])
}

stock toy_spawn_mode_to_str(id, spawn_mode, buf[], len)
{
    formatex(buf, len, "%L", id, spawn_mode == TOY_SPAWN_GUARANTEED ? "TOY_SPAWN_GUARANTEED" : "TOY_SPAWN_RANDOM")
}
