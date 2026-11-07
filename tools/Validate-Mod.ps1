param(
    [Parameter(Mandatory)][string]$GamePath,
    [string]$ModPath = (Split-Path $PSScriptRoot -Parent),
    [string]$ReportPath
)

# Static validation only: XML/XPath processing in memory. Never starts or modifies the game.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$basePath = Join-Path $GamePath 'Data/Config'
$modConfig = Join-Path $ModPath 'Config'
$effective = @{}
$original = @{}
$matches = [Collections.Generic.List[object]]::new()
$checks = [Collections.Generic.List[string]]::new()

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $checks.Add($Message)
}

function Read-Xml([string]$Path) {
    $doc = [Xml.XmlDocument]::new()
    $doc.XmlResolver = $null
    $doc.Load($Path)
    return ,$doc
}

$null = Read-Xml (Join-Path $ModPath 'ModInfo.xml')
foreach ($file in Get-ChildItem -LiteralPath $modConfig -Filter '*.xml' -Recurse -File) {
    $relative = [IO.Path]::GetRelativePath($modConfig, $file.FullName).Replace('\', '/')
    $baseFile = Join-Path $basePath $relative
    Assert-Condition (Test-Path -LiteralPath $baseFile) ('Vanilla file exists: ' + $relative)
    $doc = Read-Xml $baseFile
    $original[$relative] = $doc.CloneNode($true)
    $patch = Read-Xml $file.FullName
    foreach ($op in $patch.DocumentElement.ChildNodes) {
        if ($op.NodeType -ne [Xml.XmlNodeType]::Element) { continue }
        $xpath = $op.GetAttribute('xpath')
        $null = [Xml.XPath.XPathExpression]::Compile($xpath)
        $targets = @($doc.SelectNodes($xpath))
        if ($targets.Count -eq 0) { throw "Unmatched XPath in ${relative}: $xpath" }
        $matches.Add([pscustomobject]@{ File=$relative; Operation=$op.LocalName; XPath=$xpath; Matches=$targets.Count })
        switch ($op.LocalName) {
            'set' {
                foreach ($target in $targets) { $target.InnerText = $op.InnerText }
            }
            'setattribute' {
                foreach ($target in $targets) { $target.SetAttribute($op.GetAttribute('name'), $op.InnerText) }
            }
            'remove' {
                foreach ($target in $targets) { $null = $target.ParentNode.RemoveChild($target) }
            }
            'append' {
                foreach ($target in $targets) {
                    foreach ($child in $op.ChildNodes) { $null = $target.AppendChild($doc.ImportNode($child,$true)) }
                }
            }
            default { throw "Unsupported static patch operation: $($op.Name)" }
        }
    }
    $effective[$relative] = $doc
}

$entities = $effective['entityclasses.xml']
$player = $entities.SelectSingleNode('/entity_classes/entity_class[@name="playerMale"]')
foreach ($xpath in @('property[@name="MaxBagSize"]/@value', 'effect_group/passive_effect[@name="BagSize"]/@value', 'effect_group/passive_effect[@name="CarryCapacity"]/@value')) {
    Assert-Condition ($player.SelectSingleNode($xpath).Value -eq '960') ('Player capacity = 960: ' + $xpath)
}
Assert-Condition ($entities.SelectSingleNode('/entity_classes/entity_class[@name="playerFemale"]').GetAttribute('extends') -eq 'playerMale') 'Female player inherits the same capacity'

$items = $effective['items.xml']
$bagBonuses = $items.SelectNodes('/items/item/effect_group/passive_effect[@name="BagSize"]')
Assert-Condition ($bagBonuses.Count -eq 3) 'Vanilla has exactly three backpack size effects'
foreach ($bonus in $bagBonuses) { Assert-Condition ($bonus.GetAttribute('value') -eq '0') 'Equippable backpack cannot change the fixed capacity' }
$overrides = $effective['buffs.xml'].SelectNodes('/buffs/buff/effect_group/passive_effect[@name="CarryCapacity"][@operation="base_set"]')
Assert-Condition ($overrides.Count -eq 4) 'All four vanilla capacity-replacement buffs are covered'
foreach ($effect in $overrides) { Assert-Condition ($effect.GetAttribute('value') -eq '960') 'Capacity-replacement buff preserves no encumbrance' }

$windows = $effective['XUi_InGame/windows.xml']
$backpack = $windows.SelectSingleNode('/windows/window[@name="windowBackpack"]')
$nativeBackpack = $original['XUi_InGame/windows.xml'].SelectSingleNode('/windows/window[@name="windowBackpack"]')
Assert-Condition ($backpack.GetAttribute('controller') -eq 'BackpackWindow') 'Native BackpackWindow controller retained'
Assert-Condition ($backpack.SelectSingleNode('rect[@name="actions"]').OuterXml -ceq $nativeBackpack.SelectSingleNode('rect[@name="actions"]').OuterXml) 'Native search/filter/lock/sort actions are byte-for-byte unchanged after XML normalization'
Assert-Condition ($backpack.SelectNodes('.//*[@controller="Backpack"]').Count -eq 1) 'Exactly one shared Backpack controller'
$content = $backpack.SelectSingleNode('rect[@name="content"][@controller="Backpack"]')
Assert-Condition ($null -ne $content) 'Native bp.content navigation target retained'
Assert-Condition ($content.GetAttribute('width') -eq '870') 'Backpack interaction area spans the full window'
$tabs = @($content.SelectNodes('.//*[@controller="TabSelectorTab"]'))
Assert-Condition ($tabs.Count -eq 9) 'Exactly nine inventory pages'
$buttonGrid = $content.SelectSingleNode('.//grid[@name="flPageButtons"]')
Assert-Condition (([int]$buttonGrid.GetAttribute('rows') * [int]$buttonGrid.GetAttribute('cols')) -eq 9) 'Exactly nine page buttons'
$slotCount = 0
$ranges = [Collections.Generic.List[object]]::new()
for ($i = 0; $i -lt $tabs.Count; $i++) {
    $tab = $tabs[$i]
    Assert-Condition ($tab.GetAttribute('tab_key') -eq [string]($i+1)) ('Unique ordered page key: ' + ($i+1))
    $pageSlots = 0
    foreach ($grid in $tab.SelectNodes('.//grid')) {
        Assert-Condition ($grid.GetAttribute('repeat_content') -eq 'true') 'Grid repeats the native item template'
        Assert-Condition ([int]$grid.GetAttribute('depth') -gt [int]$content.GetAttribute('depth')) 'Inventory grid is above the clickable background'
        Assert-Condition ($grid.SelectNodes('item_stack').Count -eq 1) 'One native item_stack template per grid'
        $position = $grid.GetAttribute('pos').Split(',')
        $right = [int]$position[0] + [int]$grid.GetAttribute('cols') * [int]$grid.GetAttribute('cell_width')
        $bottom = -[int]$position[1] + [int]$grid.GetAttribute('rows') * [int]$grid.GetAttribute('cell_height')
        Assert-Condition ($right -le [int]$tab.GetAttribute('width') -and $bottom -le [int]$tab.GetAttribute('height')) 'Every page grid fits its declared bounds'
        $pageSlots += [int]$grid.GetAttribute('rows') * [int]$grid.GetAttribute('cols')
    }
    $expected = if ($i -lt 8) { 108 } else { 96 }
    Assert-Condition ($pageSlots -eq $expected) ('Page ' + ($i+1) + ' capacity = ' + $expected)
    $ranges.Add([pscustomobject]@{ Page=$i+1; FirstSlot=$slotCount+1; LastSlot=$slotCount+$pageSlots; Count=$pageSlots })
    $slotCount += $pageSlots
}
Assert-Condition ($slotCount -eq 960) 'Exactly 960 UI slots, no duplicate extra capacity'
Assert-Condition ($backpack.SelectNodes('.//item_stack').Count -eq $content.SelectNodes('.//item_stack').Count) 'Every backpack item slot belongs to the shared controller'

$deathBag = $effective['loot.xml'].SelectSingleNode('/lootcontainers/lootcontainer[@name="playerBackpack"]')
$dimensions = $deathBag.GetAttribute('size').Split(',')
$deathSlots = [int]$dimensions[0] * [int]$dimensions[1]
Assert-Condition ($deathSlots -eq 984) 'Death bag has 984 slots (960 + 24)'
$deathGrid = $windows.SelectSingleNode('/windows/window[@name="windowBagStorage"]/rect[@name="content"]/scrollview/grid[@name="queue"]')
Assert-Condition (([int]$deathGrid.GetAttribute('rows') * [int]$deathGrid.GetAttribute('cols')) -ge $deathSlots) 'Death-bag UI allocates all 984 slots'
Assert-Condition ($null -ne $deathGrid.SelectSingleNode('../preceding-sibling::defaultscrollbar')) 'Native death-bag scrollbar retained'
foreach ($window in $original['XUi_InGame/windows.xml'].SelectNodes('/windows/window[not(@name="windowBackpack" or @name="windowBagStorage")]')) {
    $name = $window.GetAttribute('name')
    $current = $windows.SelectSingleNode('/windows/window[@name="' + $name + '"]')
    if ($current.OuterXml -cne $window.OuterXml) { throw "Unexpected change to vanilla window: $name" }
}
$checks.Add('All unrelated vanilla windows unchanged')
foreach ($obsolete in @('XUi/windows.xml','XUi/controls.xml','XUi/xui.xml','XUi_Common/styles.xml','XUi_InGame/templates.xml','XUi_InGame/xui.xml','progression.xml')) {
    Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $modConfig $obsolete))) ('Legacy/unrelated patch removed: ' + $obsolete)
}

$report = [ordered]@{
    Validation = 'Static XML/XPath and structural checks only; not an in-game test'
    GamePath = $GamePath
    AssemblySha256 = (Get-FileHash -LiteralPath (Join-Path $GamePath '7DaysToDie_Data/Managed/Assembly-CSharp.dll') -Algorithm SHA256).Hash
    VanillaWindowsSha256 = (Get-FileHash -LiteralPath (Join-Path $basePath 'XUi_InGame/windows.xml') -Algorithm SHA256).Hash
    PatchOperations = $matches.Count
    Assertions = $checks.Count
    InventorySlots = $slotCount
    DeathBagSlots = $deathSlots
    Pages = @($ranges)
    Checks = @($checks)
    XPathMatches = @($matches)
}
if ($ReportPath) {
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding utf8
}
Write-Output ('PASS: {0} patch operations; {1} assertions; 960 slots / 9 pages; death bag 984.' -f $matches.Count,$checks.Count)
$ranges | Format-Table -AutoSize
