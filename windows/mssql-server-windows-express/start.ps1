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

$restore_dbs_cleaned = $restore_dbs.TrimStart('\\').TrimEnd('\\')

$dbs = $restore_dbs_cleaned | ConvertFrom-Json

if ($null -ne $dbs -And $dbs.Length -gt 0){
	Write-Verbose "Restoring $($dbs.Length) database(s)"
	Foreach($db in $dbs)
	{	
		$RelocateData = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile("$($db.dbName)", "c:\sqlexpress\data\$($db.dbName).mdf")
		$RelocateLog = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile("$($db.dbName)_Log", "c:\sqlexpress\data\$($db.dbName)_Log.ldf")

		Write-Verbose "Restore-SqlDatabase -ServerInstance '.\SQLEXPRESS' -Database $db.dbName -BackupFile $db.dbBackupFile -RelocateFile @($RelocateData,$RelocateLog)"
		Restore-SqlDatabase -ServerInstance ".\SQLEXPRESS" -Database $db.dbName -BackupFile $db.dbBackupFile -RelocateFile @($RelocateData,$RelocateLog)
	}
}

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

while ($true) { 
    Get-EventLog -LogName Application -Source "MSSQL*" -After $lastCheck | Select-Object TimeGenerated, EntryType, Message	 
    $lastCheck = Get-Date 
    Start-Sleep -Seconds 2 
}
