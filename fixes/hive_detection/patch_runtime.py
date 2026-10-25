"""Exact source edits; preserves the live physical-hive and array-refresh code."""
def once(source, old, new):
    assert source.count(old) == 1, f'Unexpected runtime version: {old[:70]}'
    return source.replace(old, new, 1)

def patch(source):
    source = once(source,
        ' return c.invoke(a,m,table.unpack(args))\nend',
        " if a==T and m=='transferItem'and cfg.transferChecked then\n"
        '  return cfg.transferChecked(record.requiredTier,record.requiredFamily,table.unpack(args,1,5))\n'
        ' end\n return c.invoke(a,m,table.unpack(args))\nend')
    source = once(source,
        'local function move(from,to,source,dest,expected,key)\n guard()',
        "local function move(from,to,source,dest,expected,key)\n"
        ' if cfg.transferChecked then\n'
        '  if context and context.check then context.check()end\n'
        "  assert(not(context and context.stopping and context.stopping()),'换蜂已暂停，保留现场')\n"
        ' else guard()end')
    source = once(source,
        " record.holding=nil;save('recovered')",
        " record.holding=nil;save('recovered')\n"
        ' -- Only this bank slot changed; move() read back its complete contents.\n'
        ' chosen.item=row;chosen.count=row.count;chosen.empty=false')
    source = once(source, 'recover(cells);cells=bank(size);best=choose(cells,need,family)',
                  'recover(cells);best=choose(cells,need,family)')
    if '-- BEC_V3_ARRAY_REFRESH_1' in source:
        source = once(source,
            " local refresh=h>0 and cfg.arrayHiveReady and not cfg.arrayHiveReady(\n"
            '  known and known.count or nil,p)\n'
            " if refresh then print('实体总线有蜂群，但观测阵列未识别；暂停整组，回收后重新装入刷新。')end\n",
            '')
        source = once(source,
            ' if refresh then keeping=false end',
            ' -- A mandatory type change will refresh every array after loading.\n'
            ' -- Read old array caches only when considering keeping this hive.\n'
            ' local refresh=keeping and cfg.arrayHiveReady and not cfg.arrayHiveReady(\n'
            '  old and sameBinding(old.binding)and old.holding and old.holding.count or nil,p)\n'
            " if refresh then print('实体总线有蜂群，但观测阵列未识别；暂停整组，回收后重新装入刷新。');keeping=false end")
    return source
