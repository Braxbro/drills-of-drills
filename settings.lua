data:extend{
    {
		type = "int-setting",
		name = "drills-of-drills-max-size",
		setting_type = "startup",
        default_value = 32,
        minimum_value = 1,
        maximum_value = 128,
        order = "02"
	},
    { 
        type = "int-setting",
        name = "drills-of-drills-filter-count",
        setting_type = "startup",
        default_value = 1,
        minimum_value = 0,
        maximum_value = 5,
        order = "03"
    }
}