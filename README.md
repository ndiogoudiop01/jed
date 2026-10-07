# Odoo — JED

| | |
|---|---|
| **Client** | `jed` |
| **Odoo** | `18.0` — `enterprise` |
| **Image de base** | `ghcr.io/ndiogoudiop01/odoo:18.0-enterprise` |
| **Domaine** | https://jed.grouplavisibilitesas.com |
| **Base par défaut** | `jed` |
| **Hébergement** | `dokploy` (VPS OVH) — ressource « Docker Compose » |

> Ce dépôt contient **tout** ce qu'il faut pour faire tourner l'instance :
> configuration, addons, sauvegardes. Le code Odoo (core + Enterprise) vient de
> l'image de base, construite depuis nos dépôts privés — il n'est pas dans ce
> dépôt et n'a pas à y être.

---

## 1. Démarrer en local (5 minutes)

```bash
git clone <url-du-repo> jed && cd jed
docker login ghcr.io -u <owner>     # une fois, pour tirer l'image de base
make dev                            # build + démarrage en développement
make logs                           # suivre le démarrage
```

Puis ouvrez **http://localhost:8102** et créez une base.

Arrêter : `make dev-down`.

---

## 2. Les commandes du quotidien

```
make                     # liste toutes les commandes disponibles
make dev                 # démarrage en développement (hot-reload)
make logs                # logs Odoo en direct
make install M=mon_module     # installer un module
make upgrade M=mon_module     # mettre à jour un module
make upgrade M=all            # tout mettre à jour
make test    M=mon_module     # lancer les tests du module
make odoo-shell               # shell Python Odoo (env, self…)
make psql                     # console PostgreSQL
make backup                   # sauvegarde immédiate
make restore FILE=/backups/…  # restaurer
make pull-base                # récupérer la dernière image de base
make rebuild                  # reconstruire après pull-base ou requirements.txt
make status                   # état + santé des conteneurs
```

**Règle d'or :** on ne modifie jamais un fichier *dans* un conteneur. Tout se
passe dans ce dossier, puis `make restart` ou `make upgrade`.

---

## 3. Où écrire du code ?

```
addons-custom/           <-- VOS modules (le seul dossier que vous modifiez)
  └── jed_ventes/
        ├── __init__.py
        ├── __manifest__.py
        ├── models/  views/  security/  tests/
addons-oca/              <-- modules OCA (submodules git, lecture seule)
```

Le core Odoo et Enterprise sont dans l'image, en `/opt/odoo` et
`/opt/odoo-enterprise`. Pour les consulter :

```bash
make shell
ls /opt/odoo-enterprise
cat /opt/SOURCES.txt      # dépôts, branches et commits exacts embarqués
```

En mode `make dev`, `addons-custom/` est monté en direct :

* modification **Python** → `make restart` (ou rien, `--dev=all` recharge)
* modification **XML / vues** → `make upgrade M=mon_module`
* nouveau module → `make install M=mon_module`

---

## 4. Déboguer pas-à-pas (VSCode)

```bash
make debug        # Odoo démarre et ATTEND le débogueur
```

Dans VSCode : `F5` → **Odoo: attach (docker)**. Les points d'arrêt posés dans
`addons-custom/` fonctionnent immédiatement.

---

## 5. Mise en production

Chaque `git push` sur `main` déclenche un redéploiement sur dokploy.

```bash
git add -A
git commit -m "feat(ventes): ajout du champ remise commerciale"
git push origin main
```

Après un déploiement qui touche des vues ou des modèles :

```bash
make upgrade M=jed_ventes
```

Pour prendre une nouvelle version du core Odoo (nouvelle image de base) :

```bash
make backup && make pull-base && make rebuild && make upgrade M=all
```

> Procédure détaillée : `docs/dokploy.md` du dépôt `odoo-stack`.

---

## 6. Sauvegardes

Un conteneur `backup` effectue un dump complet (base + filestore) chaque nuit à
**2h00**, conservé **14 jours**.

```bash
make backup                                   # dump immédiat
make backups                                  # lister
make backup-pull                              # rapatrier dans ./backups-local/
make restore FILE=/backups/xxx.tar.gz         # restaurer en écrasant
make restore FILE=/backups/xxx.tar.gz DB=test # restaurer dans une base de test
```

Une restauration vers une **autre** base désactive automatiquement les crons et
les serveurs mail sortants : aucun risque d'envoyer des e-mails depuis une copie.

---

## 7. Sécurité — points non négociables

* `LIST_DB=False` en production ; `DB_FILTER` verrouille la base servie.
* `ODOO_MASTER_PASSWORD` et `DB_PASSWORD` vivent **uniquement** dans les
  variables d'environnement de la plateforme, jamais dans git.
* Seul le service `proxy` est exposé ; Odoo et PostgreSQL restent sur le réseau
  interne du projet.
* Les ports hôte ne sont publiés qu'en mode `dev`.
* Redirection HTTP → HTTPS permanente, en-têtes de sécurité posés par nginx.
