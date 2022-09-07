[CmdletBinding()]
param(
    [Parameter(ValueFromPipelineByPropertyName)] [string] $logDir = "${Env:SystemDrive}\Logs",
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [string] $schTskName,
    [Parameter(ValueFromPipelineByPropertyName)]            [string] $schTskDesc,
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [string] $schTskDaysOfWeek,
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [string] $schTskTime,
    [Parameter(ValueFromPipelineByPropertyName)]            [string] $schTskLimitHrs,
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [string] $schTskUser,
    [Parameter(ValueFromPipelineByPropertyName)]            [string] $schTskRunLevel,
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [string] $schTskCommand,
    [Parameter(ValueFromPipelineByPropertyName)]            [string] $schTskCommandArgs
)

$ErrorActionPreference = 'Stop'

Write-Host "Starting scheduled task configuration for $schTskName ..."

# Check for existing Log directory
Get-Item -Path $logDir -ErrorAction SilentlyContinue -OutVariable logDirExists
if (!$logDirExists) {
    Write-Host "Creating compressed log directory..."
    # Create Log directory and Apply NTFS Compression
    New-Item -Path $logDir -ItemType "directory" -Force
    compact /c /f /i /s:$logDir
    compact /c /f /i /s:$logDir *
    Write-Host "Successfully created compressed log directory."
}
else {
    Write-Host "Log folder exists. Nothing to do."
}

# Replace spaces in schTskName for log file name
$schTskNameConcat = $schTskName -replace '\s',''

# Generate log file name
$logFileName = "ConfigureScheduledTask_${schTskNameConcat}_" + (Get-Date -Format "MM_dd_yyyy-HHmm") + ".log"

# Start logging transcript
Start-Transcript "${logDir}\${logFileName}"

# Function to create new scheduled task
Function New-CustomScheduledTask {
    Write-Host "Creating new $schTskName scheduled task..."

    # Set defaults for optional parameters if not specified
    $schTskDefaultDesc = if ($schTskDesc) { $schTskDesc } else { "Created by PowerShell" }
    $schTskDefaultRunLevel = if ($schTskRunLevel) { $schTskRunLevel } else { 'Limited' }
    $schTskDefaultLimitHrs = if ($schTskLimitHrs) { $schTskLimitHrs } else { '1' }
    $schTskDefaultCmdArgs = if ($schTskCommandArgs) { $schTskCommandArgs } else { ' ' }
    # Set scheduled task configuration
    $schTskAction = New-ScheduledTaskAction -Execute $schTskCommand -Argument $schTskDefaultCmdArgs
    $daysOfWeekArray = $schTskDaysOfWeek.split(" ")
    $schTskTrigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek $daysOfWeekArray -At $schTskTime
    $schTskPrincipal = New-ScheduledTaskPrincipal -UserId $schTskUser -RunLevel $schTskDefaultRunLevel
    $schTskTimeSpan = New-Timespan -hour $schTskDefaultLimitHrs
    $schTskSettingsSet = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable -WakeToRun -ExecutionTimeLimit $schTskTimeSpan
    $schTsk = New-ScheduledTask -Action $schTskAction -Principal $schTskPrincipal -Trigger $schTskTrigger -Settings $schTskSettingsSet -Description $schTskDefaultDesc

    try {
        # Register scheduled task
        Register-ScheduledTask -TaskName $schTskName -InputObject $schTsk -ErrorAction Stop
        Write-Host "Created new $schTskName scheduled task."
    }
    # Error if run without Administrator permissions
    catch [Microsoft.Management.Infrastructure.CimException] {
        Write-Error "ERROR: Administrator permissions required."
    }
    catch [System.Management.Automation.ParameterBindingException] {
        Write-Error "ERROR: Invalid scheduled task parameter supplied."
    }
    # Other errors
    catch {
        Write-Error "ERROR: An unknown error has occurred."
    }
}

# Function to re-create existing scheduled task
Function Redo-CustomScheduledTask {
    Write-Warning "Existing $schTskName scheduled task found."
    Write-Host "Un-registering existing $schTskName scheduled task..."
    Unregister-ScheduledTask -TaskName $schTskName -Confirm:$false
    New-CustomScheduledTask
}

# Check for existing scheduled task, re-apply if found
Get-ScheduledTask -TaskName $schTskName -ErrorAction SilentlyContinue -OutVariable taskExists
if (!$taskExists) {
    New-CustomScheduledTask
}
else {
    Redo-CustomScheduledTask
}

# End of Script
Write-Host "Successfully completed $schTskName scheduled task configuration."

# Stop logging transcript
Stop-Transcript
