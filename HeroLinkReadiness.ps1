<#
.SYNOPSIS
    Inventaire en lecture seule des réglages de partage de chaque site SharePoint, dont le lien principal par défaut.

.DESCRIPTION
    Outil en LECTURE SEULE : aucune commande Set- n'est exécutée.

    Pour chaque site, il lit avec Get-SPOSite :
      * SharingCapability : le niveau de partage externe du site ;
      * DefaultMainLinkScope : l'audience du lien principal (« hero link ») des éléments à la racine d'une
        bibliothèque (OnlyPeopleAdded, Organization ou Anyone) ;
      * DefaultSharingLinkType et DefaultLinkPermission : le type et l'autorisation des liens par défaut.
    Il lit aussi les réglages du locataire avec Get-SPOTenant (SharingCapability, CoreDefaultShareLinkScope)
    pour fournir un point de comparaison.

    Classement de chaque site :
      * À CORRIGER : le lien principal est ouvert à Anyone (liens anonymes) ou le site accepte les liens anonymes
        avec un lien principal ouvert à toute l'organisation.
      * À VALIDER : le lien principal est ouvert à toute l'organisation (Organization), le site accepte les
        liens anonymes (ExternalUserAndGuestSharing) ou la valeur n'a pas pu être lue.
      * OK : le lien principal est limité aux personnes ajoutées (OnlyPeopleAdded).

    Pourquoi : un lien ouvert à toute l'organisation donne accès au contenu à tous les employés. Microsoft 365 Copilot
    respecte les autorisations existantes : il peut donc citer ce contenu à quiconque a accès au fichier.

.PARAMETER AdminUrl
    URL du centre d'administration SharePoint, par exemple https://contoso-admin.sharepoint.com.
    Obligatoire sauf avec -SkipConnect.

.PARAMETER OutputFolder
    Dossier où écrire le CSV et le rapport HTML. Par défaut : le dossier courant.

.PARAMETER Template
    Limite l'inventaire à un modèle de site (par exemple GROUP#0, STS#3 ou SITEPAGEPUBLISHING#0).

.PARAMETER SkipConnect
    N'ouvre pas de nouvelle connexion (utile si Connect-SPOService est déjà fait).

.EXAMPLE
    .\HeroLinkReadiness.ps1 -AdminUrl https://contoso-admin.sharepoint.com -OutputFolder .\rapports

.EXAMPLE
    .\HeroLinkReadiness.ps1 -SkipConnect -Template 'GROUP#0'

.NOTES
    Prérequis : module Microsoft.Online.SharePoint.PowerShell et le rôle SharePoint Administrator.
    La propriété DefaultMainLinkScope n'est pas listée parmi les sorties documentées de Get-SPOSite : si votre
    version du module ne la retourne pas, le site est classé À VALIDER avec la mention « non lisible ».
    Projet : https://github.com/CharlesTrivium365/HeroLinkReadiness
#>
[CmdletBinding()]
param(
    [ValidatePattern('^https://[a-zA-Z0-9-]+-admin\.sharepoint\.[a-z.]+/?$')]
    [string]$AdminUrl,

    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$OutputFolder = (Get-Location).Path,

    [string]$Template,

    [switch]$SkipConnect
)

#Requires -Modules Microsoft.Online.SharePoint.PowerShell

if (-not $SkipConnect -and -not $AdminUrl) {
    throw 'Indiquez -AdminUrl (https://<locataire>-admin.sharepoint.com) ou utilisez -SkipConnect.'
}

function ConvertTo-HtmlText {
    param([string]$Text)
    [System.Net.WebUtility]::HtmlEncode($Text)
}

function ConvertTo-SafeCsvText {
    param([string]$Text)
    # Évite qu'un titre de site commençant par un signe égal, plus, moins ou arobase soit interprété comme une formule dans Excel.
    if ($Text -match '^[=+\-@]') { "'$Text" } else { $Text }
}

function Get-PropertyValue {
    param($Object, [string]$Name)
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { [string]$property.Value } else { $null }
}

if (-not $SkipConnect) {
    Connect-SPOService -Url $AdminUrl
}

# 1. Réglages du locataire (point de comparaison)
Write-Verbose 'Lecture des réglages de partage du locataire'
$tenant = Get-SPOTenant
$tenantSharing = Get-PropertyValue -Object $tenant -Name 'SharingCapability'
$tenantScope = Get-PropertyValue -Object $tenant -Name 'CoreDefaultShareLinkScope'

# 2. Liste des sites. Avec -Limit, Get-SPOSite ne remplit pas les propriétés de partage : on ne lit donc ici que les URL.
Write-Verbose 'Lecture de la liste des sites'
$listParams = @{ Limit = 'All' }
if ($Template) { $listParams['Template'] = $Template }
$urls = @(Get-SPOSite @listParams | Select-Object -ExpandProperty Url)

