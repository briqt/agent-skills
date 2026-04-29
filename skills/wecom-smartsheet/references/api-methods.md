# API 方法分类参考

按企微智能表格内部架构组织。table 对象由多个 Partial（数据分片）和 Service（服务）组合而成。

## 获取 table 对象

```javascript
const mgr = window.getPreloadedTablesManager();
const table = await mgr.getCompleteTableByTableId(tableId);  // 异步
```

管理器：
- `getAllTableInfosWithPreload()` — 列出所有工作表
- `getCompleteTableByTableId(id)` — 获取完整表（Promise）
- `isTableExisted(id)` — 检查表是否存在

---

## 一、fieldsPartial — 字段定义

数据存储在 `table.fieldsPartial`，方法委托到 table 上。

### 读取
- `getFields()` — 所有字段对象
- `getFieldByFieldId(fid)` — 单个字段 `{id, title, type, property}`
- `getFieldCount()` / `getAllFieldIds()` / `isFieldExist(fid)`
- `getPrimaryFieldId()` — 主字段
- `getFieldMapJSON()` — 字段快照

### 写入
- `createField({fieldId, fieldJSON: {type, title, property}})` — 创建字段对象
- `setField(fid, fieldObject)` — 添加字段到表
- `deleteFieldByFieldId(fid)` — 删除字段
- `getNewFieldId()` — 生成 ID
- `field.setProperty(newProperty)` — 修改字段属性（选项、格式等）

### fieldHelper — 字段类型注册表
- `table.fieldHelper.get(typeId)` — 获取字段类型构造器

---

## 二、tableFieldGroupPartial — 字段分组

- `getFieldGroups()` — 所有分组
- `getFieldGroupByFieldId(fid)` — 字段所属分组
- `setFieldGroup(...)` / `deleteFieldGroupByFieldGroupId(...)`
- `getFieldIdListOrderedByFieldGroup()` — 按分组排序的字段列表

---

## 三、records + recordMetaMap — 记录与单元格

记录数据存在 `table.records`，元信息在 `table.recordMetaMap`。

### 读取
- `getCell(rid, fid)` — 单元格 `{type, value}` 或 `null`
- `getRecordByRecordId(rid)` — 整行 `{fieldId: cellData}`
- `getRecordCount()` / `getRecordIdList()` / `isRecordExist(rid)`
- `getRecordMetaByRecordId(rid)` — `{createdTime, createdUserId}`
- `getRecordMapJSON()` — 记录快照

### 写入
- `setCellJSON(rid, fid, cellData)` — 写入单元格（核心方法，实时渲染）
- `insertRecords(recordIds, viewRankMaps, tableRanks)` — 新增记录
- `deleteRecords([rid])` — 删除记录
- `getNewRecordId()` / `getNewRecordIds(count)` — 生成 ID
- `setPartialRecordsMeta({rid: {createdTime, createdUserId}})` — 设置元信息

### 新增记录

```javascript
const rm = table.rankManager;
const newId = table.getNewRecordId();
const nextRank = rm.getNextRank(false);
table.insertRecords([newId], [{ [viewId]: nextRank }], [nextRank]);
table.setPartialRecordsMeta({ [newId]: { createdTime: Date.now(), createdUserId: uid } });
```

---

## 四、views + viewModelHelper — 视图

每个视图是独立对象，内含 sortPartial、filterPartial、viewDescriptionPartial 等子模块。

### table 级别
- `getAllViews()` / `getAllVisibleViews()` — 视图列表
- `getViewByViewId(vid)` — 单个视图
- `getViewCount()` / `getViewIdList()`
- `insertView({viewId, title, type, publicLevel, index, properties, rankMap})`
- `deleteView(vid)` / `moveView(vid, from, to)`
- `getNewViewId()` / `getViewMapJSON()`

### 视图对象方法

#### 记录与排序
- `getDisplayedRecordIds()` — 当前显示的记录（已过滤+排序）
- `getAllRecordIds()` — 视图内所有记录
- `getSortInfos()` / `setSortInfos(infos)` — 排序配置
- `isAutoSort()` / `setAutoSort(bool)`

#### 筛选
- `getFilterInfos()` / `setFilterInfos(infos)` — 筛选条件
- `isFilterField(fid)` — 是否为筛选字段

#### 分组
- `getGroupInfos()` / `setGroupInfos(infos)` — 分组配置
- `isGrouped()` — 是否有分组
- `getGroupTree()` — 分组树结构
- `getGroupRecordIdsByPath(path)` — 按分组路径获取记录

#### 字段显示
- `getVisibleFieldIds()` — 可见字段
- `isFieldHidden(fid)` / `setFieldsHidden(fids, hidden)`
- `setColumnWidth(fid, width)` / `getColumnWidth(fid)`
- `getFrozenFieldCount()` / `setFrozenFieldCount(n)` — 冻结列
- `moveFieldIndex(from, to)` — 调整字段顺序

#### 外观
- `getRowHeightLevel()` / `setRowHeightLevel(level)` — 行高
- `isCardMode()` / `getCardModeConfig()` / `setCardModeConfig(config)` — 看板模式
- `setViewColorConfig(config)` / `getViewColorConfig()` — 颜色配置
- `getFieldAlignment(fid)` / `setFieldAlignment(fid, align)` — 对齐

#### 统计
- `isFieldStatEnabled()` — 是否启用字段统计
- `getFieldStatResults()` — 统计结果
- `displayFieldStat()` / `hideFieldStat()`

#### 描述
- `getDescription()` / `setDescription(desc)` — 视图描述

---

## 五、rankManager — 排序管理

全局记录排序，新增记录必需。

- `getNextRank(false)` — 下一个可用 rank 字符串
- `getRankMap()` — `{recordId: rankString}`
- `getAllRecordIds()` — 按 rank 排序的 ID
- `checkRankExist(rid)` — 检查 rank 是否存在

---

## 六、userMapPartial + userService — 用户

- `getUserInfo(userId)` — `{id, name, avatarUrl, corpName}`
- `getUserInfoByName(name)` — 按名称查
- `getUserMap()` — 所有用户映射
- `hasUserInfo(userId)` — 是否有缓存

---

## 七、tableDescriptionPartial — 表描述

- `getDescription()` / `setDescription(desc)` / `clearDescription()`

---

## 八、commentMapPartial — 评论

- `getCommentCountByRecordId(rid)` — 评论数
- `getRecordCommentData(rid)` — 评论内容
- `getCommentIdByRecordId(rid)` / `getRecordIdByCommentId(cid)`
- `addCommentId(...)` / `deleteCommentId(...)`

---

## 九、permissionService — 权限

- `getPermissionStatus()` — 当前权限状态
- `getPermissionPolicy()` — 权限策略
- `isRecordPermissionField(fid)` — 是否为权限控制字段
- `getRecordPermissionFields()` — 权限字段列表

---

## 十、表级别元数据

- `getTitle()` / `setTitle(name)` — 表标题
- `toJSON()` — 完整快照（fieldMap + recordMap + viewMap + userMap）
- `totalRecordCount` / `getRecordCount()`
- `getMaxRowNum()` / `getMaxColNum()` / `getMaxCellNum()` — 容量限制
