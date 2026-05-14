local mock = {}

function mock.answer(request, context)
	local player = context.player
	local position = player.position
	local message = string.format(
		"Phase 1 read-only mock received your chat. I can see %s is level %s at %s,%s,%s. Gemini, routes, and tasker are still disabled.",
		player.name,
		player.level,
		position.x,
		position.y,
		position.z
	)

	return {
		v = 1,
		type = "answer",
		requestId = request.requestId,
		message = message,
		echo = request.text,
		context = context,
		requiresConfirmation = false,
	}
end

return mock