#$secureString = Read-Host -AsSecureString | ConvertFrom-SecureString

###############################################################################################
#                                                                                             #
# DESCRIPTION                                                                                 #
#                                                                                             #
# Ce script permet la sauvegarde de la configration d'un FortiSwitch (ou d'un autre           #
# équipement permettant la connexion en SSH puis l'export via TFTP).                          #
#                                                                                             #
# Il fonctionne uniquement pour un équipement. Pour l'utiliser sur plusieurs équipements, il  #
# faut faire une copie de ce fichier puis le reconfigurer pour l'équipement en question.      #
#                                                                                             #
###############################################################################################



###############################################################################################
#                                                                                             #
# 0 - PREREQUIS                                                                               #
#                                                                                             #
# / ! \ Télécharger TFTP Server de SolarWinds à cette adresse :                               #
# https://www.solarwinds.com/fr/free-tools/free-tftp-server                                   #
#                                                                                             #
# METTRE LE SERVICE TFTP SERVER EN MODE DEMARRAGE MANUEL                                      #
# Cela permettra de lancer le service uniquement quand on en a besoin via le script           #
#                                                                                             #
# Changer également le dossier racine du serveur TFTP afin de le faire correspondre à         #
# l'emplacement de la variable $folderLocation ci-dessous                                     #
#                                                                                             #
# Merci de compléter l'ensemble des variables ci-dessous puis lancer le script une première   #
# fois manuellement afin de renseigner le mot de passe de l'équipement                        #
#                                                                                             #
###############################################################################################

# Emplacement du fichier JSON
if (Get-Content "C:\Scripting\V2\config\network_equipment.json" -erroraction 'silentlycontinue' )  {
    $networkEquipmentJSON = Get-Content "C:\Scripting\V2\config\network_equipment.json" | ConvertFrom-Json
    Write-Host "OK - JSON file has been found and loaded" -ForegroundColor green
} else {
    Write-Host "NOK - JSON file has not been found and loaded, please check path and / or content" -ForegroundColor red
    break
}

