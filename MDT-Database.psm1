<#

    .SYNOPSIS
            Provides a set of PowerShell advanced functions (cmdlets) to
            manipulate the Microsoft Deployment Toolkit database contents.
            This required at least PowerShell 2.0 CTP3.
            
    .NOTES
        This version was forked from Michael Niehaus's original and Vaughn Miller additions.
        Same disclaimer applies, it is provided as is with no waranty
 
        Original Author: Michael Niehaus

        DISCLAIMER
        This script code is provided as is with no guarantee or waranty concerning
        the usability or impact on systems and may be used, distributed, and
        modified in any way provided the parties agree and acknowledge the 
        Microsoft or Microsoft Partners have neither accountabilty or 
        responsibility for results produced by use of this script.

        Microsoft will not provide any support through any means.
#>

function Clear-MDTArray {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(Mandatory = $true)]
        [string]
        $type,
        [Parameter(Mandatory = $true)]
        [string]
        $table
    )

    # Build the delete command
    $delCommand = "DELETE FROM $table WHERE ID = $id and Type = '$type'"
        
    # Issue the delete command
    Write-Verbose "About to issue command: $delCommand"
    $cmd = New-Object System.Data.SqlClient.SqlCommand($delCommand, $mdtSQLConnection)
    $null = $cmd.ExecuteScalar()

    Write-Host "Removed all records from $table for Type = $type and ID = $id."
}

function Get-MDTArray {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(Mandatory = $true)]
        [string]
        $type,
        [Parameter(Mandatory = $true)]
        [string]
        $table,
        [Parameter(Mandatory = $true)]
        [string]
        $column
    )

    # Build the select command
    $sql = "SELECT $column FROM $table WHERE ID = $id AND Type = '$type' ORDER BY Sequence"
        
    # Issue the select command and return the results
    Write-Verbose "About to issue command: $sql"
    $selectAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($sql, $mdtSQLConnection)
    $selectDataset = New-Object System.Data.Dataset
    $null = $selectAdapter.Fill($selectDataset, "$table")
    $selectDataset.Tables[0].Rows
}

function Set-MDTArray {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(Mandatory = $true)]
        [string]
        $type,
        [Parameter(Mandatory = $true)]
        [string]
        $table,
        [Parameter(Mandatory = $true)]
        [string]
        $column,
        [Parameter(Mandatory = $true)]
        [string[]]
        $array
    )

    # First clear the existing array
    Clear-MDTArray $id $type $table
    
    # Now insert each row in the array
    $seq = 1
    foreach ($item in $array) {
        # Insert the  row
        $sql = "INSERT INTO $table (Type, ID, Sequence, $column) VALUES ('$type', $id, $seq, '$item')"
        Write-Verbose "About to execute command: $sql"
        $settingsCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $null = $settingsCmd.ExecuteScalar()

        # Increment the counter
        $seq = $seq + 1
    }
        
    Write-Host "Added records to $table for Type = $type and ID = $id."
}

# Connection function

function Connect-MDTDatabase {

    [CmdletBinding()]
    param
    (
        [Parameter(Position = 1)] 
        $drivePath = "",
        [Parameter()] 
        $sqlServer,
        [Parameter()] 
        $instance = "",
        [Parameter()] 
        $database
    )

    # If $mdtDatabase exists from a previous execution, clear it
    if ($mdtDatabase) {
        Clear-Variable -name mdtDatabase
    }

    # If a drive path is specified, use PowerShell to build the connection string.
    # Otherwise, build it from the other parameters
    if ($drivePath -ne "") {
        # Get the needed properties to build the connection string    
        $mdtProperties = get-itemproperty $drivePath

        $mdtSQLConnectString = "Server=$($mdtProperties.'Database.SQLServer')"
        if ($mdtProperties."Database.Instance" -ne "") {
            $mdtSQLConnectString = "$mdtSQLConnectString\$($mdtProperties.'Database.Instance')"
        }
        $mdtSQLConnectString = "$mdtSQLConnectString; Database='$($mdtProperties.'Database.Name')'; Integrated Security=true;"
    }
    else {
        $mdtSQLConnectString = "Server=$($sqlServer)"
        if ($instance -ne "") {
            $mdtSQLConnectString = "$mdtSQLConnectString\$instance"
        }
        $mdtSQLConnectString = "$mdtSQLConnectString; Database='$database'; Integrated Security=true;"
    }
    
    # Make the connection and save it in a global variable
    Write-Host "Connecting to: $mdtSQLConnectString"
    $global:mdtSQLConnection = new-object System.Data.SqlClient.SqlConnection
    $global:mdtSQLConnection.ConnectionString = $mdtSQLConnectString
    $global:mdtSQLConnection.Open()
}

