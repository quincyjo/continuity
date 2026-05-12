package = "continuity"
version = "scm-1"

source = {
    url = "git+https://github.com/quincyjo/continuity.git",
}

description = {
    summary = "A collection of AwesomeWM modules providing system monitoring, media integration, audio control, client switching, and async CLI tool wrappers.",
    homepage = "https://github.com/quincyjo/continuity",
    license = "MIT",
}

dependencies = {
    "lua >= 5.1",
}

build = {
    type = "builtin",
    modules = {
        ["continuity.alttab"]                        = "lua/continuity/alttab/init.lua",
        ["continuity.audio"]                         = "lua/continuity/audio/init.lua",
        ["continuity.audio.devices"]                 = "lua/continuity/audio/devices.lua",
        ["continuity.audio.inputs"]                  = "lua/continuity/audio/inputs.lua",
        ["continuity.audio.backends.alsa"]           = "lua/continuity/audio/backends/alsa.lua",
        ["continuity.audio.backends.pulse"]          = "lua/continuity/audio/backends/pulse.lua",
        ["continuity.backlight"]                     = "lua/continuity/backlight/init.lua",
        ["continuity.backlight.backends.acpilight"]  = "lua/continuity/backlight/backends/acpilight.lua",
        ["continuity.backlight.backends.sysfs"]      = "lua/continuity/backlight/backends/sysfs.lua",
        ["continuity.backlight.backends.xbacklight"] = "lua/continuity/backlight/backends/xbacklight.lua",
        ["continuity.compat.naughty"]                = "lua/continuity/compat/naughty.lua",
        ["continuity.media"]                         = "lua/continuity/media/init.lua",
        ["continuity.media.art"]                     = "lua/continuity/media/art.lua",
        ["continuity.media.coalescer"]               = "lua/continuity/media/coalescer.lua",
        ["continuity.media.notification"]            = "lua/continuity/media/notification.lua",
        ["continuity.media.registry"]                = "lua/continuity/media/registry.lua",
        ["continuity.media.backends.mpd"]            = "lua/continuity/media/backends/mpd.lua",
        ["continuity.media.backends.mpris"]          = "lua/continuity/media/backends/mpris.lua",
        ["continuity.sysinfo.bat"]                   = "lua/continuity/sysinfo/bat/init.lua",
        ["continuity.sysinfo.bat.backends.udevadm"]  = "lua/continuity/sysinfo/bat/backends/udevadm.lua",
        ["continuity.sysinfo.cpu"]                   = "lua/continuity/sysinfo/cpu/init.lua",
        ["continuity.sysinfo.cpu.backends.procstat"] = "lua/continuity/sysinfo/cpu/backends/procstat.lua",
        ["continuity.sysinfo.mem"]                   = "lua/continuity/sysinfo/mem/init.lua",
        ["continuity.sysinfo.mem.backends.procmeminfo"] = "lua/continuity/sysinfo/mem/backends/procmeminfo.lua",
        ["continuity.sysinfo.net"]                   = "lua/continuity/sysinfo/net/init.lua",
        ["continuity.sysinfo.net.backends.ipmonitor"] = "lua/continuity/sysinfo/net/backends/ipmonitor.lua",
        ["continuity.sysinfo.temp"]                  = "lua/continuity/sysinfo/temp/init.lua",
        ["continuity.sysinfo.temp.backends.sysfs"]   = "lua/continuity/sysinfo/temp/backends/sysfs.lua",
        ["continuity.tools.find"]                    = "lua/continuity/tools/find/init.lua",
        ["continuity.tools.find.backends.fd"]        = "lua/continuity/tools/find/backends/fd.lua",
        ["continuity.tools.find.backends.find"]      = "lua/continuity/tools/find/backends/find.lua",
        ["continuity.tools.grep"]                    = "lua/continuity/tools/grep/init.lua",
        ["continuity.tools.grep.backends.grep"]      = "lua/continuity/tools/grep/backends/grep.lua",
        ["continuity.tools.grep.backends.rg"]        = "lua/continuity/tools/grep/backends/rg.lua",
        ["continuity.types"]                         = "lua/continuity/types.lua",
        ["continuity.util.app_icon"]                 = "lua/continuity/util/app_icon.lua",
        ["continuity.util.json"]                     = "lua/continuity/util/json/init.lua",
        ["continuity.util.json.json_lua"]            = "lua/continuity/util/json/json_lua.lua",
        ["continuity.util.process"]                  = "lua/continuity/util/process.lua",
    },
}
