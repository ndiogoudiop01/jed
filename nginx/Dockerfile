###############################################################################
#  Image du reverse-proxy interne.
#
#  La configuration est COPIÉE dans l'image, et non montée depuis l'hôte.
#  Raison : sur Coolify et Dokploy, `docker compose` est lancé depuis un
#  répertoire de travail qui n'est PAS celui où le dépôt a été cloné. Un
#  montage « ./nginx/odoo.conf:/etc/nginx/conf.d/default.conf » pointe alors
#  vers un chemin inexistant, que le démon Docker crée en DOSSIER vide —
#  d'où l'erreur :
#      not a directory: Are you trying to mount a directory onto a file ?
#  Une image construite depuis le contexte git est immunisée contre ça.
###############################################################################
FROM nginx:1.27-alpine

COPY odoo.conf /etc/nginx/conf.d/default.conf

#  Pas de « RUN nginx -t » ici : la configuration déclare
#      upstream odoo { server odoo:8069; }
#  et nginx résout les noms d'hôte des upstreams dès le contrôle de syntaxe.
#  Au build, le service « odoo » n'existe pas encore -> « host not found in
#  upstream », et le build échouerait sur une configuration pourtant valide.
#  La vérification a lieu au démarrage du conteneur, quand le réseau existe.
