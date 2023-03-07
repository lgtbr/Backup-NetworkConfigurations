#Read-Host -AsSecureString | ConvertFrom-SecureString

<#
.NOTES
    Author: Louis GATTABRUSI
    Last Edit: 2023-03-06
    Version 1.0 - initial release of Backup-NetworkDevices.ps1

.SYNOPSIS
    Script to backup network devices

.DESCRIPTION
    This script backup your network devices via SSH connection (Posh-SSH Module).
    Backup command is sent to the Open TFTP Server and backup is stored into TFTP Server.

    This is how it works :
    1) The script get current location, check if networkDevices.json file and /config/ folder exists
    
    2) Loading Backup-NetworkEquipmentsConfig and Get-NetworkEquipments functions

    3) Starting TFTP Server

    4) Check if module Posh-SSH is installed

    5) Backing up network devices by calling Get-NetworkEquipments and Backup-NetworkEquipmentsConfig functions

    6) Stopping TFTP Server 

    / ! \ PLEASE READ THE PREREQUISITES

    1) Download Open TFTP Server:
    In order to work, please download and install Open TFTP Server via this link:
    https://sourceforge.net/projects/tftp-server/

    2) Setup Open TFTP Server:

        A) Create a new folder where you want to store your backup:
        For example : C:\Backup_CFG_TFTP

        B) On the Open TFTP Server configuration file "OpenTFTPServerInstallationDirectory\OpenTFTPServerMT.ini" (default : C:\OpenTFTPServer\OpenTFTPServerMT.ini): 
        Configure your home directory. Please, use the same path where you want to store your backup.
        For example, you want to store your backups into "C:\Backup_CFG_TFTP", define "C:\Backup_CFG_TFTP" as home foler like this:

        [HOME]
        #You should specify home directory(s) here
        #You can specify one directory as home
        #directory, from where files will be served or
        #deposited like:-
        C:\Backup_CFG_TFTP\

        Define the clients allowed to connect to the TFTP Server:
        [ALLOWED-CLIENTS]
        #These are permitted clients for TFTP Access.
        #Hosts having IP address within these ip ranges
        #only will be responded to DNS requests.
        #32 ranges can be specified.
        #If none is specified, then all are allowed
        192.168.1.12
        192.168.2.0/24

        C) Configure clients permissions:
        
        #Next are the file operation permissions
        #Clients can only read files if read is
        #set to Y, default is Y
        read=Y
        #Clients can only create new files if write is
        #set to Y, default is N
        write=Y
        #Clients can only overwrite existing files if
        #overwrite is #set to Y, default is N
        overwrite=Y

    3) Fill networkDevices.json file:
    You need to fill every values, here here are the details:

    "configBackupsLocation": "C:/XXX", 
                                 ^ : Where you want to store your backup. Re-use the path of the folder created in step 1*
                                 Please use forward slashes instead of backslashes. Forward slashes will be replaced by backslashes when executing the script

	"configRestorePoints": X,
                           ^ : How many backup files you want to keep per device

	"configTFTPServerIP": "XXX.XXX.XXX.XXX", 
                                  ^ : IP of the TFTP server. Even if it's on the same server, DON'T USE 127.0.0.1

    "XXX": [{
      ^ : Category of devices for example : firewalls, switchs, access points, ...
        "backupCommand" : "copy config tftp $TFTPServer $fileName.bak",
                                           ^ : Backup command that will be send by the device**
	       "hostname": "xxx",
                      ^ : Hostname of the device
	       "informations": {
	           "ip": "XXX.XXX.XXX.XXX", 
                          ^ : IP of the device you want to backup configuration
	           "username": "xxx", 
                          ^ : Username used to connect to the device
	           "password": "01000000d08xxxx" 
                               ^ : Device password as SecureString. To get the password converted as SecureString, please use the first line of the script***
	       }
	}],

    4) Set the Open TFTP MultiThreaded Server service to manual:
    Go to your windows services et set the Open TFTP MultiThreaded Server service startup type to manual.

    Why ?
    For security reasons, we don't leave the TFTP server open 24/7.
    The script will start TFTP server at the beginning of the script and the service will be stopped at the end.

    5) Create a firewall rule to allow TFTP trafic (UDP port 69 (nice number btw))

.PARAMETER <none>
    <none>

.LINK
    https://github.com/lgtbr/Backup-NetworkDevices/
#>


############################################################################################
#                                                                                          #
#                               0 - Initialisation & checks                                #
#                                                                                          #
############################################################################################

# Obtain the parent folder path of the currently running script and store it in the $scriptPath variable.
$scriptPath = $MyInvocation.MyCommand.Path
$scriptPath = Split-Path $scriptPath -Parent

