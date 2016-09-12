﻿[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $PublisherID,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $ExtensionID,

    [Parameter(Mandatory=$false)]
    [string] $ExtensionTag,

    [Parameter(Mandatory=$false)]
    [ValidateSet("true", "false", "1", "0")]
    [string] $OverrideExtensionVersion,

    [Parameter(Mandatory=$false)]
    [string] $ExtensionVersion,

    [Parameter(Mandatory=$false)]
    [ValidateSet("true", "false", "1", "0")]
    [string] $OverrideInternalVersions = $true,

    [Parameter(Mandatory=$false)]
    [ValidateSet("NoOverride", "Private", "PrivatePreview", "PublicPreview", "Public")]
    [string] $ExtensionVisibility = "NoOverride",

    [Parameter(Mandatory=$false)]
    [ValidateSet("NoOverride", "Free", "Paid")]
    [string] $PricingModel = "NoOverride",

    # Global Options
    [Parameter(Mandatory=$false)]
    [string] $ServiceEndpoint,

    [Parameter(Mandatory=$false)]
    [ValidateSet("true", "false", "1", "0")]
    [string] $TfxInstall = $false,

    [Parameter(Mandatory=$false)]
    [ValidateSet("true", "false", "1", "0")]
    [string] $TfxUpdate = $false,

    [Parameter(Mandatory=$false)]
    [string] $TfxLocation = $false,

    [Parameter(Mandatory=$false)]
    [string] $ManifestGlobs = "vss-extension.json",

    [Parameter(Mandatory=$true)]
    [string] $ExtensionRoot,

    [Parameter(Mandatory=$true)]
    [string] $PackagingOutputPath,

    # Advanced Options
    [Parameter(Mandatory=$false)]
    [ValidateSet("None", "File", "Json")]
    [string] $OverrideType = "None",

    [Parameter(Mandatory=$false)]
    [string] $OverrideFile = "",

    [Parameter(Mandatory=$false)]
    [string] $OverrideJson = "{}",

    [Parameter(Mandatory=$false)]
    [string] $BypassValidation = $false,

    [Parameter(Mandatory=$false)]
    [string] $EnablePublishing = $false,

    # Sharing options
    [Parameter(Mandatory=$false)]
    [string] $EnableSharing = $false,

    [Parameter(Mandatory=$false)]
    [string] $ShareWith = $false,

    #Preview mode for remote call
    [Parameter(Mandatory=$false)]
    [string] $Preview = $false,

    [Parameter(Mandatory=$false)]
    [string] $OutputVariable = "",

    [Parameter(Mandatory=$false)]
    [string] $LocalizationRoot,

    [Parameter(Mandatory=$false)]
    [string] $TfxArguments

)

$PreviewMode = ($Preview -eq $true)

Write-Verbose "Entering script $($MyInvocation.MyCommand.Name)"
Write-Verbose "Parameter Values"
$PSBoundParameters.Keys | %{ Write-Verbose "$_ = $($PSBoundParameters[$_])" }

Write-Verbose "Importing modules"
Import-Module -DisableNameChecking "$PSScriptRoot/vsts-extension-shared.psm1"

$global:globalOptions = Convert-GlobalOptions $PSBoundParameters
$global:packageOptions = Convert-PackageOptions $PSBoundParameters

Find-Tfx -TfxInstall:$globalOptions.TfxInstall -TfxLocation $globalOptions.TfxLocation -Detect -TfxUpdate:$globalOptions.TfxUpdate

$command = "create"
if ($packageOptions.PublishEnabled)
{
    $command = "publish"
    $MarketEndpoint = Get-ServiceEndpoint -Context $distributedTaskContext -Name $globalOptions.ServiceEndpoint
    if ($MarketEndpoint -eq $null)
    {
        throw "Could not locate service endpoint $globalOptions.ServiceEndpoint"
    }
}

if ($packageOptions.OverrideExtensionVersion -and $packageOptions.OverrideInternalVersions)
{
    Update-InternalVersion
}

$tfxArgs = @(
    "extension",
    $command,
    "--root",
    $packageOptions.ExtensionRoot,
    "--output-path",
    $packageOptions.OutputPath,
    "--extensionid",
    $packageOptions.ExtensionId,
    "--publisher",
    $packageOptions.PublisherId,
    "--override",
    ($packageOptions.OverrideJson | ConvertTo-Json -Depth 100 -Compress)
)

if ($packageOptions.PublishEnabled -and $packageOptions.ShareEnabled -and ($packageOptions.ShareWith.Length -gt 0))
{
    $tfxArgs += "--share-with"

    Write-Debug "Sharing with:"
    foreach ($account in $packageOptions.ShareWith)
    {
        Write-Debug "$account"
        $tfxArgs += $account
    }
}

if ($packageOptions.ManifestGlobs -ne "")
{
    $tfxArgs += "--manifest-globs"
    $tfxArgs += $packageOptions.ManifestGlobs
}

if ($packageOptions.LocalizationRoot -ne "")
{
    $tfxArgs += "--loc-root"
    $tfxArgs += $packageOptions.LocalizationRoot
}

if ($packageOptions.BypassValidation)
{
    $tfxArgs += "--bypass-validation"
}

if (-not $packageOptions.PublishEnabled)
{
    $output = Invoke-Tfx -Arguments $tfxArgs
}
else
{
    $output = Invoke-Tfx -Arguments $tfxArgs -ServiceEndpoint $MarketEndpoint -Preview:$PreviewMode
}

if ($packageOptions.OutputVariable -ne "")
{
    switch($command)
    {
        "create"
        {
            Write-Debug "Setting output variable '$($packageOptions.OutputVariable)' using: path"
            $location = $output.path
        }
        "publish"
        {
            Write-Debug "Setting output variable '$($packageOptions.OutputVariable)' using: packaged"
            $location = $output.packaged
        }
    }

    Write-Output "Setting output variable '$($packageOptions.OutputVariable)' to '$location'"
    Write-Host "##vso[task.setvariable variable=$($packageOptions.OutputVariable);]$location"
}

if ("$output" -ne "")
{
    Write-Host "##vso[task.complete result=Succeeded;]"
    Write-Output "Done."
}
else
{
    Write-Host "##vso[task.complete result=Failed;]"
    throw ("Failed.")
}