#region Computer functions

function New-MDTComputer {

    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $assetTag,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $macAddress,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $serialNumber,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $uuid,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $description,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $settings
    )

    Process {
        # Insert a new computer row and get the identity result
        $sql = "INSERT INTO ComputerIdentity (AssetTag, SerialNumber, MacAddress, UUID, Description) VALUES ('$assetTag', '$serialNumber', '$macAddress', '$uuid', '$description') SELECT @@IDENTITY"
        Write-Verbose "About to execute command: $sql"
        $identityCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $identity = $identityCmd.ExecuteScalar()
        Write-Verbose "Added computer identity record"
    
        # Insert the settings row, adding the values as specified in the hash table
        $settingsColumns = $settings.Keys -join ","
        $settingsValues = $settings.Values -join "','"
        $sql = "INSERT INTO Settings (Type, ID, $settingsColumns) VALUES ('C', $identity, '$settingsValues')"
        Write-Verbose "About to execute command: $sql"
        $settingsCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $null = $settingsCmd.ExecuteScalar()
            
        Write-Host "Added settings for the specified computer"
        
        # Write the new record back to the pipeline
        Get-MDTComputer -ID $identity
    }
}

function Get-MDTComputer {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $assetTag = "",
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $macAddress = "",
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $serialNumber = "",
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $uuid = "",
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $description = ""
    )
    
    Process {
        # Build a select statement based on what parameters were specified
        if ($id -eq "" -and $assetTag -eq "" -and $macAddress -eq "" -and $serialNumber -eq "" -and $uuid -eq "" -and $description -eq "") {
            $sql = "SELECT * FROM ComputerSettings"
        }
        elseif ($id -ne "") {
            $sql = "SELECT * FROM ComputerSettings WHERE ID = $id"
        }
        else {
            # Specified the initial command
            $sql = "SELECT * FROM ComputerSettings WHERE "
        
            # Add the appropriate where clauses
            if ($assetTag -ne "") {
                $sql = "$sql AssetTag='$assetTag' AND"
            }
        
            if ($macAddress -ne "") {
                $sql = "$sql MacAddress='$macAddress' AND"
            }

            if ($serialNumber -ne "") {
                $sql = "$sql SerialNumber='$serialNumber' AND"
            }

            if ($uuid -ne "") {
                $sql = "$sql UUID='$uuid' AND"
            }

            if ($description -ne "") {
                $sql = "$sql Description='$description' AND"
            }
    
            # Chop off the last " AND"
            $sql = $sql.Substring(0, $sql.Length - 4)
        }
    
        $selectAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($sql, $mdtSQLConnection)
        $selectDataset = New-Object System.Data.Dataset
        $null = $selectAdapter.Fill($selectDataset, "ComputerSettings")
        $selectDataset.Tables[0].Rows
    }
}

function Set-MDTComputer {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(Mandatory = $true)]
        [string[]]
        $settings
    )
    
    Process {
        # Add each each hash table entry to the update statement
        $sql = "UPDATE Settings SET"
        foreach ($setting in $settings.GetEnumerator()) {
            $sql = "$sql $($setting.Key) = '$($setting.Value)', "
        }
        
        # Chop off the trailing ", "
        $sql = $sql.Substring(0, $sql.Length - 2)

        # Add the where clause
        $sql = "$sql WHERE ID = $id AND Type = 'C'"
        
        # Execute the command
        Write-Verbose "About to execute command: $sql"        
        $settingsCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $null = $settingsCmd.ExecuteScalar()
            
        Write-Host "Added settings for the specified computer"
        
        # Write the updated record back to the pipeline
        Get-MDTComputer -ID $id
    }
}

function Remove-MDTComputer {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        # Build the delete command
        $delCommand = "DELETE FROM ComputerIdentity WHERE ID = $id"
        
        # Issue the delete command
        Write-Verbose "About to issue command: $delCommand"
        $cmd = New-Object System.Data.SqlClient.SqlCommand($delCommand, $mdtSQLConnection)
        $null = $cmd.ExecuteScalar()

        Write-Host "Removed the computer with ID = $id."
    }
}