# Check if a JSON file named networkDevices.json exists in the script's config folder. 
# If the file exists, it is loaded into the $networkEquipmentJSON variable. 
# If the file does not exist, the script creates the config folder and downloads the networkDevices.json file from a GitHub repository.
if (Get-Content "$scriptPath\config\networkDevices.json" -erroraction 'silentlycontinue' )  {
    $networkEquipmentJSON = Get-Content "$scriptPath\config\networkDevices.json" | ConvertFrom-Json
    Write-Host "✔️ - JSON file has been found and loaded" -ForegroundColor green
} else {
    if(Test-Path -Path "$scriptPath\config") {
        Write-Host "✔️ - The folder $scriptPath\config already exist." -ForegroundColor green
    } else {
        Write-Host "❌ - The folder $scriptPath\config does not exist !" -ForegroundColor red
        Write-Host "⚠️ - Creating folder $scriptPath\config" -ForegroundColor yellow
        New-Item "$scriptPath\config" -ItemType Directory | Out-Null
    }
    Write-Host "❌ - JSON file has not been found, file will be downloaded..." -ForegroundColor red
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lgtbr/Backup-NetworkDevices/main/config/networkDevices.json" -OutFile "$scriptPath\config\networkDevices.json"
    Write-Host "⚠️ - File has been downloaded, please configure the file before executing the script" -ForegroundColor yellow
    Write-Host "⚠️ - You can find more infornations on GitHub page https://github.com/lgtbr/Backup-NetworkDevices" -ForegroundColor yellow
    break
}

# Assign a value to the $folderLocation variable by extracting a path from the $networkEquipmentJSON object and replacing forward slashes with backslashes. 
$folderLocation = $networkEquipmentJSON.configBackupsLocation | % {$_.replace("/","\")}

# Check if a directory path stored in the $folderLocation variable exists. If the directory path does not exist, it creates a new directory with the path specified by $folderLocation.
if(Test-Path -Path $folderLocation) {
     Write-Host "✔️ - The folder $folderLocation already exist." -ForegroundColor green
} else {
    Write-Host "❌ - The folder $folderLocation does not exist !" -ForegroundColor red
    Write-Host "⚠️ - Creation of the folder $folderLocation..." -ForegroundColor yellow
    New-Item $folderLocation -ItemType Directory
}

# Obtain the current date and time as a string in a specific format and store it in the $actualDate variable.
# The variable will be used later in config file name backup. 
$actualDate = Get-Date -Format "MM.dd.yyyy_HH-mm-ss"

############################################################################################
#                                                                                          #
#                                      1 - Functions                                       #
#                                                                                          #
############################################################################################

# Takes an object as a parameter and returns a list of properties from that object, excluding any properties that start with the string "config".
function Get-NetworkEquipments($object) {
    $keys = $object | Get-Member -MemberType NoteProperty | Where-Object -Property Name -notlike "config*" | Select-Object -ExpandProperty Name
    foreach ($key in $keys) {
        $networkEquipmentJSON.$key
    }
}

# The function Backup-NetworkEquipmentsConfig performs the following tasks for each network equipment in the list of $networkEquipments:
#    • Connects to the equipment via SSH using the credentials specified in the JSON configuration file.
#    • Sends a backup command to the equipment using the backup command specified in the JSON configuration file, replacing the $fileName variable with the equipment hostname and the current date and time stamp and replacing the $TFTPServer variable with the TFTP server IP address specified in the JSON configuration file.
#    • Disconnects from the equipment via SSH.
#    • Checks if a folder with the equipment hostname exists in the backup location. If it does not exist, creates the folder.
#    • Moves the backup file created by the equipment to the equipment's folder in the backup location, renaming the file to include the equipment hostname and the current date and time stamp.
#    • Deletes old backup files from the equipment's folder in the backup location, keeping the number of backup files specified in the JSON configuration file.
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

# Check if the "TFTPServer" service is currently stopped or not. If the service is stopped, it starts the service.
$serviceState = Get-Service -Name "TFTPServer"

if ($serviceState.Status -eq "Stopped") {
    Start-Service -Name "TFTPServer"
    Write-Host "⚠️  - Starting Open TFTP Server service..." -ForegroundColor yellow
} else {
    Write-Host "✔️ - Open TFTP Server service is already started !" -ForegroundColor green
}

############################################################################################
#                                                                                          #
#                                3 - Check module Posh-SSH                                 #
#                                                                                          #
############################################################################################

# Check if the Posh-SSH module is installed. If the module is detected, it is imported. 
# If the module is not detected, the script attempts to install the module using the Install-Module cmdlet.
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

# Calls the Get-NetworkEquipments function to get the list of network equipment from the $networkEquipmentJSON configuration file and store it in the $networkEquipments variable.
$networkEquipments = Get-NetworkEquipments $networkEquipmentJSON

# Calls the Backup-NetworkEquipmentsConfig function to start the backup process for all the network equipment in the $networkEquipments variable.
Backup-NetworkEquipmentsConfig

############################################################################################
#                                                                                          #
#                                 5 - Stopping TFTP Server                                 #
#                                                                                          #
############################################################################################

# Check if the Open TFTP Server service if it is currently running. If its Status property is equal to "Running", then the Stop-Service cmdlet is used to stop the service.
$serviceState = Get-Service -Name "TFTPServer"

if ($serviceState.Status -eq "Running") {
    Stop-Service -Name "TFTPServer"
    Write-Host "⚠️ - The Open TFTP Server has been stopped !" -ForegroundColor yellow
} else {
    Write-Host "✔️ - The service is already stopped." -ForegroundColor green
}
