#!/bin/bash
# =============================================
# diy-part1.sh : feeds 配置(新增第三方源)
# OpenClash + OpenAppFilter(OAF)
# =============================================
set -e

# 1. OpenClash
if [ ! -d package/luci-app-openclash ]; then
  git clone --depth 1 https://github.com/vernesong/OpenClash.git package/luci-app-openclash
fi

# 2. OpenAppFilter (OAF)
if [ ! -d package/OpenAppFilter ]; then
  git clone --depth 1 https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter
fi

exit 0