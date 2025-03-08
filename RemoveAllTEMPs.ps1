<#
	.SYNOPSIS
		Eliminar temporales y basura del PC

	.DESCRIPTION
		Eliminar temporales y basura del equipo, a si liveramos espacio y borramos tonterias que almacena Windows

	.PARAMETER -SystemInstall
		Esto pone el script en modo SystemInstall, configurado para ver por pantalla

	.EXAMPLE
		Ejecuta con privilegios de administrador o implementación de SCCM
		powershell.exe -executionpolicy bypass -file 'Remove All TEMPs V3.ps1' -SystemInstall

	.NOTES
		===========================================================================
		Created By:		Carlos Campos
		Created Date:	31/01/2025, 11:40 PM
		Version:		3.8
		File:			Remove All TEMPs.ps1
		Copyright (c)2025 Campos
		===========================================================================

	.LICENSE
		Por la presente, se otorga el permiso, de forma gratuita, a cualquier persona que obtenga una copia
		de este software y archivos de documentación asociados (el software), para tratar
		en el software sin restricción, incluidos los derechos de los derechos
		para usar copiar, modificar, fusionar, publicar, distribuir sublicense y /o vender
		copias del software y para permitir a las personas a quienes es el software
		proporcionado para hacerlo, sujeto a las siguientes condiciones:

		El aviso de derechos de autor anterior y este aviso de permiso se incluirán en todos
		copias o porciones sustanciales del software.

		EL SOFTWARE SE PROPORCIONA TAL CUAL, SIN GARANTÍA DE NINGÚN TIPO, EXPRESA O
		IMPLÍCITA, INCLUYENDO PERO SIN LIMITARSE A LAS GARANTÍAS DE COMERCIABILIDAD
		ADECUACIÓN PARA UN PROPÓSITO PARTICULAR Y NO INFRACCIÓN. EN NINGÚN CASO LOS
		AUTORES O TITULARES DE LOS DERECHOS DE AUTOR SERÁN RESPONSABLES DE NINGUNA RECLAMACIÓN, DAÑOS U OTROS
		RESPONSABILIDAD, YA SEA EN UNA ACCIÓN CONTRACTUAL, AGRAVIO O DE OTRO MODO, QUE SURJA DE
		DE O EN CONEXIÓN CON EL SOFTWARE O EL USO U OTROS TRATOS EN EL tSOFTWARE.
#>

[CmdletBinding()]
param
(
    [switch]$SystemInstall,
    [ValidateNotNullOrEmpty()][string]$PSConsoleTitle = 'Remove All TEMPs',
    [ValidateNotNullOrEmpty()][string]$actUpdates = 1,
    [ValidateNotNullOrEmpty()][string]$actLimTemp = 1,
    [ValidateNotNullOrEmpty()][string]$actWinOLD = 0,
    [ValidateNotNullOrEmpty()][string]$actPanther = 0
)


# Comprobar si el script se ejecuta como administrador
$IsAdmin = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$IsAdmin = (New-Object System.Security.Principal.WindowsPrincipal $IsAdmin).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Elevando permisos..."
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

<# $actUpdates = 1
$actLimTemp = 1
$actWinOLD  = 1
$actPanther = 1 #>

# Ruta del archivo de log
$logFile = "00 CleanupScriptLog.log"
$logPath = "$env:windir\Logs\Software"

#####################################################
#                                                   #
#     >> Funciones                                  #
#                                                   #
#####################################################
function Set-ConsoleTitle {
    <#
        .SYNOPSIS
            Console Title
        
        .DESCRIPTION
            Establece el título de la consola PowerShell
        
        .PARAMETER ConsoleTitle
            Título de la consola PowerShell
    #>
        
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)][String]$ConsoleTitle
    )
        
    $host.ui.RawUI.WindowTitle = $ConsoleTitle
}
# Función para escribir logs
function Write-Log {
    <#
    .SYNOPSIS
        Sistema de Logs
    
    .DESCRIPTION
        Con esta funcion podemos hacer un sistema de logs muy intuitivos para SCCM o uso personal
    
    .PARAMETER Message
        Write-Log -Message "Ponemos un mensaje"
    
    .PARAMETER LogType
        -LogType "INFO"  #Default
        -LogType "WARNING"
        -LogType "ERROR"
    
    .EXAMPLE
        Write-Log -Message "Ponemos un mensaje" -LogType "ERROR"
        Write-Log "Ponemos un mensaje"
    
    .NOTES
        Primero hay que definir 2 parametros:
        $logFile = "00 CleanupScriptLog.log"    # Nombre del Fichero
        $logPath = "$env:windir\Logs\Software"  # Ruta del Fichero
    #>

    param (
        [string]$Message,
        [string]$LogType = "INFO"
    )
    try {
        if (-Not (Test-Path -Path $logPath)) {
            New-Item -Path $logPath -ItemType Directory -Force
        }
        $logFilePath = "$logPath\$logFile"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "$timestamp [$LogType] $Message"
        Add-Content -Path $logFilePath -Value $logMessage
    }
    catch {
        Write-Log "Error al iniciar el log o crear la carpeta de logs: $_" -LogType "ERROR"
    }
}

