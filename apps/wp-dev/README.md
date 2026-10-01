# _wp-template — WordPress dev-site skabelon

Skabelon til nye WordPress dev-sider på clusteret. Ikke deployet (mangler i
`apps/kustomization.yaml` med vilje).

## Nyt dev-site på 5 minutter

1. Kopiér mappen: `cp -r apps/_wp-template apps/wp-<navn>`
2. Erstaj `dev` overalt: `grep -rl dev apps/wp-<navn> | xargs sed -i 's/dev/<navn>/g'`
3. Tilføj `wp-<navn>` til `apps/kustomization.yaml`
4. Opret namespace + secret FØR push (se nedenfor)
5. Commit + push — Flux synker inden for ~10 min
6. DNS-record på UDM: `<navn>.kung.dk → 10.22.50.60` (eller brug wildcard *.kung.dk)

## Secret (oprettes via jump-serveren — kommer ikke i git)

```bash
kubectl create namespace wp-<navn>
kubectl create secret generic wp-<navn>-db -n wp-<navn> \
  --from-literal=root-password="$(openssl rand -base64 24)" \
  --from-literal=wp-password="$(openssl rand -base64 24)" \
  --from-literal=wp-config-extra="define('WP_MEMORY_LIMIT', '512M');"
```

`wp-config-extra` er indholdet af `WORDPRESS_CONFIG_EXTRA` — sitespecifikke
defines (eksterne DB-profiler, constants m.m.) lægges her. Se `apps/wp-usv`
for et eksempel med ekstern database-adgang.

## Migration af eksisterende site (fra Simply-hosting)

1. DB: `mysqldump -h mysql40.unoeuro.com -u spot3_dk -p spot3_dk_db_<site> | kubectl exec -i -n wp-<navn> sts/wordpress-db -- mysql -uwordpress -p<wp-password> wordpress`
2. Filer: FTP-hent `wp-content` fra kilden → `kubectl cp wp-content/. <pod>:/var/www/html/wp-content/`
3. SiteURL: `kubectl exec -n wp-<navn> sts/wordpress-db -- mysql -uwordpress -p<wp-password> wordpress -e "UPDATE wp_options SET option_value='http://<navn>.kung.dk' WHERE option_name IN ('siteurl','home');"`
4. Kernen af wp-config (salts, credentials) kommer fra imaget + env — kun
   sitespecifikke defines skal med i `wp-config-extra`
