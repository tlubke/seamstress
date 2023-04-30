-- seamstress configuration

-- add to package.path

local home = os.getenv('HOME')
local pwd = os.getenv('PWD')
local seamstress_home = home .. '/seamstress'
local seamstress = '/usr/local/share/seamstress/lua'
local sys = seamstress .. '/?.lua;'
local core = seamstress .. '/core/?.lua;'
local lib = seamstress .. '/lib/?.lua;'
local luafiles = pwd .. '/?.lua;'
local seamstressfiles = seamstress_home .. '/?.lua;'

package.path = sys .. core .. lib .. luafiles .. seamstressfiles.. package.path

path = {}
path.home = home
path.pwd = pwd
path.seamstress = seamstress_home
