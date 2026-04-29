#!/usr/bin/env node
/**
 * fetch-smartsheet.mjs
 *
 * 通过企微后端 dop-api/opendoc 接口获取智能表格数据。
 * 与浏览器前端完全一致的请求方式。
 *
 * 用法：
 *   node fetch-smartsheet.mjs <smartsheet-url> [cookie-string]
 *
 * 环境变量：
 *   WECOM_COOKIE      Cookie 字符串
 *   WECOM_STARTROW    起始行（默认 0）
 *   WECOM_ENDROW      结束行（设置后仅请求这一页）
 *   WECOM_PAGE_SIZE   自动分页大小（默认 500）
 *
 * 示例：
 *   node fetch-smartsheet.mjs "https://doc.weixin.qq.com/smartsheet/s3_xxx?scode=xxx&tab=q979lj&viewId=vukaF8"
 */

import { inflate } from 'node:zlib';
import { promisify } from 'node:util';

const inflateAsync = promisify(inflate);

const FIELD_TYPE_MAP = {
  1: 'text',
  2: 'number',
  4: 'date',
  5: 'attachment',
  7: 'member',
  9: 'multiSelect',
  10: 'createdBy',
  11: 'lastEditedBy',
  12: 'createdTime',
  13: 'lastEditedTime',
  17: 'singleSelect',
  25: 'autoNumber',
};

// ─── URL 解析 ───

function parseSmartsheetUrl(url) {
  const u = new URL(url);
  const pathMatch = u.pathname.match(/\/smartsheet\/([^/?]+)/);
  const docId = pathMatch ? pathMatch[1] : null;
  const scode = u.searchParams.get('scode');
  const tab = u.searchParams.get('tab');
  const viewId = u.searchParams.get('viewId');
  return { docId, scode, tab, viewId };
}

// ─── Cookie 提取 ───

function extractCookieFromBrowser() {
  return process.env.WECOM_COOKIE || '';
}

// ─── 核心请求 ───

async function fetchOpendoc({ docId, scode, tab, viewId, cookie, startrow, endrow }) {
  const params = new URLSearchParams({
    scode,
    tab,
    viewId,
    id: docId,
    outformat: '1',
    supportOptimizedVer: '4',
    chunkCellSize: '15000',
    enableChunkRank: '1',
    normal: '1',
    wb: '1',
    nowb: '0',
    noEscape: '1',
    enableSmartsheetSplit: '1',
    startrow: String(startrow),
    endrow: String(endrow),
  });

  const url = `https://doc.weixin.qq.com/dop-api/opendoc?${params}`;
  const resp = await fetch(url, {
    headers: {
      'Cookie': cookie,
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
      'Referer': `https://doc.weixin.qq.com/smartsheet/${docId}`,
    },
  });

  if (!resp.ok) {
    throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
  }

  return resp.json();
}

// ─── 快照解码 ───

async function decodeSnapshot(base64Data) {
  const binary = Buffer.from(base64Data, 'base64');
  const decompressed = await inflateAsync(binary);
  return JSON.parse(decompressed.toString('utf-8'));
}

async function decodeSmartsheetParts(smartsheetData) {
  if (!smartsheetData) {
    return [];
  }

  const parts = smartsheetData
    .split(',')
    .map(part => part.trim())
    .filter(Boolean);

  return Promise.all(parts.map(decodeSnapshot));
}

function getSmartsheetPayload(data) {
  return data?.clientVars?.collab_client_vars?.initialAttributedText?.text?.[0]?.smartsheet || '';
}

// ─── 快照 → 可读数据 ───

function formatTimestamp(timestamp) {
  if (!timestamp) {
    return null;
  }

  const date = new Date(Number(timestamp));
  if (Number.isNaN(date.getTime())) {
    return timestamp;
  }

  return date.toISOString();
}

function joinRichText(nodes) {
  if (!Array.isArray(nodes)) {
    return '';
  }

  return nodes.map(node => node?.k2 || '').join('');
}

function extractFieldProperty(fieldData) {
  return fieldData.k1 || fieldData.k2 || fieldData.k4 || fieldData.k7 || fieldData.k17 || null;
}

