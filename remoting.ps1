###Remote Server Config Script###
#  Author: Steve Irvine		#
#  Version: 0.1		        #
#################################

[CmdletBinding(SupportsShouldProcess=$True)] 

param ([Parameter(Mandatory=$true)][String]$application , 
       [Parameter(Mandatory=$true)][String]$environment
)

Clear-Host
write-host "     "
write-host "==============================================================================="

$MaxThreads = 5
$SleepTimer = 500
$MaxWaitAtEnd = 600
$OutputType = "Text"
$Computers = Get-Content ".\$application\$environment\servers.txt"
$credentials = Get-Credential
$destinationpath = "c:\install\test1.ps1"

#Grab the content from the first script and hold
$content = Get-Content -path ".\test1.ps1"

#Based on the value of the second argument to the script
#Append the content of an application specific scripts
if (Test-Path ".\$application\test1.ps1"){
	$appcontent = Get-Content ".\$application\test1.ps1"
	$content += $appcontent
}


"Killing existing jobs . . ."
Get-Job | Remove-Job -Force
"Done."

$i = 0

ForEach ($Computer in $Computers){
    While ($(Get-Job -state running).count -ge $MaxThreads){
        Write-Progress  -Activity "Creating Server List" -Status "Waiting for threads to close" `
	-CurrentOperation "$i threads created - $($(Get-Job -state running).count) threads open "`
	-PercentComplete ($i / $Computers.count * 100)
        
	Start-Sleep -Milliseconds $SleepTimer
}

    #"Starting job - $Computer"
$i++
	
    #Make a new file on the filesystem, this command and the one below run concurrently not as background threads
Invoke-Command -ComputerName $Computer -ScriptBlock `
	{param($destinationpath) new-item -Path $destinationpath -force -type file} `
	-Credential $credentials -argumentlist $destinationpath 
	
	#Pipe the content of the source file to it serially 
Invoke-Command -ComputerName $Computer -ScriptBlock `
	{ param ($destinationpath, $content) Add-Content -Path $destinationpath -Value $content } `
	-Credential $credentials -argumentlist $destinationpath, $content
	
	#Run the script we've just copied, this could take a long time
	#so I make it a thread and run it in the background with the -asjob parameter
Invoke-Command -asjob -ComputerName $Computer -ScriptBlock  `
	{param($destinationpath) powershell -executionpolicy remotesigned $destinationpath}`
	 -Credential $credentials -argumentlist $destinationpath
 
Write-Progress  -Activity "Deploying Scripts" -Status "Starting Threads" -CurrentOperation `
	"$i threads created - $($(Get-Job -state running).count) threads open"`
	-PercentComplete ($i / $Computers.count * 100)
}

$Complete = Get-date

While ($(Get-Job -State Running).count -gt 0){
    $ComputersStillRunning = ""
    
    ForEach ($System  in $(Get-Job -state running)){$ComputersStillRunning += ", $($System.name)"}
    	
	$ComputersStillRunning = $ComputersStillRunning.Substring(2)
    	Write-Progress  -Activity "Deploying Scripts" -Status "$($(Get-Job -State Running).count) threads remaining" `
    	-CurrentOperation "$ComputersStillRunning" -PercentComplete ($(Get-Job -State Completed).count / $(Get-Job).count * 100)
    
    	If ($(New-TimeSpan $Complete $(Get-Date)).totalseconds -ge $MaxWaitAtEnd)`
    		{"Killing all jobs still running . . .";Get-Job -State Running | Remove-Job -Force}
    	Start-Sleep -Milliseconds $SleepTimer
}

#Build a log file name
$deploylog = ".\Logs\$env:username-$application-$environment-$(get-date -format MMddyyHHmmss).log" 

#Grab all current background tasks, and dump them into our logfile
get-job | receive-job | out-file $deploylog 

Write-Host "Deployment Complete, logs at $deploylog"