function Set-MDTComputerIdentity {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(Mandatory = $true)]
        [Hashtable]
        $settings
    )
    
    Process {
        # Add each each hash table entry to the update statement
        $sql = "UPDATE ComputerIdentity SET"
        foreach ($setting in $settings.GetEnumerator()) {
            $sql = "$sql $($setting.Key) = '$($setting.Value)', "
        }
        
        # Chop off the trailing ", "
        $sql = $sql.Substring(0, $sql.Length - 2)

        # Add the where clause
        $sql = "$sql WHERE ID = $id"
        
        # Execute the command
        Write-Verbose "About to execute command: $sql"        
        $settingsCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $null = $settingsCmd.ExecuteScalar()
            
        Write-Verbose "Update settings for the specified computer"
        
        # Write the updated record back to the pipeline
        Get-MDTComputer -ID $id
    }
}

function Get-MDTComputerApplication {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'C' 'Settings_Applications' 'Applications'
    }
}

function Clear-MDTComputerApplication {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'C' 'Settings_Applications'
    }
}

function Set-MDTComputerApplication {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $applications
    )

    Process {
        Set-MDTArray $id 'C' 'Settings_Applications' 'Applications' $applications
    }
}

function Get-MDTComputerPackage {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'C' 'Settings_Packages' 'Packages'
    }
}

function Clear-MDTComputerPackage {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'C' 'Settings_Packages'
    }
}

function Set-MDTComputerPackage {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)] 
        [string[]]
        $packages
    )

    Process {
        Set-MDTArray $id 'C' 'Settings_Packages' 'Packages' $packages
    }
}

function Get-MDTComputerRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'C' 'Settings_Roles' 'Role'
    }
}

function Clear-MDTComputerRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'C' 'Settings_Roles'
    }
}

function Set-MDTComputerRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $roles
    )

    Process {
        Set-MDTArray $id 'C' 'Settings_Roles' 'Role' $roles
    }
}

function Get-MDTComputerAdministrator {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'C' 'Settings_Administrators' 'Administrators'
    }
}

function Clear-MDTComputerAdministrator {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'C' 'Settings_Administrators'
    }
}

function Set-MDTComputerAdministrator {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $administrators
    )

    Process {
        Set-MDTArray $id 'C' 'Settings_Administrators' 'Administrators' $administrators
    }
}

#endregion


#region Role functions
function New-MDTRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $name,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $settings
    )

    Process {
        # Insert a new role row and get the identity result
        $sql = "INSERT INTO RoleIdentity (Role) VALUES ('$name') SELECT @@IDENTITY"
        Write-Verbose "About to execute command: $sql"
        $identityCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $identity = $identityCmd.ExecuteScalar()
        Write-Verbose "Added role identity record"
    
        # Insert the settings row, adding the values as specified in the hash table
        $settingsColumns = $settings.Keys -join ","
        $settingsValues = $settings.Values -join "','"
        $sql = "INSERT INTO Settings (Type, ID, $settingsColumns) VALUES ('R', $identity, '$settingsValues')"
        Write-Verbose "About to execute command: $sql"
        $settingsCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $null = $settingsCmd.ExecuteScalar()
            
        Write-Host "Added settings for the specified role"
        
        # Write the new record back to the pipeline
        Get-MDTRole -ID $identity
    }
}

function Get-MDTRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $name = ""
    )
    
    Process {
        # Build a select statement based on what parameters were specified
        if ($id -eq "" -and $name -eq "") {
            $sql = "SELECT * FROM RoleSettings"
        }
        elseif ($id -ne "") {
            $sql = "SELECT * FROM RoleSettings WHERE ID = $id"
        }
        else {
            $sql = "SELECT * FROM RoleSettings WHERE Role = '$name'"
        }
        
        # Execute the statement and return the results    
        $selectAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($sql, $mdtSQLConnection)
        $selectDataset = New-Object System.Data.Dataset
        $null = $selectAdapter.Fill($selectDataset, "RoleSettings")
        $selectDataset.Tables[0].Rows
    }
}

