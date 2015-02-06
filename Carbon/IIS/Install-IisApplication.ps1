# Copyright 2012 Aaron Jensen
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

function Install-IisApplication
{
    <#
    .SYNOPSIS
    Creates a new application under a website.
    
    .DESCRIPTION
    Creates a new application at `VirtualPath` under website `SiteName` running the code found on the file system under `PhysicalPath`, i.e. if SiteName is is `example.com`, the application is accessible at `example.com/VirtualPath`.  If an application already exists at that path, it is removed first.  The application can run under a custom application pool using the optional `AppPoolName` parameter.  If no app pool is specified, the application runs under the same app pool as the website it runs under.

    Beginning with Carbon 2.0, returns a `Microsoft.Web.Administration.Application` object for the new application if one is created or modified.

    Beginning with Carbon 2.0, if no app pool name is given, existing application's are updated to use `DefaultAppPool`.
    
    .EXAMPLE
    Install-IisApplication -SiteName Peanuts -VirtualPath CharlieBrown -PhysicalPath C:\Path\To\CharlieBrown -AppPoolName CharlieBrownPool
    
    Creates an application at `Peanuts/CharlieBrown` which runs from `Path/To/CharlieBrown`.  The application runs under the `CharlieBrownPool`.
    
    .EXAMPLE
    Install-IisApplication -SiteName Peanuts -VirtualPath Snoopy -PhysicalPath C:\Path\To\Snoopy
    
    Create an application at Peanuts/Snoopy, which runs from C:\Path\To\Snoopy.  It uses the same application as the Peanuts website.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Web.Administration.Application])]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The site where the application should be created.
        $SiteName,
        
        [Parameter(Mandatory=$true)]
        [Alias('Name')]
        [string]
        # The name of the application.
        $VirtualPath,
        
        [Parameter(Mandatory=$true)]
        [Alias('Path')]
        [string]
        # The path to the application.
        $PhysicalPath,
        
        [string]
        # The app pool for the application. Default is `DefaultAppPool`.
        $AppPoolName = 'DefaultAppPool'
    )
    
    Set-StrictMode -Version 'Latest'

    $site = Get-IisWebsite -SiteName $SiteName
    if( -not $site )
    {
        Write-Error ('[IIS] Website ''{0}'' not found.' -f $SiteName)
        return
    }

    $iisAppPath = Join-IisVirtualPath $SiteName $VirtualPath

    $PhysicalPath = Resolve-FullPath -Path $PhysicalPath
    if( -not (Test-Path $PhysicalPath -PathType Container) )
    {
        Write-Verbose ('IIS://{0}: creating physical path {1}' -f $iisAppPath,$PhysicalPath)
        $null = New-Item $PhysicalPath -ItemType Directory
    }

    $appPoolDesc = ''
    if( $AppPoolName )
    {
        $appPoolDesc = '; appPool: {0}' -f $AppPoolName
    }
    
    $apps = $site.GetCollection()

    $appPath = "/{0}" -f $VirtualPath
    $app = Get-IisApplication -SiteName $SiteName -VirtualPath $VirtualPath
    $modified = $false
    if( -not $app )
    {
        Write-Verbose ('IIS://{0}: creating application' -f $iisAppPath)
        $app = $apps.CreateElement('application') |
                    Add-IisServerManagerMember -ServerManager $site.ServerManager -PassThru
        $app['path'] = $appPath
        $apps.Add( $app ) | Out-Null
        $modified = $true
    }

    if( $app['path'] -ne $appPath )
    {
        $app['path'] = $appPath
        $modified = $true
    }
        
    if( $AppPoolName -and $app['applicationPool'] -ne $AppPoolName)
    {
        $app['applicationPool'] = $AppPoolName
        $modified = $true
    }

    $vdir = $null
    if( $app | Get-Member 'VirtualDirectories' )
    {
        $vdir = $app.VirtualDirectories |
                    Where-Object { $_.Path -eq '/' }
    }

    if( -not $vdir )
    {
        Write-Verbose ('IIS://{0}: creating virtual directory' -f $iisAppPath)
        $vdirs = $app.GetCollection()
        $vdir = $vdirs.CreateElement('virtualDirectory')
        $vdir['path'] = '/'
        $vdirs.Add( $vdir ) | Out-Null
        $modified = $true
    }

    if( $vdir['physicalPath'] -ne $PhysicalPath )
    {
        Write-Verbose ('IIS://{0}: setting physical path {1}' -f $iisAppPath,$PhysicalPath)
        $vdir['physicalPath'] = $PhysicalPath
        $modified = $true
    }

    if( $modified )
    {
        Write-Verbose ('IIS://{0}: committing changes' -f $iisAppPath)
        $app.CommitChanges()

        return Get-IisApplication -SiteName $SiteName -VirtualPath $VirtualPath
    }

}