function parseFieldOptions(property) {
  const rawOptions = property?.k9;
  if (!Array.isArray(rawOptions)) {
    return [];
  }

  return rawOptions.map(option => ({
    id: option?.k1,
    text: option?.k2 || option?.k30 || option?.k31 || option?.k1,
    color: option?.k3,
  }));
}

function buildStructureFromSnapshot(snapshot) {
  const root = snapshot?.[0]?.[0];
  const content = root?.c || {};
  const workbook = content.k3 || {};
  const rawFields = workbook.k3 || {};
  const rawViews = workbook.k4 || [];
  const rawUsers = workbook.k5 || {};

  const fields = {};
  for (const [fieldId, fieldData] of Object.entries(rawFields)) {
    const type = fieldData.k31;
    const property = extractFieldProperty(fieldData);
    const options = parseFieldOptions(property);
    const optionMap = Object.fromEntries(options.map(option => [option.id, option.text]));

    fields[fieldId] = {
      id: fieldId,
      title: fieldData.k30,
      type,
      typeName: FIELD_TYPE_MAP[type] || `unknown(${type})`,
      property,
      options,
      optionMap,
    };
  }

  const views = rawViews.map(view => ({
    id: view.k30,
    title: view.k31,
    type: view.k32,
    ownerId: view.k34,
    fieldIds: view.k1?.k2 || [],
  }));

  const users = {};
  for (const [userId, userData] of Object.entries(rawUsers)) {
    users[userId] = {
      id: userData.k1,
      name: userData.k2,
      avatar: userData.k3,
      corpName: userData.k6,
    };
  }

  return {
    tableId: content.k1,
    fields,
    views,
    users,
    primaryFieldId: workbook.k9,
    inlineRecordContainer: {
      recordMap: workbook.k1 || {},
      recordMetaMap: workbook.k2 || {},
      rankMap: workbook.k16?.k1 || {},
    },
  };
}

function getRecordContainer(recordSnapshot) {
  const root = recordSnapshot?.[0]?.[0];
  const content = root?.c || {};
  const block = content.k2 || {};

  return {
    recordMap: block.k1 || {},
    recordMetaMap: block.k2 || {},
    rankMap: block.k5?.k6?.k1 || {},
  };
}

function getOrderedFieldIds({ fields, views, viewId }) {
  const activeView = views.find(view => view.id === viewId);
  const fromView = activeView?.fieldIds?.filter(fieldId => fields[fieldId]);
  if (fromView?.length) {
    return fromView;
  }

  return Object.keys(fields);
}

function parseAttachmentList(rawAttachments) {
  if (!Array.isArray(rawAttachments)) {
    return [];
  }

  return rawAttachments.map(file => ({
    id: file?.k1,
    title: file?.k2,
    url: file?.k3,
    width: file?.k4,
    height: file?.k5,
  }));
}

function parseMemberList(rawMembers, users) {
  if (!Array.isArray(rawMembers)) {
    return [];
  }

  return rawMembers.map(member => ({
    id: member?.k1,
    name: users[member?.k1]?.name || member?.k1,
  }));
}

function parseOptionValue(rawIds, field) {
  if (!Array.isArray(rawIds)) {
    return field?.type === 17 ? null : [];
  }

  const values = rawIds.map(optionId => field?.optionMap?.[optionId] || optionId);
  return field?.type === 17 ? (values[0] || null) : values;
}

function parseCellValue(cell, field, users) {
  const type = cell?.k30 || field?.type;

  switch (type) {
    case 1:
      return joinRichText(cell.k1);
    case 2:
      return cell.k2 ?? null;
    case 4:
      return formatTimestamp(cell.k4);
    case 5:
      return parseAttachmentList(cell.k5);
    case 7:
      return parseMemberList(cell.k7, users);
    case 9:
    case 17:
      return parseOptionValue(cell.k17, field);
    case 25:
      return cell.k25?.k2 || cell.k25?.k1 || null;
    default:
      break;
  }

  if (Array.isArray(cell?.k1)) {
    return joinRichText(cell.k1);
  }
  if (cell?.k2 !== undefined) {
    return cell.k2;
  }
  if (cell?.k4) {
    return formatTimestamp(cell.k4);
  }
  if (Array.isArray(cell?.k5)) {
    return parseAttachmentList(cell.k5);
  }
  if (Array.isArray(cell?.k7)) {
    return parseMemberList(cell.k7, users);
  }
  if (Array.isArray(cell?.k17)) {
    return parseOptionValue(cell.k17, field);
  }
  if (cell?.k25) {
    return cell.k25?.k2 || cell.k25?.k1 || null;
  }

  return null;
}

