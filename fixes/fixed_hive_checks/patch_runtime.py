"""Add batch-local layout/managed-port reuse to both supported runtimes."""
def once(source,old,new):
    assert source.count(old)==1,old[:80]
    return source.replace(old,new,1)

def patch(source):
    source=once(source,'local function discover()\n',
        'local discoveredSize\nlocal function discover()\n'
        ' if cfg.fixedBatchChecks and discoveredSize then\n'
        "  for _,a in ipairs({SOUTH,NORTH})do assert(call(a,'getOutput',0)==0,'蜂群IO已有红石输出，不能叠加操作')end\n"
        '  return discoveredSize\n end\n')
    source=once(source,' return size\nend\n',' discoveredSize=size;return size\nend\n')
    source=once(source,'local function emptyPorts()\n for _,side in ipairs({2,3}) do for slot=1,12 do\n',
        'local portsChecked=false\nlocal function emptyPorts()\n'
        ' local slots={}\n'
        ' if cfg.fixedBatchChecks and portsChecked then slots={1,7}else for i=1,12 do slots[#slots+1]=i end end\n'
        ' for _,side in ipairs({2,3}) do for _,slot in ipairs(slots)do\n')
    source=once(source,"  assert(stack(side,slot)==nil,'蜂群IO已有硬盘，保留未完成操作')\n end end\nend",
        "  assert(stack(side,slot)==nil,'蜂群IO已有硬盘，保留未完成操作')\n end end\n portsChecked=true\nend")
    source=once(source,' emptyPorts()\nend\nfunction M.ensure(ctx)',
        ' emptyPorts();portsChecked=false\nend\nfunction M.ensure(ctx)')
    return source
