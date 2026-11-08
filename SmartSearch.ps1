# ==============================================================================
#  SmartSearch v5.1.0 - Native Windows Desktop App (PowerShell + WPF)
#  Search, deduplicate and purge local storage - fully offline, no HTML.
#  Simplified settings · No auto-open · Hardened
# ==============================================================================
$Version = '5.1.0'
$ErrorActionPreference = 'Continue'
$PSScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$AppDir = $PSScriptRoot
$SettingsPath = Join-Path $AppDir 'SmartSearchSettings.json'
$PresetDir = Join-Path $env:LOCALAPPDATA 'SmartSearch'
if (-not (Test-Path $PresetDir)) { New-Item -ItemType Directory -Path $PresetDir -Force | Out-Null }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Windows.Forms

# ---------------------------------------------------------------------------
#  XAML UI
# ---------------------------------------------------------------------------
$XamlText = @'
<Window
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SmartSearch"
        Width="920" Height="760"
        Foreground="#E7F5EB"
        WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI"
        TextOptions.TextFormattingMode="Display"
        UseLayoutRounding="True">
    <Window.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#0B0F0D" Offset="0"/>
            <GradientStop Color="#050806" Offset="1"/>
        </LinearGradientBrush>
    </Window.Background>
    <Window.Resources>
        <LinearGradientBrush x:Key="BtnGrad" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#16A34A" Offset="0"/>
            <GradientStop Color="#22C55E" Offset="1"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="BtnGradHover" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#22C55E" Offset="0"/>
            <GradientStop Color="#15803D" Offset="1"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="Accent" StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#16A34A" Offset="0"/>
            <GradientStop Color="#34D399" Offset="0.55"/>
            <GradientStop Color="#22C55E" Offset="1"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="IconTile" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#4ADE80" Offset="0"/>
            <GradientStop Color="#22C55E" Offset="1"/>
        </LinearGradientBrush>
        <DropShadowEffect x:Key="CardShadow" BlurRadius="24" ShadowDepth="5" Direction="270" Opacity="0.16" Color="#000000"/>
        <DropShadowEffect x:Key="SoftShadow" BlurRadius="14" ShadowDepth="2" Direction="270" Opacity="0.12" Color="#000000"/>
        <DropShadowEffect x:Key="BtnShadow" BlurRadius="14" ShadowDepth="4" Direction="270" Opacity="0.35" Color="#15803D"/>
        <DropShadowEffect x:Key="Glow" BlurRadius="7" ShadowDepth="0" Opacity="0.30" Color="#22C55E"/>
        <Style x:Key="InputBox" TargetType="TextBox">
            <Setter Property="Height" Value="34"/>
            <Setter Property="Padding" Value="10,5"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Foreground" Value="#E7F5EB"/>
            <Setter Property="CaretBrush" Value="#22C55E"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="bd" Background="#101614" BorderBrush="#22302A"
                                BorderThickness="1" CornerRadius="8">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="2,0"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="bd" Property="BorderBrush" Value="#16A34A"/>
                                <Setter TargetName="bd" Property="Effect" Value="{StaticResource Glow}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="bd" Property="Background" Value="#0A0E0D"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="Combo" TargetType="ComboBox">
            <Setter Property="Height" Value="34"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Foreground" Value="#E7F5EB"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="ScrollViewer.CanContentScroll" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton x:Name="toggle" Focusable="False" ClickMode="Press"
                                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                                          Background="Transparent" BorderThickness="0">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Border x:Name="bd" Background="#101614" BorderBrush="#22302A" BorderThickness="1" CornerRadius="8">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="26"/>
                                                </Grid.ColumnDefinitions>
                                                <ContentPresenter Margin="10,0,0,0" VerticalAlignment="Center" HorizontalAlignment="Left"
                                                                  IsHitTestVisible="False"
                                                                  Content="{Binding SelectionBoxItem, RelativeSource={RelativeSource TemplatedParent}}"
                                                                  ContentTemplate="{Binding SelectionBoxItemTemplate, RelativeSource={RelativeSource TemplatedParent}}"/>
                                                <Path Grid.Column="1" Data="M0,0 L4.5,4.5 L9,0" Stroke="#4A674F" StrokeThickness="1.8"
                                                      StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"
                                                      VerticalAlignment="Center" HorizontalAlignment="Center"/>
                                            </Grid>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter TargetName="bd" Property="BorderBrush" Value="#6F8B7C"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                            </ToggleButton>
                            <Popup x:Name="PART_Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}"
                                   AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
                                <Border x:Name="drop" Background="#101614" BorderBrush="#22302A" BorderThickness="1" CornerRadius="10"
                                        Margin="0,5,0,0" Padding="4" Effect="{StaticResource SoftShadow}"
                                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"
                                        MaxHeight="{TemplateBinding MaxDropDownHeight}">
                                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                                        <ItemsPresenter/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ComboEdit" TargetType="ComboBox">
            <Setter Property="Height" Value="34"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Foreground" Value="#E7F5EB"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton x:Name="toggle" Focusable="False" ClickMode="Press"
                                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                                          Background="Transparent" BorderThickness="0">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Border x:Name="bd" Background="#101614" BorderBrush="#22302A" BorderThickness="1" CornerRadius="8">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="26"/>
                                                </Grid.ColumnDefinitions>
                                                <TextBox x:Name="PART_EditableTextBox" Margin="3,0,0,0" VerticalAlignment="Center"
                                                         Background="Transparent" BorderThickness="0" Padding="7,0"
                                                         Foreground="#E7F5EB" FontSize="13" Focusable="True" CaretBrush="#22C55E"/>
                                                <Path Grid.Column="1" Data="M0,0 L4.5,4.5 L9,0" Stroke="#4A674F" StrokeThickness="1.8"
                                                      StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"
                                                      VerticalAlignment="Center" HorizontalAlignment="Center"/>
                                            </Grid>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter TargetName="bd" Property="BorderBrush" Value="#6F8B7C"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                            </ToggleButton>
                            <Popup x:Name="PART_Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}"
                                   AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
                                <Border x:Name="drop" Background="#101614" BorderBrush="#22302A" BorderThickness="1" CornerRadius="10"
                                        Margin="0,5,0,0" Padding="4" Effect="{StaticResource SoftShadow}"
                                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"
                                        MaxHeight="{TemplateBinding MaxDropDownHeight}">
                                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                                        <ItemsPresenter/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ComboBoxItem">
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="Foreground" Value="#E7F5EB"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="bd" Background="Transparent" CornerRadius="5" Padding="10,6">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#12311F"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#134B27"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="BtnPrimary" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource BtnGrad}"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="13"/>
           