function buildSystemFieldValue(field, meta, users) {
  switch (field?.type) {
    case 10:
      return meta?.createdUserId ? (users[meta.createdUserId]?.name || meta.createdUserId) : null;
    case 11:
      return meta?.lastModifiedUserId ? (users[meta.lastModifiedUserId]?.name || meta.lastModifiedUserId) : null;
    case 12:
      return formatTimestamp(meta?.createdTime);
    case 13:
      return formatTimestamp(meta?.lastModifiedTime);
    default:
      return null;
  }
}

function parseRecords({ recordContainer, fields, users, orderedFieldIds }) {
  const rawRecordMap = recordContainer?.recordMap || {};
  const rawRecordMetaMap = recordContainer?.recordMetaMap || {};
  const rankMap = recordContainer?.rankMap || {};

  const rankedIds = Object.keys(rankMap);
  const fallbackIds = Object.keys(rawRecordMap).filter(recordId => !rankMap[recordId]);
  const recordIds = rankedIds.length ? [...rankedIds, ...fallbackIds] : Object.keys(rawRecordMap);

  const records = [];
  for (const recordId of recordIds) {
    const rawRecord = rawRecordMap[recordId];
    if (!rawRecord) {
      continue;
    }

    const rawCells = Array.isArray(rawRecord.k2) ? rawRecord.k2 : [];
    const valueByFieldId = {};

    for (const cell of rawCells) {
      const fieldId = cell?.k100;
      if (!fieldId) {
        continue;
      }

      const field = fields[fieldId] || {
        id: fieldId,
        title: fieldId,
        type: cell?.k30,
        typeName: FIELD_TYPE_MAP[cell?.k30] || `unknown(${cell?.k30})`,
        optionMap: {},
      };

      valueByFieldId[fieldId] = parseCellValue(cell, field, users);
    }

    const rawMeta = rawRecordMetaMap[recordId] || {};
    const meta = {
      createdTime: rawMeta.k1,
      createdUserId: rawMeta.k2,
      lastModifiedUserId: rawMeta.k31,
      lastModifiedTime: rawMeta.k32,
    };

    const valueByTitle = {};
    for (const fieldId of orderedFieldIds) {
      const field = fields[fieldId];
      let value = valueByFieldId[fieldId];
      if (value === undefined) {
        value = buildSystemFieldValue(field, meta, users);
      }
      valueByTitle[field.title] = value ?? null;
    }

    records.push({
      id: recordId,
      rank: rankMap[recordId] || null,
      meta: {
        createdTime: formatTimestamp(meta.createdTime),
        createdUserId: meta.createdUserId,
        createdUserName: users[meta.createdUserId]?.name || meta.createdUserId || null,
        lastModifiedUserId: meta.lastModifiedUserId,
        lastModifiedUserName: users[meta.lastModifiedUserId]?.name || meta.lastModifiedUserId || null,
        lastModifiedTime: formatTimestamp(meta.lastModifiedTime),
      },
      valueByFieldId,
      valueByTitle,
    });
  }

  return records;
}

function formatDisplayValue(value) {
  if (value === null || value === undefined) {
    return 'null';
  }

  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }

  return JSON.stringify(value, null, 2);
}

