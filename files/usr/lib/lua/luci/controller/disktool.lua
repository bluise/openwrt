-- Copyright (C) 2026 bluise
-- 磁盘管理 (系统 -> 磁盘管理)
--
-- 页面本身很薄: 所有逻辑都在 /usr/bin/openwrt-storage 里(那个脚本也能直接 SSH 用),
-- 这里只负责跑命令并把输出显示出来 —— 免得把分区操作写进 Lua 里出错。
-- 页面本体: /usr/lib/lua/luci/view/disktool.htm

module("luci.controller.disktool", package.seeall)

function index()
	entry({"admin", "system", "storage"}, template("disktool"), "磁盘管理", 45)
end
