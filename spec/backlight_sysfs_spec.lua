-- spec/backlight_sysfs_spec.lua
require("spec.support.awesome_mocks")
local sysfs = require("continuity.backlight.backends.sysfs")

describe("backlight.sysfs backend", function()
	describe("_kind_from_name", function()
		it("returns 'keyboard' for names containing kbd", function()
			assert.equals("keyboard", sysfs._kind_from_name("system76_acpi::kbd_backlight"))
		end)

		it("returns 'keyboard' for names containing keyboard", function()
			assert.equals("keyboard", sysfs._kind_from_name("asus_keyboard_backlight"))
		end)

		it("returns 'display' for display devices", function()
			assert.equals("display", sysfs._kind_from_name("intel_backlight"))
			assert.equals("display", sysfs._kind_from_name("acpi_video0"))
		end)
	end)

	describe("_raw_to_perc", function()
		it("converts max to 100", function()
			assert.equals(100, sysfs._raw_to_perc(255, 255))
		end)

		it("converts 0 to 0", function()
			assert.equals(0, sysfs._raw_to_perc(0, 255))
		end)

		it("maps midpoint raw to midpoint perc", function()
			-- 128 / (255 + 1) * 100 = 50
			assert.equals(50, sysfs._raw_to_perc(128, 255))
		end)

		it("works with non-255 max", function()
			assert.equals(50, sysfs._raw_to_perc(500, 1000))
		end)

		it("maps midpoint to 50% on coarse display (max=19)", function()
			assert.equals(50, sysfs._raw_to_perc(10, 19))
		end)
	end)

	describe("_perc_to_raw", function()
		it("converts 100% to max", function()
			assert.equals(255, sysfs._perc_to_raw(100, 255))
		end)

		it("converts 0% to 0", function()
			assert.equals(0, sysfs._perc_to_raw(0, 255))
		end)

		it("maps midpoint to midpoint raw", function()
			-- 50 / 100 * (255 + 1) = 128
			assert.equals(128, sysfs._perc_to_raw(50, 255))
		end)
	end)

	describe("_parse_line", function()
		it("parses id:raw format", function()
			local id, raw = sysfs._parse_line("intel_backlight:150")
			assert.equals("intel_backlight", id)
			assert.equals(150, raw)
		end)

		it("returns nil for invalid format", function()
			local id, raw = sysfs._parse_line("novalue")
			assert.is_nil(id)
			assert.is_nil(raw)
		end)

		it("returns nil for non-numeric raw", function()
			local id, raw = sysfs._parse_line("intel_backlight:abc")
			assert.is_nil(id)
			assert.is_nil(raw)
		end)
	end)
end)
