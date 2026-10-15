local C=assert(loadfile('/home/bec_v2/lib/config.lua'))()
local fs=require('filesystem');local ser=require('serialization');local term=require('term')
local path=C.path('github-upload.dat')
print('GitHub: Alivn-chao/gtnh-bec-automation / diagnostics/v2/')
print('Use a fine-grained token for this repository with Contents: read and write.')
print('Paste the token HERE in OC only. Input is masked; do not send it in chat.')
io.write('Token: ')
local token=assert(term.read(nil,false,'*'),'No token entered'):gsub('%s+$','')
assert(token:match('^[%w_]+$')and #token>=10,'Token format not accepted; no configuration changed')
local value={version=1,owner='Alivn-chao',repo='gtnh-bec-automation',token=token}
local text=ser.serialize(value,false);local temp=path..'.new'
local f=assert(io.open(temp,'w'));assert(f:write(text));assert(f:flush());f:close()
f=assert(io.open(temp,'r'));local actual=f:read('*a');f:close();assert(actual==text,'Read-back failed')
assert(not fs.exists(path..'.previous'),'An old token backup exists; review it locally before replacing credentials')
if fs.exists(path)then assert(fs.rename(path,path..'.previous'),'Credential backup failed')end
local ok,err=fs.rename(temp,path)
if not ok then
 if fs.exists(path..'.previous')then assert(fs.rename(path..'.previous',path),'Rollback failed')end
 error('Save failed: '..tostring(err))
end
print('SAVED. Credentials stay on this OC disk and are excluded from diagnostic reports.')
