# 云端业务数据与版本备份

## 初始化（本次首次开发）

在 TripTrail 数据库连接中执行完整的 docs/cloud-initialize.sql，只执行一次。
它删除旧 triptrail_cloud_records JSON 测试表和旧 RPC，在一个事务内创建关系表与备份存储。
不修改其他业务表，也不会删除 App 本机内容。不要把初始化脚本用于后续升级。全新环境初始化后还需执行 `cloud-recycle.sql`。
cloud-schema.sql 是业务部分，cloud-backups.sql 是备份部分；执行合并文件后无需再执行分文件。

业务表：triptrail_trips、triptrail_trip_days、triptrail_trip_items、triptrail_stories、
triptrail_story_days、triptrail_story_entries、triptrail_favorites，以及媒体/凭证子表。
固定字段使用标量列，关联通过外键维护；日期沿用客户端契约，以 epoch 毫秒存储。
数据库不持久化整条内容的 JSON。triptrail_cloud_records 现在是只读聚合视图，JSON 仅用于传输。
triptrail_save_record 在事务内检查版本并写入关系表；子记录失败会整体回滚。
仍以一个旅程/足迹/收藏为冲突判断单位，不做逐字段自动合并。
备份表 triptrail_backups 独立于实时业务。triptrail-backups 桶存完整快照，
triptrail-media 桶存同步媒体；后续编辑实时记录不会覆盖已有备份。

## 配置与访问范围

iOS 的 Config/Cloud.local.xcconfig 和 Android 的 cloud.local.properties 为已忽略本地文件，
两端编译时内置客户端 Key，不要求最终用户填写，也不要强制加入 Git。
Project URL 为 https://spb-nxpqknocdb70j1pz.supabase.opentrust.net 。
安装包中的 anon Key 是公开客户端凭据，客户端不使用数据库密码或 service_role Key。
按产品要求不登录，公开共享业务内容与备份。备份桶不开放裸公开 URL，但持客户端 Key 的用户可以访问。
SQL 使用 SECURITY INVOKER，兼容阿里云限制；RLS 权限仅用于 TripTrail 专用表/桶。
所有用户共享 anon 权限，第三方可以直接操作这些专用表。这不是私人备份服务。

## App 入口

- 旅程、足迹操作菜单，收藏长按菜单：本地内容可设为云端，云端内容不提供转回本地的入口。
- “＋”直接进入创建页；旅程与收藏页内选择普通新建或智能录入，足迹直接填写。业务内容没有手动云端导入入口。
- 我的 → 数据管理 → 导出备份：导出本地 / 上传云端。
- 恢复备份：从本地文件导入 / 从云端恢复。
- 备份管理：按服务器时间倒序列出版本，可以导出文件、恢复或删除指定版本。
- 导入分享文件：本地旅程/足迹分享文件追加到当前内容，与替换全量数据的备份恢复不同。

## 同步、离线与备份

各设备打开旅程、足迹、收藏时自动发现并下载尚未在本机的云端内容；已关联内容按版本更新。
只在打开功能/云端卡片或手动同步时拉取，导航触发有 60 秒去重，不使用定时云端轮询。
编辑后的已关联内容自动上传；离线修改保留，下次打开或同步时重试。
设为云端后保持云端模式，本地仍有离线副本。同 ID 的独立本地记录不被自动覆盖。
删除云端项目会同步删除，其他设备下次打开相应功能或手动同步时移除本地副本。离线删除先保存队列，联网后补交，不会再次下载。

“我的 → 数据管理 → 回收站”可恢复一天内删除的旅程、足迹、收藏；云端回收站公开共享。本地项目仅在本机恢复。云端保留期以服务器收到删除时开始计算，重复提交不会延期。恢复后其他设备下次同步自动加载。

现有数据库执行 `docs/cloud-recycle.sql` 增量迁移。超过 24 小时服务器拒绝恢复；关系数据在访问回收站时清理，保留最小删除标记防止离线旧版本重新上传。共享媒体对象暂不清理，避免误删其他内容引用的图片。恢复云端备份仍由用户显式选择版本。
本次重建使用新同步绑定命名空间，旧测试记录的本地副本变为本地模式，可重新主动上传。

完整备份复用两端现有 .triptrailbackup 格式，包含可读取的图片/视频。
资源无法读取时先提示取消或跳过。云端以 8 MiB 分块传输，避免一次读入整个视频备份；
版本表记录总字节、分块数量、SHA-256、完成状态。所有分块上传完成才标记 ready。
下载后验证总大小和哈希，通过后才进入恢复确认。恢复前等待当前同步完成，
成功后清除旧同步绑定，恢复内容作为本地副本，不会把历史快照自动覆盖回共享云端。
上传/删除中断的版本在列表可见，可以重试删除；删除先标记 deleting，再删除分块，最后删除元数据。
删除备份不删除当前业务内容。本地文件由系统文件选择器管理，App 不擅自删除用户文件。

旧同步媒体不自动垃圾回收；旧测试表重建后遗留的对象可单独在 Storage 管理台清理。
初始化脚本不直接删除 Storage 元数据，避免产生无法追踪的物理对象。

## 验证

scripts/generate_cloud_schema.py 从 Swift 便携字段定义生成关系表 SQL。
scripts/test_cloud_schema.mjs 使用 PGlite 执行真实 PostgreSQL DDL/RPC，覆盖三类内容、媒体、
凭证、anon 权限、版本冲突、失败回滚、级联清理和备份状态；运行方式见脚本注释，测试实例完全隔离。

iOS CloudSyncTests.testLiveCloudBackupVersionRestoreAndDelete 仅当 App Documents 下存在
.cloud-live-test 标记时才访问真实云端；普通测试跳过。使用内存模型和独立测试备份验证多版本上传、
下载恢复、图片原件、校验失败及云端删除。真实环境验证只清理本次生成 UUID 的测试对象。