function Set-MDTRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(Mandatory = $true)]
        [string[]]
        $settings
    )
    
    Process {
        # Add each each hash table entry to the update statement
        $sql = "UPDATE Settings SET"
        foreach ($setting in $settings.GetEnumerator()) {
            $sql = "$sql $($setting.Key) = '$($setting.Value)', "
        }
        
        # Chop off the trailing ", "
        $sql = $sql.Substring(0, $sql.Length - 2)

        # Add the where clause
        $sql = "$sql WHERE ID = $id AND Type = 'R'"
        
        # Execute the command
        Write-Verbose "About to execute command: $sql"        
        $settingsCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $null = $settingsCmd.ExecuteScalar()
            
        Write-Host "Added settings for the specified role"
        
        # Write the updated record back to the pipeline
        Get-MDTRole -ID $id
    }
}

function Remove-MDTRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        # Build the delete command
        $delCommand = "DELETE FROM RoleIdentity WHERE ID = $id"
        
        # Issue the delete command
        Write-Verbose "About to issue command: $delCommand"
        $cmd = New-Object System.Data.SqlClient.SqlCommand($delCommand, $mdtSQLConnection)
        $null = $cmd.ExecuteScalar()

        Write-Host "Removed the role with ID = $id."
    }
}

function Get-MDTRoleApplication {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'R' 'Settings_Applications' 'Applications'
    }
}

function Clear-MDTRoleApplication {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'R' 'Settings_Applications'
    }
}

function Set-MDTRoleApplication {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $applications
    )

    Process {
        Set-MDTArray $id 'R' 'Settings_Applications' 'Applications' $applications
    }
}

function Get-MDTRolePackage {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'R' 'Settings_Packages' 'Packages'
    }
}

function Clear-MDTRolePackage {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'R' 'Settings_Packages'
    }
}

function Set-MDTRolePackage {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)] 
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)] 
        [string[]]
        $packages
    )

    Process {
        Set-MDTArray $id 'R' 'Settings_Packages' 'Packages' $packages
    }
}

function Get-MDTRoleRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'R' 'Settings_Roles' 'Role'
    }
}

function Clear-MDTRoleRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'R' 'Settings_Roles'
    }
}

function Set-MDTRoleRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $roles
    )

    Process {
        Set-MDTArray $id 'R' 'Settings_Roles' 'Role' $roles
    }
}

function Get-MDTRoleAdministrator {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'R' 'Settings_Administrators' 'Administrators'
    }
}

function Clear-MDTRoleAdministrator {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'R' 'Settings_Administrators'
    }
}

function Set-MDTRoleAdministrator {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $administrators
    )

    Process {
        Set-MDTArray $id 'R' 'Settings_Administrators' 'Administrators' $administrators
    }
}

#endregion

#region Location functions
function New-MDTLocation {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true)] 
        [string]
        $name,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string[]]
        $gateways,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $settings
    )

    Process {
        # Insert a new role row and get the identity result
        $sql = "INSERT INTO LocationIdentity (Location) VALUES ('$name') SELECT @@IDENTITY"
        Write-Verbose "About to execute command: $sql"
        $identityCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $identity = $identityCmd.ExecuteScalar()
        Write-Verbose "Added location identity record"
    
        # Set the gateways
        $null = Set-MDTLocation -id $identity -gateways $gateways
        
        # Insert the settings row, adding the values as specified in the hash table
        $settingsColumns = $settings.Keys -join ","
        $settingsValues = $settings.Values -join "','"
        $sql = "INSERT INTO Settings (Type, ID, $settingsColumns) VALUES ('L', $identity, '$settingsValues')"
        Write-Verbose "About to execute command: $sql"
        $settingsCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $null = $settingsCmd.ExecuteScalar()
            
        Write-Host "Added settings for the specified location"
        
        # Write the new record back to the pipeline
        Get-MDTLocation -ID $identity
    }
}

