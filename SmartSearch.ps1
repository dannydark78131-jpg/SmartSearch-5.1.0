# ============================================================================
# SmartSearch v5.1.1 - Native Windows desktop app (PowerShell + WPF)
# Offline file search and safe duplicate detection/removal.
# ============================================================================
$Version = '5.1.1'
$ErrorActionPreference = 'Stop'

if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$AppDir = $PSScriptRoot
$SettingsPath = Join-Path $AppDir 'SmartSearchSettings.json'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms

function Get-DefaultSettings {
    [pscustomobject]@{
        SearchRoot        = [Environment]::GetFolderPath('UserProfile')
        SearchText        = ''
        IncludeSubfolders = $true
        Exclusions        = @('AppData', 'node_modules', '.git', '$RECYCLE.BIN', 'Temporary Internet Files')
    }
}

function Get-AppSettings {
    $settings = Get-DefaultSettings
    if (Test-Path -LiteralPath $SettingsPath -PathType Leaf) {
        try {
            $saved = Get-Content -LiteralPath $SettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            foreach ($name in @('SearchRoot', 'SearchText', 'IncludeSubfolders', 'Exclusions')) {
                if ($null -ne $saved.PSObject.Properties[$name]) {
                    $settings.$name = $saved.$name
                }
            }
        }
        catch {
            # Keep defaults if the settings file is missing fields or invalid JSON.
        }
    }
    return $settings
}

function Save-AppSettings {
    param([Parameter(Mandatory)]$Settings)
    $Settings | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
}

