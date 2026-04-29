---
name: wecom-smartsheet
description: 读取企业微信智能表格数据。通过浏览器 JS 内存逆向读取已登录页面的数据模型，绕过官方 API「只能操作自己创建的文档」的限制。使用场景：(1) 读取表结构、字段定义、枚举选项 (2) 按视图查询记录数据 (3) 跨工作表读取 (4) 统计分析表格数据。触发词：企业微信、企微、智能表格、多维表格、wecom、smartsheet。前置条件：browser 工具可用且浏览器已登录企业微信文档。
---

# 企业微信智能表格读取

企微智能表格用 Canvas 渲染，DOM 无单元格数据，但 JS 内存中保存了完整数据模型。

## 入口

```
window.getPreloadedTablesManager()
  → mgr.getCompleteTableByTableId(tableId)   // 异步，必须 await
```

从 URL 提取参数：`tab=` → tableId，`viewId=` → viewId。

## 读取

```javascript
async () => {
  const mgr = window.getPreloadedTablesManager();
  const table = await mgr.getCompleteTableByTableId(TABLE_ID);
  const v = table.views.find(v => v.id === VIEW_ID);
  const rids = v.properties.recordIds.slice(0, N);
  const fids = v.properties.fieldIds;
  const fieldMap = {};
  for (const fid of fids) {
    const f = table.getFieldByFieldId(fid);
    fieldMap[fid] = f ? f.title : fid;
  }
  const rows = [];
  for (const rid of rids) {
    const row = { _id: rid };
    for (const fid of fids) {
      const cell = table.getCell(rid, fid);
      if (!cell || !cell.value) { row[fieldMap[fid]] = null; continue; }
      const val = cell.value;
      const f = table.getFieldByFieldId(fid);
      if (Array.isArray(val) && (f.type === 9 || f.type === 17)) {
        const opts = (f.property && f.property.options) || [];
        row[fieldMap[fid]] = val.map(v => { const o = opts.find(o => o.id === v); return o ? o.text : v; });
      } else if (Array.isArray(val)) {
        row[fieldMap[fid]] = val.map(v => v.text || v.title || v.id || v).join('');
      } else if (typeof val === 'object') {
        row[fieldMap[fid]] = val.text || val.seq || JSON.stringify(val);
      } else { row[fieldMap[fid]] = val; }
    }
    rows.push(row);
  }
  return JSON.stringify(rows).substring(0, 4000);
}
```

## 字段类型速查

| type | 含义 | value 格式 |
|------|------|-----------|
| 1 | 文本 | `[{type:'text', text:'...'}]` |
| 2 | 数字 | 数值 |
| 4 | 日期 | 毫秒时间戳 |
| 5 | 附件 | `[{title, imageUrl}]` |
| 7 | 成员 | `[{id:'userId'}]` |
| 9 | 多选 | `['optionId']`，需从 `field.property.options` 翻译 |
| 17 | 单选 | 同上 |
| 25 | 自动编号 | `{seq, text}` |

更多字段类型详见 [references/field-types.md](references/field-types.md)。
完整 API 方法列表详见 [references/api-methods.md](references/api-methods.md)。

## 注意事项

- `getCompleteTableByTableId` 返回 Promise，必须 await
- 大表分批读取（每次 50-100 行），避免 evaluate 超时
- evaluate 返回值用 `JSON.stringify().substring(0, N)` 截断
- 视图的 `recordIds` 已过筛选和排序，反映用户看到的顺序
- open/navigate 可能报超时但页面实际已加载，用 tabs 确认即可
