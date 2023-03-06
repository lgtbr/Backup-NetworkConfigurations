#$secureString = Read-Host -AsSecureString | ConvertFrom-SecureString

<#
    .SYNOPSIS
    Adds a file name extension to a supplied name.

    .DESCRIPTION
    Adds a file name extension to a supplied name.
    Takes any strings for the file name or extension.

    .PARAMETER Name
    Specifies the file name.

    .PARAMETER Extension
    Specifies the extension. "Txt" is the default.

    .INPUTS
    None. You cannot pipe objects to Add-Extension.

    .OUTPUTS
    System.String. Add-Extension returns a string with the extension or file name.

    .EXAMPLE
    PS> extension -name "File"
    File.txt

    .EXAMPLE
    PS> extension -name "File" -extension "doc"
    File.doc

    .EXAMPLE
    PS> extension "File" "doc"
    File.doc

    .LINK
    Online version: http://www.fabrikam.com/extension.html

    .LINK
    Set-Item
#>


############################################################################################
#                                                                                          #
#                               0 - Initialisation & checks                                #
#                                                                                          #
############################################################################################

$scriptPath = $MyInvocation.MyCommand.Path
$scriptPath = Split-Path $scriptPath -Parent

# Emplacement du fichier JSON
if (Get-Content "$scriptPath\config\networkDevices.json" -erroraction 'silentlycontinue' )  {
    $networkEquipmentJSON = Get-Content "$scriptPath\config\networkDevices.json" | ConvertFrom-Json
    Write-Host "✔️ - JSON file has been found and loaded" -ForegroundColor green
} else {
    if(Test-Path -Path "$scriptPath\config") {
        Write-Host "✔️ - The folder $scriptPath\config already exist." -ForegroundColor green
    } else {
        Write-Host "❌ - The folder $scriptPath\config does not exist !" -ForegroundColor red
        Write-Host "⚠ - Creating folder $scriptPath\config" -ForegroundColor yellow
        New-Item "$scriptPath\config" -ItemType Directory | Out-Null
    }
    Write-Host "❌ - JSON file has not been found, file will be downloaded..." -ForegroundColor red
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lgtbr/Backup-NetworkDevices/main/config/networkDevices.json" -OutFile "$scriptPath\config\networkDevices.json"
    Write-Host "⚠ - File has been downloaded, please configure the file before executing the script" -ForegroundColor yellow
    Write-Host "⚠ - You can find more infornations on GitHub page https://github.com/lgtbr/Backup-NetworkDevices" -ForegroundColor yellow
    break
}

