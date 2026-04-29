# 字段类型详细参考

## 完整类型映射

| type | 含义 | value 格式 | 可写 |
|------|------|-----------|------|
| 1 | 文本 | `[{type:'text', text:'内容', format:{bold:false, italic:false, underline:false, strikeThrough:false}}]` | ✅ |
| 2 | 数字 | 数值（如 `42`、`3.14`） | ✅ |
| 4 | 日期 | 毫秒时间戳（如 `1775697585541`） | ✅ |
| 5 | 附件/图片 | `[{id, title, imageUrl, width, height}]` | ❓ 未验证 |
| 7 | 成员 | `[{id:'userId'}]`，多选时数组多个元素 | ❓ 未验证 |
| 9 | 多选 | `['optionId1', 'optionId2']`，需从 `field.property.options` 翻译 | ✅ |
| 10 | 创建人 | 自动字段，只读 | ❌ |
| 11 | 最后编辑人 | 自动字段，只读 | ❌ |
| 12 | 创建时间 | 自动字段，只读 | ❌ |
| 13 | 最后编辑时间 | 自动字段，只读 | ❌ |
| 17 | 单选/进度 | `['optionId']`，同多选但通常只一个元素 | ✅ |
| 25 | 自动编号 | `{seq:'1', text:'1', hash:'...'}` | ❌ 自动生成 |

## 选项字段（type 9 / 17）

选项定义在 `field.property.options` 中：

```javascript
field.property = {
  isMultiple: false,       // true=多选, false=单选
  isQuickAdd: true,        // 允许快速添加新选项
  options: [
    { id: 'optId1', text: '进行中', style: 1 },   // style 控制颜色
    { id: 'optId2', text: '已完成', style: 4 },
  ],
  defaultCellValue: null
}
```

### 选项 style 颜色映射

| style | 颜色 |
|-------|------|
| 1 | 红色 |
| 2 | 橙色 |
| 3 | 黄色 |
| 4 | 绿色 |
| 5 | 蓝色 |
| 6 | 紫色 |
| 10 | 灰色 |
| 21 | 浅蓝 |

### 添加选项

```javascript
const field = table.getFieldByFieldId(fieldId);
field.setProperty({
  ...field.property,
  options: [
    ...field.property.options,
    { id: 'newOptId', text: '新选项', style: 4 }
  ]
});
```

### 写入选项值

```javascript
// 单选
table.setCellJSON(rid, fid, { type: 17, value: ['optionId'] });
// 多选
table.setCellJSON(rid, fid, { type: 9, value: ['optId1', 'optId2'] });
```

## 日期字段（type 4）

```javascript
// 属性
field.property = {
  format: 'yyyy"年"m"月"d"日"',  // 显示格式
  autoFill: false                  // 是否自动填充当前日期
}

// 写入（毫秒时间戳）
table.setCellJSON(rid, fid, { type: 4, value: Date.now() });
// 指定日期
table.setCellJSON(rid, fid, { type: 4, value: new Date('2026-04-09').getTime() });
```

## 数字字段（type 2）

```javascript
// 属性
field.property = {
  decimalPlaces: 1,        // 小数位数
  useSeparate: true,       // 千分位分隔
  useDefaultDecimal: true,
  defaultCellValue: null
}

// 写入
table.setCellJSON(rid, fid, { type: 2, value: 42.5 });
```

## 文本字段（type 1）

```javascript
// 纯文本
table.setCellJSON(rid, fid, {
  type: 1,
  value: [{ type: 'text', text: '内容' }]
});

// 带格式
table.setCellJSON(rid, fid, {
  type: 1,
  value: [{
    type: 'text',
    text: '加粗内容',
    format: { bold: true, italic: false, underline: false, strikeThrough: false }
  }]
});

// 多段文本
table.setCellJSON(rid, fid, {
  type: 1,
  value: [
    { type: 'text', text: '第一段' },
    { type: 'text', text: '第二段', format: { bold: true } }
  ]
});
```
