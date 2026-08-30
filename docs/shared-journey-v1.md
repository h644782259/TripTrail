# TripTrail Shared Journey v1

`*.triptrail` 用于跨设备、跨平台分享单段行程或足迹。未包含媒体时是 UTF-8 JSON；包含媒体时是由清单 JSON 和原始媒体字节组成的 `TRIPTRAILPKG1` 容器。

- UTI: `com.personal.triptrail.shared-journey`
- MIME: `application/vnd.triptrail.journey`
- 文件扩展名: `.triptrail`
- 日期: ISO 8601
- 当前 `formatVersion`: `1`

## 轻量 JSON 顶层结构

```json
{
  "format": "triptrail.shared-journey",
  "formatVersion": 1,
  "sharedAt": "2026-08-29T15:50:00Z",
  "kind": "trip",
  "trip": {}
}
```

`kind` 取值为 `trip` 或 `footprint`，并且只能分别携带 `trip` 或 `story` 一个内容对象。UUID 用字符串表示。

## 导入规则

1. 先校验 `format`、`formatVersion`、`kind` 和对应内容对象，再展示只读预览。
2. 只有用户主动确认收藏后才写入本地。
3. 以行程或足迹的根 UUID 去重；同一交换包重复导入不产生副本。
4. 导入是追加操作，不覆盖接收方已有内容。
5. 足迹中的 `sourceTripID`、`sourceDayID`、`sourceItemID` 和同步选择在分享时移除。
6. 未勾选媒体时，`MediaReference` 不进入交换包。
7. 勾选媒体时，交换包保存媒体引用 UUID 和原始文件字节，但不会发送分享者的 `PHAsset.localIdentifier`；导入端写入自己的相簿后生成新标识。

## 带媒体容器

1. UTF-8 魔数 `TRIPTRAILPKG1\n`。
2. 8 字节大端无符号整数，表示清单 JSON 的字节数。
3. 清单 JSON，包含 `format`、`formatVersion`、`kind`、内容 JSON 和媒体数组。
4. 按媒体数组顺序拼接原始媒体字节；每段长度由 `byteCount` 给出。

分享文件的容器 `kind` 为 `sharedJourney`。同样的容器也用于 `.triptrailbackup` 完整换机备份，其 `kind` 为 `backup`。

完整字段以 [`DataBackupService.swift`](../TripTrail/Services/DataBackupService.swift) 中的 `SharedJourneyFile`、`TripRecord` 和 `StoryRecord` 为准。