# Emplacement où les configurations des équipements seront stockées 
$folderLocation = $networkEquipmentJSON.configBackupsLocation | % {$_.replace("/","\")}

$actualDate = Get-Date -Format "MM.dd.yyyy_HH-mm-ss"


###############################################################################################
#                                                                                             #
# 1 - DEMARRAGE DU SERVICE TFTP                                                               #
#                                                                                             #
###############################################################################################

$serviceState = Get-Service -Name "TFTPServer"

if ($serviceState.Status -eq "Stopped") {
    Start-Service -Name "TFTPServer"
    Write-Host "OK - Starting Open TFTP Server service..." -ForegroundColor yellow
} else {
    Write-Host "OK - Open TFTP Server service is already started !" -ForegroundColor green
}

###############################################################################################
#                                                                                             #
# 1 - PREPARATION ET INSTALLATION POSH-SSH                                                    #
#                                                                                             #
# On va voir si le dossier $folderName existe, si ce n'est pas le cas, on le crée             #
# Idem pour le module Posh-SSH, si il n'est pas installé, on l'installe                       #
#                                                                                             #
###############################################################################################

if(Test-Path -Path $folderLocation) {
     Write-Host "OK - The folder $folderLocation already exist." -ForegroundColor green
} else {
    Write-Host "NOK - The folder $folderLocation does not exist !" -ForegroundColor red
    Write-Host "OK - Creation of the folder $folderLocation..." -ForegroundColor yellow
    New-Item $folderLocation -ItemType Directory
}

if (Get-Module -ListAvailable -Name "Posh-SSH") {
    Import-Module Posh-SSH
    Write-Host "OK - The module Posh-SSH has been detected succesfully." -ForegroundColor green
} else {
    Write-Host "OK - The module Posh-SSH is not installed !" -ForegroundColor red
    Write-Host "OK - Please wait until the installation of Posh-SSH is being processed..." -ForegroundColor yellow
    Install-Module Posh-SSH -Confirm:$false -Force
}


###############################################################################################
#                                                                                             #
# 3 - CONNEXION SSH                                                                           #
#                                                                                             #
# Connexion à l'équipement en SSH, export de la config via TFTP et on ferme la connexion      #
# Rangement du fichier de config. dans un dossier qui porte le nom de l'équipement            #
# Si ce dossier n'existe pas, on le crée                                                      #
#                                                                                             #
###############################################################################################

function Get-NetworkEquipments($object) {
    $keys = $object | Get-Member -MemberType NoteProperty | Where-Object -Property Name -notlike "config*" | Select-Object -ExpandProperty Name
    foreach ($key in $keys) {
        $networkEquipmentJSON.$key
    }
}

function Backup-NetworkEquipmentsConfig {
    foreach ($equipment in $networkEquipments) {
        Write-Host "OK - Connecting to $($equipment.hostname) [$($equipment.informations.ip)]" -ForegroundColor Yellow

        $equipmentCredentials = New-Object System.Management.Automation.PSCredential -ArgumentList $equipment.informations.username, (ConvertTo-SecureString $equipment.informations.password -Force)
        New-SSHSession -ComputerName $equipment.informations.ip -Credential $equipmentCredentials -AcceptKey | Out-Null

        $SSHStream = New-SSHShellStream -Index 0
        $SSHStream.WriteLine("`n")
        Start-Sleep -s 1
        $SSHStream.read() | Out-Null

        Write-Host "OK - Sending backup command to $($equipment.hostname) [$($equipment.informations.ip)]" -ForegroundColor Green
        $SSHStream.WriteLine("$($equipment.backupCommand | % {$_.replace('$fileName',"CFG_$($equipment.hostname)-$actualDate")} | % {$_.replace('$TFTPServer',"$($networkEquipmentJSON.configTFTPServerIP)")})")
        Start-Sleep -s 20
        $SSHStream.read() | Out-Null

        Write-Host "OK - Disconnecting from $($equipment.hostname) [$($equipment.informations.ip)]" -ForegroundColor Green
        Remove-SSHSession -Index 0 | Out-Null

        if(Test-Path -Path "$folderLocation\$($equipment.hostname)") {
            Write-Host "OK - The folder $folderLocation\$($equipment.hostname) already exist." -ForegroundColor green
        } else {
            Write-Host "NOK - The folder $folderLocation\$($equipment.hostname) does not exist !" -ForegroundColor red
            New-Item "$folderLocation\$($equipment.hostname)" -ItemType Directory
            Write-Host "OK - Folder $folderLocation\$($equipment.hostname) has been created" -ForegroundColor green
        }

        if(Test-Path -Path "$folderLocation\CFG_$($equipment.hostname)-$actualDate.*") {
            Move-Item -Path "$folderLocation\CFG_$($equipment.hostname)-$actualDate.*" -Destination "$folderLocation\$($equipment.hostname)\" -Force
        } else {
            Write-Host "NOK - The file $folderLocation\$CFG_$($equipment.hostname)-$actualDate.* has not been moved because the file is unavailable !" -ForegroundColor red
        }
        Get-ChildItem -File -Path "$folderLocation\$($equipment.hostname)" -Filter *.* -Force | Sort -Property CreationTime -Descending | Select-Object -Skip $networkEquipmentJSON.configRestorePoints | Remove-Item
    }
}

$networkEquipments = Get-NetworkEquipments $networkEquipmentJSON
Backup-NetworkEquipmentsConfig

###############################################################################################
#                                                                                             #
# 5 - ARRET DU SERVICE TFTP                                                                   #
#                                                                                             #
###############################################################################################

$serviceState = Get-Service -Name "TFTPServer"

if ($serviceState.Status -eq "Running") {
    Stop-Service -Name "TFTPServer"
    Write-Host "OK - The Open TFTP Server has been stopped !" -ForegroundColor yellow
} else {
    Write-Host "OK - The service is already stopped." -ForegroundColor green
}