function Get-MDTLocation {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $name = "",
        [Parameter()]
        [switch]
        $detail = $false
    )
    
    Process {
        # Build a select statement based on what parameters were specified
        if ($id -eq "" -and $name -eq "") {
            if ($detail) {
                $sql = "SELECT * FROM LocationSettings"
            }
            else {
                $sql = "SELECT DISTINCT ID, Location FROM LocationSettings"
            }
        }
        elseif ($id -ne "") {
            if ($detail) {
                $sql = "SELECT * FROM LocationSettings WHERE ID = $id"
            }
            else {
                $sql = "SELECT DISTINCT ID, Location FROM LocationSettings WHERE ID = $id"
            }
        }
        else {
            if ($detail) {
                $sql = "SELECT * FROM LocationSettings WHERE Location = '$name'"
            }
            else {
                $sql = "SELECT DISTINCT ID, Location FROM LocationSettings WHERE Location = '$name'"
            }
        }
        
        # Execute the statement and return the results    
        $selectAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($sql, $mdtSQLConnection)
        $selectDataset = New-Object System.Data.Dataset
        $null = $selectAdapter.Fill($selectDataset, "LocationSettings")
        $selectDataset.Tables[0].Rows
    }
}

function Set-MDTLocation {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string[]]
        $gateways = $null,
        [Parameter()]
        [string[]]
        $settings = $null
    )
    
    Process {
        # If there are some new settings save them
        if ($settings -ne $null) {
            # Add each each hash table entry to the update statement
            $sql = "UPDATE Settings SET"
            foreach ($setting in $settings.GetEnumerator()) {
                $sql = "$sql $($setting.Key) = '$($setting.Value)', "
            }
        
            # Chop off the trailing ", "
            $sql = $sql.Substring(0, $sql.Length - 2)

            # Add the where clause
            $sql = "$sql WHERE ID = $id AND Type = 'L'"
        
            # Execute the command
            Write-Verbose "About to execute command: $sql"        
            $settingsCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
            $null = $settingsCmd.ExecuteScalar()
            
            Write-Host "Added settings for the specified location"
        }
        
        # If there are some gateways save them
        if ($gateways -ne $null) {
            # Build the delete command to remove the existing gateways
            $delCommand = "DELETE FROM LocationIdentity_DefaultGateway WHERE ID = $id"
        
            # Issue the delete command
            Write-Verbose "About to issue command: $delCommand"
            $cmd = New-Object System.Data.SqlClient.SqlCommand($delCommand, $mdtSQLConnection)
            $null = $cmd.ExecuteScalar()
            
            # Now insert the specified values
            foreach ($gateway in $gateways) {
                # Insert the  row
                $sql = "INSERT INTO LocationIdentity_DefaultGateway (ID, DefaultGateway) VALUES ($id, '$gateway')"
                Write-Verbose "About to execute command: $sql"
                $settingsCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
                $null = $settingsCmd.ExecuteScalar()

            }
            Write-Host "Set the default gateways for the location with ID = $id."    
        }
        
        # Write the updated record back to the pipeline
        Get-MDTLocation -ID $id
    }
}

function Remove-MDTLocation {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        # Build the delete command
        $delCommand = "DELETE FROM LocationIdentity WHERE ID = $id"
        
        # Issue the delete command
        Write-Verbose "About to issue command: $delCommand"
        $cmd = New-Object System.Data.SqlClient.SqlCommand($delCommand, $mdtSQLConnection)
        $null = $cmd.ExecuteScalar()

        Write-Host "Removed the location with ID = $id."
    }
}

function Get-MDTLocationApplication {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'L' 'Settings_Applications' 'Applications'
    }
}

function Clear-MDTLocationApplication {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'L' 'Settings_Applications'
    }
}

function Set-MDTLocationApplication {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $applications
    )

    Process {
        Set-MDTArray $id 'L' 'Settings_Applications' 'Applications' $applications
    }
}

function Get-MDTLocationPackage {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'L' 'Settings_Packages' 'Packages'
    }
}

function Clear-MDTLocationPackage {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'L' 'Settings_Packages'
    }
}

function Set-MDTLocationPackage {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $packages
    )

    Process {
        Set-MDTArray $id 'L' 'Settings_Packages' 'Packages' $packages
    }
}

function Get-MDTLocationRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'L' 'Settings_Roles' 'Role'
    }
}

function Clear-MDTLocationRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'L' 'Settings_Roles'
    }
}

function Set-MDTLocationRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $roles
    )

    Process {
        Set-MDTArray $id 'L' 'Settings_Roles' 'Role' $roles
    }
}

function Get-MDTLocationAdministrator {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'L' 'Settings_Administrators' 'Administrators'
    }
}

function Clear-MDTLocationAdministrator {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'L' 'Settings_Administrators'
    }
}

