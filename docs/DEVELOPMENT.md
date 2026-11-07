# v3.4.0 b10 适配记录

## 基线

- 用户目标：固定 960 格、9 页、全免负重，保留原生搜索/筛选/锁格/整理，不增加其他玩法功能。
- 游戏日志确认版本 `V 3.4.0 (b10)`；Steam 客户端构建号 `26309840`。
- 原始工作区备份：`.work/original-mod.zip`。
- 原版配置和游戏程序集仅在本机读取，未包含在发布包中。

## 设计与静态依据

1. `EntityPlayer.CalcCurrentBackpackSize` 将最终 `BagSize` 限制到 `Entity.MaxBagSize`，因此同时把基础容量和上限设为 960。
2. `playerFemale` 继承 `playerMale`；两种角色共用这组配置。基础 `CarryCapacity` 从 CVar 引用改为常量 960，不受入场时的沙盒倍率影响。
3. 三种原生装备背包的 `BagSize base_add` 与其显示增量设为 0。技能/装备的额外免负重格数可以保持原版，不影响已全免负重的 960 格。
4. god、类固醇和两个 Twitch 效果会用 `base_set` 覆盖负重容量，因此同步改为 960。其他消耗品/技能的加法效果不需要修改。
5. `XUiC_ItemStackGrid.Init` 递归收集子节点里的 `ItemStack` 控制器；`XUiC_Backpack.SetStacks` 按数组顺序赋予全局槽位编号。保留单一 `Backpack` 控制器包住九页，不能给每页各放一个 `Backpack` 控制器。
6. `XUiC_BackpackWindow.Init` 把原生操作栏的筛选、整理、锁格回调绑定到这个背包控制器；操作栏完整保留，分页只改变显示结构。
7. `XUiC_ItemStackGrid.updateSearch` 遍历全部物品控制器并设置 `MatchesSearch`；继续使用原版 `item_stack` 模板的搜索可见性绑定。搜索不移动槽位，也不自动切换页签。
8. `XUiC_BackpackWindow.ApplyLockedSlotStates/UpdateLockedSlots` 使用整个控制器数组和 `PackedBoolArray`。没有对页码单独维护锁格状态，避免页间状态映射错误。
9. 原生 `TabSelectorButton` 支持 `SimpleButton`，并由 `UpdateSelectionState` 更新按钮选中外观。
10. `XUiC_BagContainer.SetBag` 会按掉落容器尺寸更新网格行列，但操作的是 UI 初始化时创建的物品控制器数组。因此同时把 `playerBackpack` 容量和 `windowBagStorage` 的预建格数提高到 984，保留原生滚动条。
11. `ItemStackGrid.Write` 使用 16 位有符号计数写入物品数组长度；960/984 未超过该字段范围。这只是序列化路径的静态依据，不等同于已验证存档/网络完整流程。

## 改动范围

- 运行时仅保留 `entityclasses.xml`、`buffs.xml`、`items.xml`、`loot.xml`、`XUi_InGame/windows.xml` 五个补丁文件。
- 移除旧 `XUi` 目录补丁及无关的制作队列、物品详情、技能与全局缩放改动。
- 不修改原版 `actions`、原版 `item_stack` 模板、普通搜刮窗口或其他容器容量。
- 检查到本机“超越存储3”向原生 `actions` 添加按钮；本补丁不替换该区域，保留其 XML 挂接位置，但尚未验证该模组 DLL 与 960 格背包的运行时兼容性。

## 验证边界

`tools/Validate-Mod.ps1` 按顺序在内存中应用本模组使用的 `set/remove/append` 操作，遇到零命中 XPath 立即失败，并检查容量、继承、效果覆盖、九页槽数、布局边界、原生操作栏完整性及死亡掉落容量。

检查结果保存在 `.work/static-validation.json`，其中记录本机原版配置/程序集哈希、每条 XPath 命中数量及所有断言。验证器不会执行游戏代码，不证明像素布局、交互、性能或多人同步已经通过实测。

独立静态复核未发现阻断项，并核实 `GetChildrenByType` 的递归顺序、全背包整理路径及锁格数组的可变长度编码。末页第 954/955 格交界和第 960 格的实际初始化与拖放仍列为手动验收重点。
