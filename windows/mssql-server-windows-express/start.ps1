# The script sets the sa password and start the SQL Service 
# Also it attaches additional database from the disk
# The format for attach_dbs
# The format for restore_dbs


param(
[Parameter(Mandatory=$false)]
[string]$sa_password,

[Parameter(Mandatory=$false)]
[string]$ACCEPT_EULA,

[Parameter(Mandatory=$false)]
[string]$attach_dbs,

[Parameter(Mandatory=$false)]
[string]$restore_dbs
)


if($ACCEPT_EULA -ne "Y" -And $ACCEPT_EULA -ne "y"){
	Write-Verbose "ERROR: You must accept the End User License Agreement before this container can start."
	Write-Verbose "Set the environment variable ACCEPT_EULA to 'Y' if you accept the agreement."

    exit 1 
}

# start the service
Write-Verbose "Starting SQL Server"
start-service MSSQL`$SQLEXPRESS

if($sa_password -ne "_"){
	Write-Verbose "Changing SA login credentials"
    $sqlcmd = "ALTER LOGIN sa with password=" +"'" + $sa_password + "'" + ";ALTER LOGIN sa ENABLE;"
    Invoke-Sqlcmd -Query $sqlcmd -ServerInstance ".\SQLEXPRESS" 
}

#--env restore_dbs="[{'dbName': 'ISHDB-12.0.0','dbDataPath': 'c:\\sqlexpress\\data\\','dbLogPath': 'c:\\sqlexpress\\log\\','dbBackupFile': 'C:\\sqlexpress\\backup\\ISH-12.0.0-sqlserver2012.MobilePhones.bak'}]"
$restore_dbs_cleaned = $restore_dbs.TrimStart('\\').TrimEnd('\\')

$dbs = $restore_dbs_cleaned | ConvertFrom-Json

if ($null -ne $dbs -And $dbs.Length -gt 0){
    $svrConn = new-object Microsoft.SqlServer.Management.Common.ServerConnection
    $svrConn.ServerInstance = ".\SQLEXPRESS"
    $svrConn.LoginSecure = $true
    $svr = new-object Microsoft.SqlServer.Management.Smo.Server ($svrConn)
    $defaultDbDataPath = if ($svr.Settings.DefaultFile) { $svr.Settings.DefaultFile } else { $svr.MasterDBPath }
    $defaultDbLogPath = if ($svr.Settings.DefaultLog) { $svr.Settings.DefaultLog } else { $svr.MasterDBLogPath }
    $res = new-object Microsoft.SqlServer.Management.Smo.Restore

	Write-Verbose "Restoring $($dbs.Length) database(s) to $($svr.Name)"
	Foreach($db in $dbs)
	{	
		Write-Verbose "Restoring $($db)"
        $res.Devices.AddDevice($db.dbBackupFile, [Microsoft.SqlServer.Management.Smo.DeviceType]::File)
        $dt = $res.ReadFileList($svr)
        $RelocateFile = @()
        $dbDataPath = if ($db.dbDataPath) { $db.dbDataPath } else { $defaultDbDataPath }
        Write-Verbose "Using Data folder $($dbDataPath)"
        $dbLogPath = if ($db.dbLogPath) { $db.dbLogPath } else { $defaultDbLogPath }
        Write-Verbose "Using Log folder $($dbLogPath)"
		
        foreach($r in $dt.Rows)
        {
            $logicalFileName = $r["LogicalName"]
            $type = $r["Type"]
            $physicalFilePath = if ($type -eq "D") { $dbDataPath.TrimEnd('\\') } else { $dbLogPath.TrimEnd('\\') }
            $physicalFileName = Split-Path $r["PhysicalName"] -leaf
            Write-Verbose "RelocateFile with LogicalFileName:  $($logicalFileName), PhysicalName: $($physicalFileName)"
            $RelocateFile += New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($logicalFileName, "$($physicalFilePath)\$($physicalFileName)")
        }

		Write-Verbose "Restore-SqlDatabase -ServerInstance '.\SQLEXPRESS' -Database $db.dbName -BackupFile $db.dbBackupFile -RelocateFile $RelocateFile"
		Restore-SqlDatabase -ServerInstance ".\SQLEXPRESS" -Database $db.dbName -BackupFile $db.dbBackupFile -RelocateFile $RelocateFile
	}
}

#--env attach_dbs="[{'dbName': 'IShDita_130','dbFiles': ['C:\\sqlexpress\\data\\IShDita_130.mdf', 'C:\\sqlexpress\\data\\IShDita_130.ldf']}]"
$attach_dbs_cleaned = $attach_dbs.TrimStart('\\').TrimEnd('\\')

$dbs = $attach_dbs_cleaned | ConvertFrom-Json

if ($null -ne $dbs -And $dbs.Length -gt 0){
	Write-Verbose "Attaching $($dbs.Length) database(s)"
	Foreach($db in $dbs)
	{
		$files = @();
		Foreach($file in $db.dbFiles)
		{
			$files += "(FILENAME = N'$($file)')";
		}
		
		$files = $files -join ","
		$sqlcmd = "sp_detach_db ""$($db.dbName)"";CREATE DATABASE ""$($db.dbName)"" ON $($files) FOR ATTACH ;"

		Write-Verbose "Invoke-Sqlcmd -Query $($sqlcmd) -ServerInstance '.\SQLEXPRESS'"
		Invoke-Sqlcmd -Query $sqlcmd -ServerInstance ".\SQLEXPRESS"
	}
}

Write-Verbose "Started SQL Server."

$lastCheck = (Get-Date).AddSeconds(-2) 
<#
while ($true) { 
    Get-EventLog -LogName Application -Source "MSSQL*" -After $lastCheck | Select-Object TimeGenerated, EntryType, Message	 
    $lastCheck = Get-Date 
    Start-Sleep -Seconds 2 
}
#>
powershell