Write-Log "Inicio del script de limpieza $PSConsoleTitle." 

Function Clear-Folder {
    param (
        [string]$Path,
        [string]$LogDescription
    )
    try {
        if (Test-Path -Path "$Path\*") {
            Write-Log "Eliminando archivos en $LogDescription ($Path)..."
            Remove-Item -Path "$Path\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            Write-Log "La carpeta $Path no existe. No se realizaron cambios."
        }
    }
    catch {
        Write-Log -Message "Error al limpiar $LogDescription ($Path): $_" -LogType "ERROR"
    }
}
    
#####################################################
#                                                   #
#     >> Servicio de Windows Update                 #
#                                                   #
#####################################################

# Función para detener un servicio
Function Stop-ServiceSafely {
    param (
        [string]$ServiceName
    )
    try {
        Write-Log "Deteniendo servicio: ${ServiceName}..." 
        Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        # Esperar a que el servicio se detenga completamente
        while ((Get-Service -Name $ServiceName).Status -eq 'Running') {
            Start-Sleep -Seconds 1
            Write-Log "Esperando a que se detenga el servicio ${ServiceName}..."
        }
        Write-Log "Servicio $ServiceName detenido exitosamente." 
    }
    catch {
        Write-Log "Error al detener el servicio ${ServiceName}: $_" -LogType "ERROR"
    }
}

Function Start-ServiceSafely {
    param (
        [string]$ServiceName
    )
    try {
        Write-Log "Iniciando servicio: $ServiceName..." 
        Set-Service -name $ServiceName -startupType automatic -ErrorAction SilentlyContinue
        Start-Service -Name $ServiceName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        Write-Log "Servicio $ServiceName iniciado exitosamente." 
    }
    catch {
        Write-Log "Error al iniciar el servicio $ServiceName : $_" -LogType "ERROR"
    }
}
function Clear-Update {  
    Write-Host "Actualizaciones de Windows Update...`t`t`t" -NoNewline
    if ($actUpdates -eq 1) {
        Write-Log "Iniciando Limpieza de Windows Update..." -LogType "WARNING"
        
        # Detener serviciosF
        Stop-ServiceSafely -ServiceName "wuauserv"
        Stop-ServiceSafely -ServiceName "cryptSvc"
        Stop-ServiceSafely -ServiceName "bits"
        Stop-ServiceSafely -ServiceName "msiserver"

        # Rutas de las carpetas a eliminar
        $foldersUpdates = @(
            "$env:windir\SoftwareDistribution",
            "$env:windir\SoftwareDistribution.OLD",
            "$env:windir\SoftwareDistribution_OLD",
            "$env:windir\System32\catroot2"
        )

        # Eliminar las carpetas
        foreach ($folder in $foldersUpdates) {
            Clear-Folder -Path $folder -LogDescription "carpeta $folder"
        }

        # Iniciar servicios relacionados con Windows Update
        Start-ServiceSafely -ServiceName "wuauserv"
        Start-ServiceSafely -ServiceName "cryptSvc"
        Start-ServiceSafely -ServiceName "bits"
        Start-ServiceSafely -ServiceName "msiserver"

        Write-Log "Servicios de Windows Update reiniciados exitosamente." 
        Write-Host "LIMPIADO" -ForegroundColor Green
        $Success = $true
    }
    elseif ($actUpdates -eq 0) {
        Write-Log "La iniciacion de la limpieza de WindowsUpdate esta desactivada" -LogType "WARNING"
        Write-Host "DESABILITADO" -ForegroundColor Yellow
        $Success = $true
    }
    else {
        Write-Log "No esta configurada la limpieza de WindowsUpdate" -LogType "ERROR"
        Write-Host "ERROR" -ForegroundColor Red
        $Success = $false
    }
    Return $Success
}

#####################################################
#                                                   #
#     >> Limpiar Temporales                         #
#                                                   #
#####################################################


