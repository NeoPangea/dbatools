﻿function Get-DbaMaintenanceSolutionLog {
<#
.SYNOPSIS
Reads the log files generated by the IndexOptimize Agent Job from Ola Hallengren's MaintenanceSolution.

.DESCRIPTION
Ola wrote a .sql script to get the content from the commandLog table. However, if LogToTable='N', there will be no logging in that table. This function reads the text files that are written in the SQL Instance's Log directory.

.PARAMETER SqlInstance
The SQL Server instance. 

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 
Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES 
Author: Klaas Vandenberghe ( @powerdbaklaas )
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Get-DbaMaintenanceSolutionLog

.EXAMPLE 
Get-DbaMaintenanceSolutionLog -SqlInstance sqlserver2014a

Gets the outcome of the IndexOptimize job on sql instance sqlserver2014a

.EXAMPLE 
Get-DbaMaintenanceSolutionLog -SqlInstance sqlserver2014a -SqlCredential $credential

Gets the outcome of the IndexOptimize job on sqlserver2014a, using SQL Authentication
		
.EXAMPLE 
'sqlserver2014a', 'sqlserver2020test' | Get-DbaMaintenanceSolutionLog
	
Gets the outcome of the IndexOptimize job on sqlserver2014a and sqlserver2020test.
	
#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential = [System.Management.Automation.PSCredential]::Empty,
		[switch]$Silent
	)
	
	process {
		foreach ($instance in $sqlinstance) {
			$logdir = $logfiles = $null
			$computername = $instance.ComputerName
			Write-Message -Level Verbose -Message "Connecting to $instance"
			
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Can't connect to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			$logdir = $server.errorlogpath -replace '^(.):', "\\$computername\`$1$"
			if (!$logdir) {
				Write-Message -Level Warning -Message "No log directory returned from $instance"
				Continue
			}
			Write-Message -Level Verbose -Message "Log directory on $computername is $logdir"
			$logfiles = Get-ChildItem $logdir -Filter IndexOptimize_* | Select-Object -ExpandProperty fullName
			
			if (! $logfiles.count -ge 1) {
				Write-Message -Level Warning -Message "No log files returned from $computername"
				Continue
			}
			$instanceinfo = @{ }
			$instanceinfo['ComputerName'] = $server.NetName
			$instanceinfo['InstanceName'] = $server.ServiceName
			$instanceinfo['SqlInstance'] = $server.Name
			
			foreach ($File in $logfiles) {
				Write-Message -Level Verbose -Message "Reading $file"
				$text = New-Object System.IO.StreamReader -ArgumentList "$File"
				while ($line = $text.ReadLine()) {
					if ($line -match '^Database: \[(?<database>[^\]]+)') {
						$db = $instanceinfo.Clone()
						# $db['Database'] = $line.Split(': ')[-1]
						$db['Database'] = $Matches.database
						Write-Message -Level Verbose -Message "Index Optimizations on Database $($db.Database) on $computername"
					}
					if ($line -match '^Status | ^Standby | ^Updateability | ^Useraccess | ^Isaccessible | ^RecoveryModel') {
						$dbkey = $line.Split(': ')[0]
						$dbvalue = $line.Split(': ')[-1]
						$db[$dbkey] = $dbvalue
					}
					if ($line -match '^Command: ALTER INDEX \[(?<index>[^\]]+)\] ON \[(?<database>[^\]]+)\]\.\[(?<schema>[^]]+)\]\.\[(?<table>[^\]]+)\] (?<action>[^\ ]+) WITH \((?<options>[^\)]+)') {
						$index = $db.Clone()
						$index['Index'] = $Matches.index
						$index['Schema'] = $Matches.Schema
						$index['Table'] = $Matches.Table
						$index['action'] = $Matches.action
						$index['options'] = $Matches.options
						Write-Message -Level Verbose -Message "Index $($index.Index) on Table $($index.Table) in Database $($index.Database) on $computername"
					}
					if ($line -match "^Comment: ") {
						$line = $line.Replace('Comment: ', '')
						$commentparts = $line.Split(',')
						foreach ($part in $commentparts) {
							$indkey, $indvalue = $part.trim().split(': ')
							$index[$indkey] = $indvalue[-1]
						}
					}
					if ($line -match "^Outcome: ") { $index['outcome'] = $line.Split(': ')[-1] }
					if ($durationIndicator -eq $true) {
						$index['Endtime'] = $line -replace ('Date and Time: ', '')
						$durationIndicator = $false
						[PSCustomObject]$index
					}
					if ($line -match "^Duration: ") {
						$durationIndicator = $true
						$index['Duration'] = $line.Split(': ')[-3 .. -1] -join ':'
					}
				}
				$text.close()
			}
		}
	}
}