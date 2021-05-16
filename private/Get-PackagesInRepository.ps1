function Get-PackagesInRepository {
    <#

    #>
    [CmdletBinding()]
    Param (
        [Parameter( Mandatory = $true )]
        [string]$Repository,
        [Parameter( Mandatory = $true )]
        [string]$RepositoryType,
        [Parameter( Mandatory = $true )]
        [string]$Model
    )

    $UTF8ByteOrderMark = [System.Text.Encoding]::UTF8.GetString(@(195, 175, 194, 187, 194, 191))

    Write-Debug "Looking for packages in repository '${Repository}' (Type: ${RepositoryType})"

    if ($RepositoryType -eq 'HTTP') {
        $ModelXmlPath    = Join-Url -BaseUri $Repository -ChildUri "${Model}_Win10.xml"
        $DatabaseXmlPath = Join-Url -BaseUri $Repository -ChildUri "database.xml"
    } elseif ($RepositoryType -eq 'FILE') {
        $ModelXmlPath    = Join-Path -Path $Repository -ChildPath "${Model}_Win10.xml"
        $DatabaseXmlPath = Join-Path -Path $Repository -ChildPath "database.xml"
    }

    if ((Get-PackagePathInfo -Path $ModelXmlPath).Reachable) {
        Write-Debug "Getting packages from the model xml file ${ModelXmlPath}"
        if ($RepositoryType -eq 'HTTP') {
            # Model XML method for web based repositories
            $webClient = New-WebClient -Proxy $Proxy -ProxyCredential $ProxyCredential -ProxyUseDefaultCredentials $ProxyUseDefaultCredentials

            try {
                $COMPUTERXML = $webClient.DownloadString($ModelXmlPath)
            }
            catch {
                if ($_.Exception.innerException.Response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
                    throw "No information was found on this model of computer (invalid model number or not supported by Lenovo?)"
                } else {
                    throw "An error occured when contacting ${Repository}:`r`n$($_.Exception.Message)"
                }
            }

            # Downloading with Net.WebClient seems to remove the BOM automatically, this only seems to be neccessary when downloading with IWR. Still I'm leaving it in to be safe
            [xml]$PARSEDXML = $COMPUTERXML -replace "^$UTF8ByteOrderMark"
        } elseif ($RepositoryType -eq 'FILE') {
            # Model XML method for file based repositories
            $COMPUTERXML = Get-Content -LiteralPath $ModelXmlPath -Raw

            # Strings with a BOM cannot be cast to an XmlElement, so we make sure to remove it if present
            [xml]$PARSEDXML = $COMPUTERXML -replace "^$UTF8ByteOrderMark"
        }

        foreach ($Package in $PARSEDXML.packages.package) {
            $PathInfo = Get-PackagePathInfo -Path $Package.location -BasePath $Repository
            Write-Debug "Repo: $Repository, PkgLocation: $($Package.location), PkgInfo: $PathInfo"
            if ($PathInfo.Reachable) {
                [PackagePointer]@{
                    XMLFullPath  = $PathInfo.AbsoluteLocation
                    XMLFile      = $Package.location -replace '^.*[\\/]'
                    Directory    = $PathInfo.AbsoluteLocation -replace '[^\\/]*$'
                    Category     = $Package.category
                    LocationType = $PathInfo.Type
                }
            } else {
                Write-Error "The package definition at $($Package.location) could not be found or accessed"
            }
        }
    } elseif ((Get-PackagePathInfo -Path $DatabaseXmlPath).Reachable) {
        Write-Debug "Getting packages from the database xml file ${DatabaseXmlPath}"
        if ($RepositoryType -eq 'HTTP') {
            $webClient = New-WebClient -Proxy $Proxy -ProxyCredential $ProxyCredential -ProxyUseDefaultCredentials $ProxyUseDefaultCredentials

            try {
                $XmlString = $webClient.DownloadString($DatabaseXmlPath)
            }
            catch {
                if ($_.Exception.innerException.Response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
                    throw "No information was found on this model of computer (invalid model number or not supported by Lenovo?)"
                } else {
                    throw "An error occured when contacting ${Repository}:`r`n$($_.Exception.Message)"
                }
            }

            # Downloading with Net.WebClient seems to remove the BOM automatically, this only seems to be neccessary when downloading with IWR. Still I'm leaving it in to be safe
            [xml]$PARSEDXML = $XmlString -replace "^$UTF8ByteOrderMark"
        } elseif ($RepositoryType -eq 'FILE') {
            $XmlString = Get-Content -LiteralPath $DatabaseXmlPath -Raw

            # Strings with a BOM cannot be cast to an XmlElement, so we make sure to remove it if present
            [xml]$PARSEDXML = $XmlString -replace "^$UTF8ByteOrderMark"
        }

        foreach ($Package in $PARSEDXML.Database.package) {
            if ($Package.SystemCompatibility.System.mtm -contains $Model) {
                $PathInfo = Get-PackagePathInfo -Path $Package.LocalPath -BasePath $Repository
                Write-Debug "Repo: $Repository, PkgLocation: $($Package.LocalPath), PkgInfo: $PathInfo"
                if ($PathInfo.Reachable) {
                    [PackagePointer]@{
                        XMLFullPath  = $PathInfo.AbsoluteLocation
                        XMLFile      = $Package.LocalPath -replace '^.*[\\/]'
                        Directory    = $PathInfo.AbsoluteLocation -replace '[^\\/]*$'
                        Category     = ""
                        LocationType = $PathInfo.Type
                    }
                } else {
                    Write-Error "The package definition at $($Package.LocalPath) could not be found or accessed"
                }
            } else {
                Write-Debug "Package $($Package.LocalPath) is not applicable to the computer model"
            }
        }
    } else {
        throw "Could not find '${Model}_Win10.xml' or 'database.xml' package index files inside the repository - cannot retrieve any packages"
    }
}