function Set-MDTLocationAdministrator {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $administrators
    )

    Process {
        Set-MDTArray $id 'L' 'Settings_Administrators' 'Administrators' $administrators
    }
}
#endregion

#region Make Model functions

function New-MDTMakeModel {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $make,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $model,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $settings
    )

    Process {
        # Insert a new role row and get the identity result
        $sql = "INSERT INTO MakeModelIdentity (Make, Model) VALUES ('$make', '$model') SELECT @@IDENTITY"
        Write-Verbose "About to execute command: $sql"
        $identityCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $identity = $identityCmd.ExecuteScalar()
        Write-Verbose "Added make model identity record"
    
        # Insert the settings row, adding the values as specified in the hash table
        $settingsColumns = $settings.Keys -join ","
        $settingsValues = $settings.Values -join "','"
        $sql = "INSERT INTO Settings (Type, ID, $settingsColumns) VALUES ('M', $identity, '$settingsValues')"
        Write-Verbose "About to execute command: $sql"
        $settingsCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $null = $settingsCmd.ExecuteScalar()
            
        Write-Host "Added settings for the specified make model"
        
        # Write the new record back to the pipeline
        Get-MDTMakeModel -ID $identity
    }
}

function Get-MDTMakeModel {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $make = "",
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $model = ""
    )
    
    Process {
        # Build a select statement based on what parameters were specified
        if ($id -eq "" -and $make -eq "" -and $model -eq "") {
            $sql = "SELECT * FROM MakeModelSettings"
        }
        elseif ($id -ne "") {
            $sql = "SELECT * FROM MakeModelSettings WHERE ID = $id"
        }
        elseif ($make -ne "" -and $model -ne "") {
            $sql = "SELECT * FROM MakeModelSettings WHERE Make = '$make' AND Model = '$model'"
        }
        elseif ($make -ne "") {
            $sql = "SELECT * FROM MakeModelSettings WHERE Make = '$make'"
        }
        else {
            $sql = "SELECT * FROM MakeModelSettings WHERE Model = '$model'"
        }
        
        # Execute the statement and return the results    
        $selectAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($sql, $mdtSQLConnection)
        $selectDataset = New-Object System.Data.Dataset
        $null = $selectAdapter.Fill($selectDataset, "MakeModelSettings")
        $selectDataset.Tables[0].Rows
    }
}

function Set-MDTMakeModel {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(Mandatory = $true)]
        [string[]]
        $settings
    )
    
    Process {
        # Add each each hash table entry to the update statement
        $sql = "UPDATE Settings SET"
        foreach ($setting in $settings.GetEnumerator()) {
            $sql = "$sql $($setting.Key) = '$($setting.Value)', "
        }
        
        # Chop off the trailing ", "
        $sql = $sql.Substring(0, $sql.Length - 2)

        # Add the where clause
        $sql = "$sql WHERE ID = $id AND Type = 'M'"
        
        # Execute the command
        Write-Verbose "About to execute command: $sql"        
        $settingsCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $null = $settingsCmd.ExecuteScalar()
            
        Write-Host "Added settings for the specified make model"
        
        # Write the updated record back to the pipeline
        Get-MDTMakeModel -ID $id
    }
}

function Remove-MDTMakeModel {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        # Build the delete command
        $delCommand = "DELETE FROM MakeModelIdentity WHERE ID = $id"
        
        # Issue the delete command
        Write-Verbose "About to issue command: $delCommand"
        $cmd = New-Object System.Data.SqlClient.SqlCommand($delCommand, $mdtSQLConnection)
        $null = $cmd.ExecuteScalar()

        Write-Host "Removed the make model with ID = $id."
    }
}

function Get-MDTMakeModelApplication {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'M' 'Settings_Applications' 'Applications'
    }
}

function Clear-MDTMakeModelApplication {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'M' 'Settings_Applications'
    }
}

function Set-MDTMakeModelApplication {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $applications
    )

    Process {
        Set-MDTArray $id 'M' 'Settings_Applications' 'Applications' $applications
    }
}

function Get-MDTMakeModelPackage {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'M' 'Settings_Packages' 'Packages'
    }
}

function Clear-MDTMakeModelPackage {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'M' 'Settings_Packages'
    }
}