# 3. Lecture des propriétés de partage, site par site
$results = [System.Collections.Generic.List[object]]::new()
$index = 0
foreach ($url in $urls) {
    $index++
    Write-Progress -Activity 'Lecture des sites' -Status $url -PercentComplete (100 * $index / [math]::Max($urls.Count, 1))
    try {
        $site = Get-SPOSite -Identity $url
    }
    catch {
        Write-Warning "Site illisible : $url ($($_.Exception.Message))"
        continue
    }

    $scope = Get-PropertyValue -Object $site -Name 'DefaultMainLinkScope'
    $sharing = Get-PropertyValue -Object $site -Name 'SharingCapability'

    if (-not $scope) {
        $status = 'À VALIDER'
        $reason = 'DefaultMainLinkScope non lisible'
    }
    elseif ($scope -eq 'Anyone') {
        $status = 'À CORRIGER'
        $reason = 'Le lien principal est ouvert à Anyone'
    }
    elseif ($scope -eq 'Organization' -and $sharing -eq 'ExternalUserAndGuestSharing') {
        $status = 'À CORRIGER'
        $reason = 'Lien principal ouvert à toute l''organisation et liens anonymes permis'
    }
    elseif ($scope -eq 'Organization') {
        $status = 'À VALIDER'
        $reason = 'Le lien principal est ouvert à toute l''organisation'
    }
    elseif ($sharing -eq 'ExternalUserAndGuestSharing') {
        $status = 'À VALIDER'
        $reason = 'Le site accepte les liens anonymes'
    }
    else {
        $status = 'OK'
        $reason = 'Lien principal limité aux personnes ajoutées'
    }

    $results.Add([pscustomobject]@{
            Statut              = $status
            Raison              = $reason
            Url                 = $url
            Titre               = ConvertTo-SafeCsvText -Text (Get-PropertyValue -Object $site -Name 'Title')
            Modele              = Get-PropertyValue -Object $site -Name 'Template'
            Partage             = $sharing
            LienPrincipal       = $scope
            TypeLienParDefaut   = Get-PropertyValue -Object $site -Name 'DefaultSharingLinkType'
            PermissionParDefaut = Get-PropertyValue -Object $site -Name 'DefaultLinkPermission'
            Etiquette           = Get-PropertyValue -Object $site -Name 'SensitivityLabel'
        })
}
Write-Progress -Activity 'Lecture des sites' -Completed
$ordered = @($results | Sort-Object { @{ 'À CORRIGER' = 0; 'À VALIDER' = 1; 'OK' = 2 }[$_.Statut] }, Url)

# 4. Sorties
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$csvPath = Join-Path $OutputFolder "HeroLinkReadiness-$stamp.csv"
$htmlPath = Join-Path $OutputFolder "HeroLinkReadiness-$stamp.html"
$ordered | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

$colors = @{ 'À CORRIGER' = '#c62828'; 'À VALIDER' = '#ef6c00'; 'OK' = '#2e7d32' }
$tableRows = foreach ($r in $ordered) {
    "<tr><td style='color:$($colors[$r.Statut]);font-weight:600'>$($r.Statut)</td><td>$(ConvertTo-HtmlText $r.Raison)</td><td><a href='$(ConvertTo-HtmlText $r.Url)'>$(ConvertTo-HtmlText $r.Url)</a></td><td>$(ConvertTo-HtmlText $r.Titre)</td><td>$(ConvertTo-HtmlText $r.Partage)</td><td>$(ConvertTo-HtmlText $r.LienPrincipal)</td><td>$(ConvertTo-HtmlText $r.TypeLienParDefaut)</td><td>$(ConvertTo-HtmlText $r.PermissionParDefaut)</td></tr>"
}
$counts = foreach ($s in 'À CORRIGER', 'À VALIDER', 'OK') { "<li><strong>$s</strong> : $(@($ordered | Where-Object Statut -eq $s).Count)</li>" }

@"
<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><title>Réglages de partage SharePoint</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:2rem;color:#1a1a2e}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ddd;padding:6px 10px;text-align:left;font-size:14px}th{background:#1a1446;color:#fff}.diag{background:#fff4e5;border-left:4px solid #ef6c00;padding:10px 14px}</style>
</head><body>
<h1>Réglages de partage et lien principal par défaut</h1>
<p>Généré le $(Get-Date -Format 'yyyy-MM-dd HH:mm') · $($ordered.Count) site(s)</p>
<p class="diag">Locataire : SharingCapability = <strong>$(ConvertTo-HtmlText $tenantSharing)</strong> · CoreDefaultShareLinkScope = <strong>$(ConvertTo-HtmlText $tenantScope)</strong></p>
<ul>$($counts -join '')</ul>
<table><tr><th>Statut</th><th>Raison</th><th>Site</th><th>Titre</th><th>Partage</th><th>Lien principal</th><th>Type de lien</th><th>Permission</th></tr>
$($tableRows -join "`n")
</table>
</body></html>
"@ | Set-Content -Path $htmlPath -Encoding UTF8

$ordered | Format-Table Statut, Url, Partage, LienPrincipal -AutoSize
Write-Information "CSV : $csvPath" -InformationAction Continue
Write-Information "Rapport HTML : $htmlPath" -InformationAction Continue
