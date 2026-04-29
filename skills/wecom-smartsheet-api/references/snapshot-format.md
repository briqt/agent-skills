# 企微智能表格后端 API 逆向发现

## 核心接口

### dop-api/opendoc
- GET 请求，返回 JSON
- 认证：Cookie（wedoc_sid, wedoc_skey, wedoc_ticket, TOK）
- 数据在 `clientVars.collab_client_vars.initialAttributedText.text[0].smartsheet`
- 格式：base64 + zlib deflate 压缩
- chunk 模式：多段 base64 用逗号分隔，part1=表结构，part2=记录数据

### URL 参数
- `id` = 文档 ID（如 s3_xxx）
- `scode` = 分享码
- `tab` = 工作表 ID（如 q979lj）
- `viewId` = 视图 ID
- `outformat=1`
- `supportOptimizedVer=4`
- `chunkCellSize=15000`
- `enableChunkRank=1`
- `normal=1`
- `startrow=0&endrow=N` — chunk 分页（大表必需）
- `wb=1&nowb=0` — 返回 workbook 信息
- `noEscape=1&enableSmartsheetSplit=1` — 启用分段模式

## 快照压缩 key 映射

### 表结构（part1）
```
root[0][0].c = {
  k1: tableId,
  k2: hidden,
  k3: {
    k1: recordMap (空表或小表直接包含),
    k2: recordMetaMap,
    k3: fieldMap {
      [fieldId]: {
        k30: title,
        k31: type,
        k1/k2/k4/k7/k17: property (按类型不同)
      }
    },
    k4: views [{
      k30: viewId,
      k31: title,
      k32: type,
      k34: ownerId,
      k1: { k2: fieldIds, k5: colInfos, k7: sortInfos, k8: filterInfos, k9: groupInfos }
    }],
    k5: userMap { [userId]: { k1: id, k2: name, k3: avatar, k6: corpName } },
    k9: primaryFieldId,
    k12: visibility/editability,
    k16: rankInfo { k1: viewRankMap, k3: nextRank }
  }
}
```

### 记录数据（part2，chunk 模式）
```
root[0][0].c = {
  k1: tableId,
  k2: {
    k1: recordMap {
      [recordId]: {
        k2: [  // 字段值数组
          {
            k30: fieldType,
            k100: fieldId,
            k1: [{k1:'text', k2:'内容'}],  // 文本
            k2: numericValue,                // 数字
            k4: timestamp,                   // 日期
            k5: [{k1:id, k2:title, k3:url}], // 附件
            k7: [{k1:userId}],               // 成员
            k17: ['optionId'],               // 选项
            k25: {k1:seq, k2:text},          // 自动编号
          }
        ]
      }
    },
    k2: recordMetaMap {
      [recordId]: {
        k1: createdTime,
        k2: createdUserId,
        k31: lastModifiedUserId,
        k32: lastModifiedTime
      }
    },
    k3: visibility,
    k5: { k6: { k1: { [recordId]: rankString } } }
  }
}
```

## 字段类型

| type | 含义 |
|------|------|
| 1 | 文本 |
| 2 | 数字 |
| 4 | 日期 |
| 5 | 附件 |
| 7 | 成员 |
| 9 | 多选 |
| 10 | 创建人 |
| 11 | 最后修改人 |
| 12 | 创建时间 |
| 13 | 最后修改时间 |
| 17 | 单选 |
| 25 | 自动编号 |

## 选项字段 property

```
field.property.k9 = [{ k1: optionId, k2: optionText, k3: color }]
```

## 记录元信息

- `k1` = 创建时间
- `k2` = 创建人 userId
- `k31` = 最后修改人 userId
- `k32` = 最后修改时间

系统字段（创建人/时间、最后修改人/时间）如果 cell 内没有显式值，从 recordMetaMap 回填。

## 解析流程

1. 解 part1 → fieldMap / views / userMap / primaryFieldId
2. 解 part2 → recordMap / recordMetaMap / rankMap
3. 遍历 record.k2 的 cell 数组，用 k100 找字段定义
4. 选项字段用 property.k9 翻译
5. 大表按 startrow/endrow 循环请求
