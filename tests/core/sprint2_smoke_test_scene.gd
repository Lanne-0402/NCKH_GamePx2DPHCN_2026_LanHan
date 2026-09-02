extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var session: ExerciseSession = $ExerciseSession
	PoseInput.set_tracking(true)
	assert(session.start_session({
		"session_id": "sprint2-smoke-test",
		"exercise_id": "scapular_retraction",
		"repetitions_per_phase": 2,
		"phase_count": 2,
		"rest_duration_seconds": 0.05,
	}))
	assert(session.state == ExerciseSession.State.ACTIVE)
	PoseInput.simulate_rejected_rep()
	assert(session.total_rejected_reps == 1)
	PoseInput.simulate_valid_rep()
	PoseInput.simulate_valid_rep()
	assert(session.state == ExerciseSession.State.RESTING)
	session.debug_skip_rest()
	assert(session.state == ExerciseSession.State.ACTIVE)
	assert(session.current_phase == 2)
	PoseInput.set_tracking(false)
	assert(session.state == ExerciseSession.State.TRACKING_LOST)
	PoseInput.set_tracking(true)
	assert(session.state == ExerciseSession.State.ACTIVE)
	PoseInput.simulate_valid_rep()
	PoseInput.simulate_valid_rep()
	assert(session.state == ExerciseSession.State.COMPLETED)
	assert(session.total_valid_reps == 4)
	print("SPRINT_2_SMOKE_TEST: PASS")
	get_tree().quit(0)