function Clear-Temp {  
    Write-Host "Temporales de Windows...`t`t`t`t" -NoNewline
    if ($actLimTemp -eq 1) {
        Write-Log "Iniciando limpieza de Temporales..." -LogType "WARNING"

        # Rutas de las carpetas a eliminar
        $foldersTemp = @(
            "$env:windir\ccmcache",
            "$env:windir\Temp"
        )

        # Eliminar las carpetas
        foreach ($folder in $foldersTemp) {
            Clear-Folder -Path $folder -LogDescription "carpeta $folder"
        }

        # Limpieza de Temp de usuarios
        try {
            #Write-Log -Message "Iniciando limpieza de carpetas Temp de usuarios..." -LogType "WARNING"
            Get-ChildItem -Path "C:\Users\*" -Directory | ForEach-Object {
                $tempPath = Join-Path $_.FullName "AppData\Local\Temp"
                Clear-Folder -Path $tempPath -LogDescription "carpeta Temp del usuario $($_.Name)"
            }
        }
        catch {
            Write-Log "Error al limpiar carpetas Temp de usuarios: $_" -LogType "ERROR"
            Write-Host "ERROR" -ForegroundColor Red
            $Success = $false
        }
        Write-Log "Limpieza de Temporales completada." -LogType "WARNING"
        Write-Host "LIMPIADO" -ForegroundColor Green
        $Success = $true

    }
    elseif ($actLimTemp -eq 0) {
        Write-Log "La iniciacion de la limpieza de Temporales esta desactivada" -LogType "WARNING"
        Write-Host "DESABILITADO" -ForegroundColor Yellow
        $Success = $true
    }
    else {
        Write-Log "No esta configurada la limpieza de Temporales" -LogType "ERROR"
        Write-Host "ERROR" -ForegroundColor Red
        $Success = $false
    }
    Return $Success
}

function Clear-WinOLD {  
    Write-Host "Versiones anteriores de Windows...`t`t`t" -NoNewline
    if ($actWinOLD -eq 1) {
        Write-Log "Iniciando limpieza de Windows.OLD..." -LogType "WARNING"

        # Rutas de las carpetas a eliminar
        $foldersTemp = @(
            "C:\Windows.old"
        )

        # Eliminar las carpetas
        foreach ($folder in $foldersTemp) {
            # Tomar posesión de la carpeta
            takeown /F $folder /A /R /D N

            # Otorgar permisos de control total a los administradores
            icacls $folder /grant Administradores:F /T /C /Q

            Clear-Folder -Path $folder -LogDescription "carpeta $folder"
        }

        Write-Log "Limpieza de Windows.OLD completada." -LogType "WARNING"
        Write-Host "LIMPIADO" -ForegroundColor Green
        $Success = $true

    }
    elseif ($actWinOLD -eq 0) {
        Write-Log "La iniciacion de la limpieza de Windows.OLD esta desactivada" -LogType "WARNING"
        Write-Host "DESABILITADO" -ForegroundColor Yellow
        $Success = $true
    }
    else {
        Write-Log "No esta configurada la limpieza de Windows.OLD" -LogType "ERROR"
        Write-Host "ERROR" -ForegroundColor Red
        $Success = $false
    }
    Return $Success
}

function Clear-Panther {  
    $nNameClear = "Panther"
    Write-Host "Archivos de registros de la instalación de Windows...`t" -NoNewline
    if ($actPanther -eq 1) {
        Write-Log "Iniciando limpieza de $nNameClear..." -LogType "WARNING"

        # Rutas de las carpetas a eliminar
        $foldersTemp = "$env:windir\$nNameClear" # Archivos de registros de la instalación de Windows
            
        # Eliminar las carpetas
        If (Test-Path $foldersTemp) {
            Clear-Folder -Path $foldersTemp -LogDescription "carpeta $foldersTemp"
            Write-Log "Limpieza de $foldersTemp completada." -LogType "WARNING"
            Write-Host "LIMPIADO" -ForegroundColor Green
            $Success = $true
        }
        else {
            Write-Log "No existe la carpeta $foldersTemp." -LogType "WARNING"
            Write-Host "NO-CARPETA" -ForegroundColor Magenta
            $Success = $false
        }
    }
    elseif ($actPanther -eq 0) {
        Write-Log "La iniciacion de la limpieza de $nNameClear esta desactivada" -LogType "WARNING"
        Write-Host "DESABILITADO" -ForegroundColor Yellow
        $Success = $true
    }
    else {
        Write-Log "No esta configurada la limpieza de $nNameClear" -LogType "ERROR"
        Write-Host "ERROR" -ForegroundColor Red
        $Success = $false
    }
    $nNameClear = $Null
    Return $Success
}


Set-ConsoleTitle -ConsoleTitle $PSConsoleTitle
Clear-Host
$Success = $true
If ($SystemInstall.IsPresent) {
    $Status = Clear-Update
    If ($Status = $false) {
        $Success = $false
    }
    $Status = Clear-Temp
    If ($Status = $false) {
        $Success = $false
    }
    $Status = Clear-WinOLD
    If ($Status = $false) {
        $Success = $false
    }
    $Status = Clear-Panther
    If ($Status = $false) {
        $Success = $false
    }
}else {
    $Status = Clear-Update
    If ($Status = $false) {
        $Success = $false
    }
    $Status = Clear-Temp
    If ($Status = $false) {
        $Success = $false
    }
    $Status = Clear-WinOLD
    If ($Status = $false) {
        $Success = $false
    }
    $Status = Clear-Panther
    If ($Status = $false) {
        $Success = $false
    }
}
If ($Success -eq $false) {
    Exit 1
}
