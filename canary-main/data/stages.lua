-- Minlevel and multiplier are MANDATORY
-- Maxlevel is OPTIONAL, but is considered infinite by default
-- Create a stage with minlevel 1 and no maxlevel to disable stages
experienceStages = {
	{
		minlevel = 1,
		maxlevel = 39,
		multiplier = 10,
	},
	{
		minlevel = 40,
		maxlevel = 79,
		multiplier = 8,
	},
	{
		minlevel = 80,
		maxlevel = 149,
		multiplier = 6,
	},
	{
		minlevel = 150,
		maxlevel = 249,
		multiplier = 4,
	},
	{
		minlevel = 250,
		maxlevel = 399,
		multiplier = 3,
	},
	{
		minlevel = 400,
		maxlevel = 599,
		multiplier = 2,
	},
	{
		minlevel = 600,
		multiplier = 1.5,
	},
}

skillsStages = {
	{
		minlevel = 10,
		maxlevel = 60,
		multiplier = 8,
	},
	{
		minlevel = 61,
		maxlevel = 90,
		multiplier = 6,
	},
	{
		minlevel = 91,
		maxlevel = 115,
		multiplier = 4,
	},
	{
		minlevel = 116,
		maxlevel = 130,
		multiplier = 3,
	},
	{
		minlevel = 131,
		multiplier = 2,
	},
}

magicLevelStages = {
	{
		minlevel = 0,
		maxlevel = 50,
		multiplier = 6,
	},
	{
		minlevel = 51,
		maxlevel = 80,
		multiplier = 4,
	},
	{
		minlevel = 81,
		maxlevel = 105,
		multiplier = 3,
	},
	{
		minlevel = 106,
		maxlevel = 120,
		multiplier = 2,
	},
	{
		minlevel = 121,
		multiplier = 1.5,
	},
}