# Emplacement où les configurations des équipements seront stockées 
$folderLocation = $networkEquipmentJSON.configBackupsLocation | % {$_.replace("/","\")}

if(Test-Path -Path $folderLocation) {
     Write-Host "✔️ - The folder $folderLocation already exist." -ForegroundColor green
} else {
    Write-Host "❌ - The folder $folderLocation does not exist !" -ForegroundColor red
    Write-Host "⚠ - Creation of the folder $folderLocation..." -ForegroundColor yellow
    New-Item $folderLocation -ItemType Directory
}

$actualDate = Get-Date -Format "MM.dd.yyyy_HH-mm-ss"

############################################################################################
#                                                                                          #
#                                      1 - Functions                                       #
#                                                                                          #
############################################################################################

function Get-NetworkEquipments($object) {
    $keys = $object | Get-Member -MemberType NoteProperty | Where-Object -Property Name -notlike "config*" | Select-Object -ExpandProperty Name
    foreach ($key in $keys) {
        $networkEquipmentJSON.$key
    }
}

function Backup-NetworkEquipmentsConfig {
    foreach ($equipment in $networkEquipments) {
        Write-Host "⚠️ - Connecting to $($equipment.hostname) [$($equipment.informations.ip)]" -ForegroundColor Yellow

        $equipmentCredentials = New-Object System.Management.Automation.PSCredential -ArgumentList $equipment.informations.username, (ConvertTo-SecureString $equipment.informations.password -Force)
        New-SSHSession -ComputerName $equipment.informations.ip -Credential $equipmentCredentials -AcceptKey | Out-Null

        $SSHStream = New-SSHShellStream -Index 0
        $SSHStream.WriteLine("`n")
        Start-Sleep -s 1
        $SSHStream.read() | Out-Null

        Write-Host "✔️ - Sending backup command to $($equipment.hostname) [$($equipment.informations.ip)]" -ForegroundColor Green
        $SSHStream.WriteLine("$($equipment.backupCommand | % {$_.replace('$fileName',"CFG_$($equipment.hostname)-$actualDate")} | % {$_.replace('$TFTPServer',"$($networkEquipmentJSON.configTFTPServerIP)")})")
        Start-Sleep -s 20
        $SSHStream.read() | Out-Null

        Write-Host "⚠️ - Disconnecting from $($equipment.hostname) [$($equipment.informations.ip)]" -ForegroundColor Yellow
        Remove-SSHSession -Index 0 | Out-Null

        if(Test-Path -Path "$folderLocation\$($equipment.hostname)") {
            Write-Host "✔️ - The folder $folderLocation\$($equipment.hostname) already exist." -ForegroundColor green
        } else {
            Write-Host "❌ - The folder $folderLocation\$($equipment.hostname) does not exist !" -ForegroundColor red
            New-Item "$folderLocation\$($equipment.hostname)" -ItemType Directory
            Write-Host "✔️ - Folder $folderLocation\$($equipment.hostname) has been created" -ForegroundColor green
        }

        if(Test-Path -Path "$folderLocation\CFG_$($equipment.hostname)-$actualDate.*") {
            Move-Item -Path "$folderLocation\CFG_$($equipment.hostname)-$actualDate.*" -Destination "$folderLocation\$($equipment.hostname)\" -Force
        } else {
            Write-Host "❌ - The file $folderLocation\$CFG_$($equipment.hostname)-$actualDate.* has not been moved because the file is unavailable !" -ForegroundColor red
        }
        Get-ChildItem -File -Path "$folderLocation\$($equipment.hostname)" -Filter *.* -Force | Sort -Property CreationTime -Descending | Select-Object -Skip $networkEquipmentJSON.configRestorePoints | Remove-Item
    }
}

############################################################################################
#                                                                                          #
#                                 2 - Starting TFTP Server                                 #
#                                                                                          #
############################################################################################

$serviceState = Get-Service -Name "TFTPServer"

if ($serviceState.Status -eq "Stopped") {
    Start-Service -Name "TFTPServer"
    Write-Host "⚠  - Starting Open TFTP Server service..." -ForegroundColor yellow
} else {
    Write-Host "✔️ - Open TFTP Server service is already started !" -ForegroundColor green
}

############################################################################################
#                                                                                          #
#                                3 - Check module Posh-SSH                                 #
#                                                                                          #
############################################################################################

if (Get-Module -ListAvailable -Name "Posh-SSH") {
    Import-Module Posh-SSH
    Write-Host "✔️ - The module Posh-SSH has been detected succesfully." -ForegroundColor green
} else {
    Write-Host "❌ - The module Posh-SSH is not installed !" -ForegroundColor red
    Write-Host "⚠️ - Please wait until the installation of Posh-SSH is being processed..." -ForegroundColor yellow
    Install-Module Posh-SSH -Confirm:$false -Force
}

############################################################################################
#                                                                                          #
#                                4 - Backup network devices                                #
#                                                                                          #
############################################################################################

$networkEquipments = Get-NetworkEquipments $networkEquipmentJSON
Backup-NetworkEquipmentsConfig

############################################################################################
#                                                                                          #
#                                 5 - Stopping TFTP Server                                 #
#                                                                                          #
############################################################################################

$serviceState = Get-Service -Name "TFTPServer"

if ($serviceState.Status -eq "Running") {
    Stop-Service -Name "TFTPServer"
    Write-Host "⚠️ - The Open TFTP Server has been stopped !" -ForegroundColor yellow
} else {
    Write-Host "✔️ - The service is already stopped." -ForegroundColor green
}