function Test-ExcludedPath {
    param([string]$Path, [string[]]$Exclusions = @())
    if (-not $Exclusions) { return $false }
    foreach ($segment in ($Path -split '[\\/]')) {
        foreach ($excluded in $Exclusions) {
            if (-not [string]::IsNullOrWhiteSpace($excluded) -and
                [string]::Equals($segment, $excluded, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    }
    return $false
}

function Find-LocalFiles {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$SearchText = '',
        [bool]$IncludeSubfolders = $true,
        [string[]]$Exclusions = @(),
        [ValidateRange(1, 100000)][int]$MaxResults = 5000
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "The selected folder does not exist: $Root"
    }
    $options = @{ LiteralPath = $Root; File = $true; ErrorAction = 'SilentlyContinue' }
    if ($IncludeSubfolders) { $options.Recurse = $true }
    $query = $SearchText.Trim()
    $found = [System.Collections.Generic.List[object]]::new()

    foreach ($file in (Get-ChildItem @options)) {
        if (Test-ExcludedPath -Path $file.FullName -Exclusions $Exclusions) { continue }
        if ($query -and $file.Name.IndexOf($query, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $found.Add([pscustomobject]@{
            Name = $file.Name
            FullName = $file.FullName
            Length = [long]$file.Length
            Display = ('{0}  |  {1}  |  {2:N1} KB' -f $file.Name, $file.FullName, ($file.Length / 1KB))
        })
        if ($found.Count -ge $MaxResults) { break }
    }
    return ,$found.ToArray()
}

function Get-ConfirmedDuplicateFiles {
    param([Parameter(Mandatory)][object[]]$Files)
    # File size alone cannot establish that two files are duplicates; compare SHA-256.
    $seen = @{}
    $duplicates = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $Files) {
        try {
            if (-not (Test-Path -LiteralPath $file.FullName -PathType Leaf)) { continue }
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($seen.ContainsKey($hash)) { $duplicates.Add($file) }
            else { $seen[$hash] = $file.FullName }
        }
        catch {
            # Skip files that became inaccessible during the scan.
        }
    }
    return ,$duplicates.ToArray()
}

function Start-SmartSearch {
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SmartSearch" Width="980" Height="720" MinWidth="720" MinHeight="520"
        WindowStartupLocation="CenterScreen" Background="#080D0A" Foreground="#E7F5EB"
        FontFamily="Segoe UI" UseLayoutRounding="True">
    <Window.Resources>
        <SolidColorBrush x:Key="Panel" Color="#111A15"/>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#0D1510"/><Setter Property="Foreground" Value="#E7F5EB"/>
            <Setter Property="CaretBrush" Value="#22C55E"/><Setter Property="BorderBrush" Value="#2A3A30"/>
            <Setter Property="Padding" Value="9,7"/><Setter Property="FontSize" Value="13"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#1A2A20"/><Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="13,8"/><Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/><Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
        <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#D4E5D9"/></Style>
    </Window.Resources>
    <Grid Margin="18">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <Border Grid.Row="0" Background="{StaticResource Panel}" CornerRadius="12" Padding="18,13" Margin="0,0,0,12">
            <StackPanel><TextBlock Text="SmartSearch" FontSize="27" FontWeight="Bold"/>
                <TextBlock Text="Search local files and safely remove byte-identical duplicates" Foreground="#91A79A" Margin="0,3,0,0"/></StackPanel>
        </Border>
        <Border Grid.Row="1" Background="{StaticResource Panel}" CornerRadius="12" Padding="14" Margin="0,0,0,12">
            <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="2*"/><ColumnDefinition Width="3*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                <TextBlock Grid.Row="0" Grid.Column="0" Text="Name contains" Foreground="#91A79A" Margin="0,0,8,4"/>
                <TextBlock Grid.Row="0" Grid.Column="1" Text="Folder to search" Foreground="#91A79A" Margin="0,0,8,4"/>
                <TextBox x:Name="txtSearch" Grid.Row="1" Grid.Column="0" Margin="0,0,10,0"/>
                <TextBox x:Name="txtRoot" Grid.Row="1" Grid.Column="1" Margin="0,0,8,0"/>
                <Button x:Name="btnBrowse" Grid.Row="1" Grid.Column="2" Content="Browse…" Margin="0,0,8,0"/>
                <Button x:Name="btnSearch" Grid.Row="1" Grid.Column="3" Content="Search" Background="#16813D" MinWidth="105"/>
                <CheckBox x:Name="chkSubfolders" Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="4" Content="Include subfolders" IsChecked="True" Margin="0,9,0,0"/>
            </Grid>
        </Border>
        <Border Grid.Row="2" Background="{StaticResource Panel}" CornerRadius="12" Padding="10">
            <ListBox x:Name="lstResults" Background="#0B110D" Foreground="#E7F5EB" BorderBrush="#26372C" BorderThickness="1" FontFamily="Consolas" FontSize="12" Padding="4"/>
        </Border>
        <Grid Grid.Row="3" Margin="0,12,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <TextBlock x:Name="lblStatus" Grid.Column="0" Text="Ready" Foreground="#91A79A" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
            <Button x:Name="btnClear" Grid.Column="1" Content="Clear results" Margin="8,0"/>
            <Button x:Name="btnPurge" Grid.Column="2" Content="Remove exact duplicates" Background="#8B332B"/>
        </Grid>
    </Grid>
</Window>
'@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    try { $window = [Windows.Markup.XamlReader]::Load($reader) }
    finally { $reader.Dispose() }

    $txtSearch = $window.FindName('txtSearch')
    $txtRoot = $window.FindName('txtRoot')
    $chkSubfolders = $window.FindName('chkSubfolders')
    $lstResults = $window.FindName('lstResults')
    $lblStatus = $window.FindName('lblStatus')
    $btnBrowse = $window.FindName('btnBrowse')
    $btnSearch = $window.FindName('btnSearch')
    $btnClear = $window.FindName('btnClear')
    $btnPurge = $window.FindName('btnPurge')

    $settings = Get-AppSettings
    $txtSearch.Text = [string]$settings.SearchText
    $txtRoot.Text = [string]$settings.SearchRoot
    $chkSubfolders.IsChecked = [bool]$settings.IncludeSubfolders
    $results = [System.Collections.Generic.List[object]]::new()

    $searchAction = {
        $root = $txtRoot.Text.Trim()
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            [System.Windows.MessageBox]::Show('Choose an existing folder to search.', 'SmartSearch', 'OK', 'Warning') | Out-Null
            return
        }
        $btnSearch.IsEnabled = $false
        $lblStatus.Text = 'Searching…'
        $lstResults.Items.Clear()
        $results.Clear()
        try {
            $items = Find-LocalFiles -Root $root -SearchText $txtSearch.Text `
                -IncludeSubfolders ([bool]$chkSubfolders.IsChecked) -Exclusions @($settings.Exclusions)
            foreach ($item in $items) {
                $results.Add($item)
                [void]$lstResults.Items.Add($item.Display)
            }
            $lblStatus.Text = "Found $($results.Count) file(s). Duplicate checks use SHA-256."
        }
        catch { $lblStatus.Text = "Search failed: $($_.Exception.Message)" }
        finally { $btnSearch.IsEnabled = $true }
    }.GetNewClosure()

    $btnBrowse.Add_Click({
        $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dialog.Description = 'Choose the folder SmartSearch should scan.'
        $dialog.ShowNewFolderButton = $false
        if (Test-Path -LiteralPath $txtRoot.Text -PathType Container) { $dialog.SelectedPath = $txtRoot.Text }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtRoot.Text = $dialog.SelectedPath }
    }.GetNewClosure())

    $btnSearch.Add_Click({ & $searchAction }.GetNewClosure())
    $txtSearch.Add_KeyDown({ param($sender, $eventArgs) if ($eventArgs.Key -eq [System.Windows.Input.Key]::Enter) { & $searchAction } }.GetNewClosure())
    $txtRoot.Add_KeyDown({ param($sender, $eventArgs) if ($eventArgs.Key -eq [System.Windows.Input.Key]::Enter) { & $searchAction } }.GetNewClosure())

    $btnClear.Add_Click({
        $results.Clear()
        $lstResults.Items.Clear()
        $lblStatus.Text = 'Results cleared.'
    }.GetNewClosure())

    $btnPurge.Add_Click({
        if ($results.Count -lt 2) { $lblStatus.Text = 'Search for at least two files first.'; return }
        $btnPurge.IsEnabled = $false
        $lblStatus.Text = 'Comparing file contents…'
        try {
            $duplicates = @(Get-ConfirmedDuplicateFiles -Files $results.ToArray())
            if ($duplicates.Count -eq 0) { $lblStatus.Text = 'No byte-identical duplicates found.'; return }
            $paths = ($duplicates | ForEach-Object { $_.FullName }) -join [Environment]::NewLine
            $answer = [System.Windows.MessageBox]::Show(
                "Found $($duplicates.Count) byte-identical duplicate file(s). The first copy of each file will be kept. Remove these copies?`n`n$paths",
                'Confirm duplicate removal', 'YesNo', 'Warning')
            if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { $lblStatus.Text = 'Removal cancelled.'; return }

            $removed = 0
            foreach ($duplicate in $duplicates) {
                try {
                    $hash = (Get-FileHash -LiteralPath $duplicate.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
                    $keeperExists = $false
                    foreach ($candidate in $results) {
                        if ($candidate.FullName -eq $duplicate.FullName) { continue }
                        try {
                            if ((Get-FileHash -LiteralPath $candidate.FullName -Algorithm SHA256 -ErrorAction Stop).Hash -eq $hash) {
                                $keeperExists = $true
                                break
                            }
                        }
                        catch { }
                    }
                    if ($keeperExists) {
                        Remove-Item -LiteralPath $duplicate.FullName -Force -ErrorAction Stop
                        $removed++
                    }
                }
                catch { }
            }
            $lblStatus.Text = "Removed $removed duplicate file(s). Search again to refresh results."
        }
        catch { $lblStatus.Text = "Duplicate check failed: $($_.Exception.Message)" }
        finally { $btnPurge.IsEnabled = $true }
    }.GetNewClosure())

    $window.Add_Closing({
        $settings.SearchRoot = $txtRoot.Text.Trim()
        $settings.SearchText = $txtSearch.Text
        $settings.IncludeSubfolders = [bool]$chkSubfolders.IsChecked
        try { Save-AppSettings -Settings $settings }
        catch { Write-Warning "Could not save SmartSearch settings: $($_.Exception.Message)" }
    }.GetNewClosure())

    [void]$window.ShowDialog()
}

try { Start-SmartSearch }
catch {
    $message = "SmartSearch could not start: $($_.Exception.Message)"
    [System.Windows.MessageBox]::Show($message, 'SmartSearch', 'OK', 'Error') | Out-Null
    Write-Error $message
    exit 1
}
