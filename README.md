# HeroLinkReadiness

Inventaire en lecture seule des **réglages de partage** et du **lien principal par défaut** (« hero link ») de chaque site SharePoint, pour repérer le surpartage avant qu'il ne soit amplifié par Microsoft Copilot.

Chaque site SharePoint possède une propriété `DefaultMainLinkScope` qui fixe l'audience du lien principal des éléments situés à la racine d'une bibliothèque. Les valeurs possibles sont `OnlyPeopleAdded` (valeur effective par défaut), `Organization` et `Anyone`. Un lien ouvert à toute l'organisation donne accès au contenu à tous les employés. Comme Copilot respecte les autorisations existantes, il peut ensuite citer ce contenu à quiconque a accès au fichier.

HeroLinkReadiness répond à une seule question : **quels sites partagent par défaut plus largement que prévu ?**

📝 Article lié : [blog.trivium365.com](https://blog.trivium365.com) (le lien direct sera ajouté à la publication de l'article du 13 octobre 2026)

## Ce que fait l'outil

1. Lit `SharingCapability` et `CoreDefaultShareLinkScope` du locataire avec `Get-SPOTenant`.
2. Liste les sites avec `Get-SPOSite -Limit All`.
3. Relit chaque site avec `Get-SPOSite -Identity` pour obtenir ses propriétés de partage (voir « Limites connues »).
4. Classe chaque site :

| Statut | Signification |
|---|---|
| **À CORRIGER** | Lien principal ouvert à `Anyone` ou lien principal ouvert à toute l'organisation sur un site qui accepte les liens anonymes |
| **À VALIDER** | Lien principal ouvert à toute l'organisation (`Organization`) ou site qui accepte les liens anonymes ou valeur non lisible |
| **OK** | Lien principal limité aux personnes ajoutées (`OnlyPeopleAdded`) |

Il produit un tableau à l'écran, un fichier CSV et un rapport HTML.

**L'outil ne modifie rien.** Aucune commande `Set-` n'est exécutée.

## Prérequis

- PowerShell 7 ou Windows PowerShell 5.1
- Module `Microsoft.Online.SharePoint.PowerShell`
- Le rôle SharePoint Administrator

```powershell
Install-Module Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser
```

## Utilisation

```powershell
.\HeroLinkReadiness.ps1 -AdminUrl https://contoso-admin.sharepoint.com -OutputFolder .\rapports
```

Déjà connecté avec `Connect-SPOService` ? Ajoutez `-SkipConnect`. Pour cibler un type de site, ajoutez par exemple `-Template 'GROUP#0'` (sites d'équipe liés à un groupe Microsoft 365).

## Exemple de résultat

```
Statut     Url                                   Partage                      LienPrincipal
------     ---                                   -------                      -------------
À CORRIGER https://contoso.sharepoint.com/sites/pub   ExternalUserAndGuestSharing  Anyone
À VALIDER  https://contoso.sharepoint.com/sites/rh    ExternalUserSharingOnly      Organization
OK         https://contoso.sharepoint.com/sites/ventes Disabled                     OnlyPeopleAdded
```

## Et ensuite ?

La correction se fait site par site avec `Set-SPOSite -Identity <url> -DefaultMainLinkScope OnlyPeopleAdded`. La valeur `Anyone` n'est disponible que si les liens anonymes sont permis au niveau du locataire. Le paramètre n'existe que sur `Set-SPOSite` : `Set-SPOTenant` n'a pas d'équivalent pour le lien principal. Il ne touche que l'audience du lien, pas son niveau de permission. Testez d'abord sur un site pilote.

## Limites connues

- Selon la documentation de `Get-SPOSite`, les paramètres `-Limit` et `-Filter` ne remplissent pas les propriétés de partage (dont `SharingCapability`). L'outil relit donc chaque site individuellement : prévoyez plusieurs minutes dans un grand locataire.
- `DefaultMainLinkScope` n'apparaît pas dans la liste des sorties documentées de `Get-SPOSite` (il est documenté sur `Set-SPOSite`). Si votre version du module ne le retourne pas, le site est classé **À VALIDER** avec la mention « non lisible ». Cette lecture n'a pas pu être testée sur un vrai locataire.
- Les sites OneDrive ne sont pas inclus.
- L'outil lit les réglages par défaut des sites. Il ne parcourt pas les liens de partage déjà créés.

## Sources

- [Get-SPOSite](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-sposite) (Microsoft Learn)
- [Set-SPOSite](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/set-sposite) (Microsoft Learn)
- [Get-SPOTenant](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spotenant) (Microsoft Learn)
- [Connect-SPOService](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/connect-sposervice) (Microsoft Learn)

## Licence

MIT. Publié par Charles Jenkins, [blog.trivium365.com](https://blog.trivium365.com).