async function loadSmartsheet({ docId, scode, tab, viewId, cookie, startrow, endrow, pageSize }) {
  let currentStart = startrow;
  let currentEnd = endrow ?? (startrow + pageSize);
  const fixedRange = endrow !== undefined;

  let structure = null;
  const recordMap = new Map();
  let requestIndex = 0;

  while (true) {
    requestIndex += 1;
    const data = await fetchOpendoc({
      docId,
      scode,
      tab,
      viewId,
      cookie,
      startrow: currentStart,
      endrow: currentEnd,
    });

    if (!structure) {
      structure = data;
    }

    const smartsheetPayload = getSmartsheetPayload(data);
    const snapshots = await decodeSmartsheetParts(smartsheetPayload);
    const [structureSnapshot, recordSnapshot] = snapshots;

    const parsedStructure = buildStructureFromSnapshot(structureSnapshot);
    const orderedFieldIds = getOrderedFieldIds({
      fields: parsedStructure.fields,
      views: parsedStructure.views,
      viewId,
    });

    let recordContainer = null;
    if (recordSnapshot) {
      recordContainer = getRecordContainer(recordSnapshot);
    } else if (requestIndex === 1) {
      recordContainer = parsedStructure.inlineRecordContainer;
    }

    const pageRecords = parseRecords({
      recordContainer,
      fields: parsedStructure.fields,
      users: parsedStructure.users,
      orderedFieldIds,
    });

    let newCount = 0;
    for (const record of pageRecords) {
      if (!recordMap.has(record.id)) {
        newCount += 1;
      }
      recordMap.set(record.id, record);
    }

    console.log(`分页 ${requestIndex}: startrow=${currentStart}, endrow=${currentEnd}, 记录=${pageRecords.length}, 新增=${newCount}`);

    const isSplit = snapshots.length > 1;
    if (!isSplit || fixedRange || pageRecords.length === 0 || newCount < pageSize) {
      return {
        data,
        structure: parsedStructure,
        records: [...recordMap.values()],
      };
    }

    currentStart += pageSize;
    currentEnd += pageSize;
  }
}

// ─── 主流程 ───

async function main() {
  const url = process.argv[2];
  if (!url) {
    console.error('用法: node fetch-smartsheet.mjs <smartsheet-url> [cookie]');
    process.exit(1);
  }

  const cookie = process.argv[3] || extractCookieFromBrowser();
  if (!cookie) {
    console.error('需要 Cookie。通过第二个参数传入，或设置 WECOM_COOKIE 环境变量。');
    console.error('从浏览器获取: document.cookie');
    process.exit(1);
  }

  const startrow = Number(process.env.WECOM_STARTROW || 0);
  const endrowEnv = process.env.WECOM_ENDROW;
  const endrow = endrowEnv === undefined ? undefined : Number(endrowEnv);
  const pageSize = Number(process.env.WECOM_PAGE_SIZE || 500);

  const { docId, scode, tab, viewId } = parseSmartsheetUrl(url);
  if (!docId || !scode || !tab) {
    throw new Error('无法从 URL 解析 docId/scode/tab，请确认是完整的智能表格链接。');
  }

  console.log(`文档: ${docId}`);
  console.log(`表格: ${tab}, 视图: ${viewId || '(默认)'}`);
  console.log(`分页: startrow=${startrow}, ${endrow !== undefined ? `endrow=${endrow}` : `pageSize=${pageSize}`}`);

  const { data, structure, records } = await loadSmartsheet({
    docId,
    scode,
    tab,
    viewId,
    cookie,
    startrow,
    endrow,
    pageSize,
  });

  console.log(`状态: ${data.padType}, 标题: ${data.clientVars?.title || data.clientVars?.initialTitle}`);

  console.log('\n─── 表结构 ───');
  console.log(`主字段: ${structure.primaryFieldId}`);
  console.log(`字段数: ${Object.keys(structure.fields).length}`);
  for (const field of Object.values(structure.fields)) {
    console.log(`  ${field.id}: ${field.title} (${field.typeName})`);
  }

  console.log(`\n视图数: ${structure.views.length}`);
  for (const view of structure.views) {
    console.log(`  ${view.id}: ${view.title}`);
  }

  console.log(`\n用户数: ${Object.keys(structure.users).length}`);
  for (const user of Object.values(structure.users)) {
    console.log(`  ${user.id}: ${user.name} (${user.corpName})`);
  }

  console.log(`\n─── 记录数据 ───`);
  console.log(`记录数: ${records.length}`);

  if (records[0]) {
    console.log('\n第一行数据:');
    for (const [title, value] of Object.entries(records[0].valueByTitle)) {
      console.log(`  ${title}: ${formatDisplayValue(value)}`);
    }
  }

  if (process.env.DEBUG) {
    console.log('\n─── 第一条记录（完整 JSON）───');
    console.log(JSON.stringify(records[0] || null, null, 2));
  }
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
