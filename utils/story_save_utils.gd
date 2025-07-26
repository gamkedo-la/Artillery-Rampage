class_name StorySaveUtils


static func story_save_exists(save:SaveState = null) -> bool:
	if not save:
		save = SaveStateManager.save_state
	
	if not save or not save.state:
		return false
	var state : Dictionary[StringName, Dictionary] = save.state
	
	var exists:bool = state.has(StoryLevelState.SAVE_STATE_KEY)
	return exists
	
static func get_story_save(save:SaveState = null, add_parent_if_not_exists:bool = false) -> Dictionary:
	if not story_save_exists(save):
		return {StoryLevelState.SAVE_STATE_KEY: {}} if add_parent_if_not_exists else {}
	
	if not save:
		save = SaveStateManager.save_state
	return save.state.get(StoryLevelState.SAVE_STATE_KEY)

static func delete_story_save() -> void:
	SaveStateManager.clear_save_state_by_key(StoryLevelState.SAVE_STATE_KEY)
	# Ensure that player upgrades and player state are cleared out correctly in memory
	PlayerUpgrades.clear()
	PlayerStateManager.clear()

static func new_story_save() -> void:
	delete_story_save()
	var save:SaveState = SaveStateManager.save_state
	if save:
		save.state.set(StoryLevelState.SAVE_STATE_KEY, {StoryLevelState.RUN_KEY: 1})
		SaveStateManager.save_tree_state(&"NewStory")