function Set-MDTMakeModelPackage {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $packages
    )

    Process {
        Set-MDTArray $id 'M' 'Settings_Packages' 'Packages' $packages
    }
}

function Get-MDTMakeModelRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'M' 'Settings_Roles' 'Role'
    }
}

function Clear-MDTMakeModelRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'M' 'Settings_Roles'
    }
}

function Set-MDTMakeModelRole {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $roles
    )

    Process {
        Set-MDTArray $id 'M' 'Settings_Roles' 'Role' $roles
    }
}

function Get-MDTMakeModelAdministrator {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Get-MDTArray $id 'M' 'Settings_Administrators' 'Administrators'
    }
}

function Clear-MDTMakeModelAdministrator {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id
    )

    Process {
        Clear-MDTArray $id 'M' 'Settings_Administrators'
    }
}

function Set-MDTMakeModelAdministrator {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [uInt64]
        $id,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string[]]
        $administrators
    )

    Process {
        Set-MDTArray $id 'M' 'Settings_Administrators' 'Administrators' $administrators
    }
}

#endregion

#region Package mapping functions

function New-MDTPackageMapping {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string]
        $ARPName,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string]
        $package
    )

    Process {
        # Insert a new row
        $sql = "INSERT INTO PackageMapping (ARPName, Packages) VALUES ('$ARPName','$package')"
        Write-Verbose "About to execute command: $sql"
        $identityCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $null = $identityCmd.ExecuteScalar()
        Write-Verbose "Added package mapping record for $ARPName"
    
        # Write the new record back to the pipeline
        Get-MDTPackageMapping -ARPName $ARPName
    }
}

function Get-MDTPackageMapping {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $ARPName = "",
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $package = ""
    )
    
    Process {
        # Build a select statement based on what parameters were specified
        if ($ARPName -eq "" -and $package -eq "") {
            $sql = "SELECT * FROM PackageMapping"
        }
        elseif ($ARPName -ne "" -and $package -ne "") {
            $sql = "SELECT * FROM PackageMapping WHERE ARPName = '$ARPName' AND Packages = '$package'"
        }
        elseif ($ARPName -ne "") {
            $sql = "SELECT * FROM PackageMapping WHERE ARPName = '$ARPName'"
        }
        else {
            $sql = "SELECT * FROM PackageMapping WHERE Packages = '$package'"
        }
        
        # Execute the statement and return the results    
        $selectAdapter = New-Object System.Data.SqlClient.SqlDataAdapter($sql, $mdtSQLConnection)
        $selectDataset = New-Object System.Data.Dataset
        $null = $selectAdapter.Fill($selectDataset, "PackageMapping")
        $selectDataset.Tables[0].Rows
    }
}

function Set-MDTPackageMapping {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string]
        $ARPName,
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [string]
        $package = $null
    )
    
    Process {
        # Update the row
        $sql = "UPDATE PackageMapping SET Packages = '$package' WHERE ARPName = '$ARPName'"
        Write-Verbose "About to execute command: $sql"
        $settingsCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $null = $settingsCmd.ExecuteScalar()
        Write-Host "Updated the package mapping record for $ARPName to install package $package."    
        
        # Write the updated record back to the pipeline
        Get-MDTPackageMapping -ARPName $ARPName
    }
}

function Remove-MDTPackageMapping {

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $ARPName = "",
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]
        $package = ""
    )
    
    Process {
        # Build a delete statement based on what parameters were specified
        if ($ARPName -eq "" -and $package -eq "") {
            # Dangerous, delete them all
            $sql = "DELETE FROM PackageMapping"
        }
        elseif ($ARPName -ne "" -and $package -ne "") {
            $sql = "DELETE FROM PackageMapping WHERE ARPName = '$ARPName' AND Packages = '$package'"
        }
        elseif ($ARPName -ne "") {
            $sql = "DELETE FROM PackageMapping WHERE ARPName = '$ARPName'"
        }
        else {
            $sql = "DELETE FROM PackageMapping WHERE Packages = '$package'"
        }
        
        # Execute the delete command
        Write-Verbose "About to execute command: $sql"
        $settingsCmd = New-Object System.Data.SqlClient.SqlCommand($sql, $mdtSQLConnection)
        $null = $settingsCmd.ExecuteScalar()
        Write-Host "Removed package mapping records matching the specified parameters."    
    }
}

#endregion