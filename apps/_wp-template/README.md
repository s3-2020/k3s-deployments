# _wp-template — WordPress dev-site skabelon (namespace `dev`)

Alle WordPress-udviklingssider ligger i det **fælles namespace `dev`**
(`apps/dev/`). Denne skabelon er ikke deployet — kopiér filerne ind i
`apps/dev/` ved nye sites.

## Nyt dev-site på 5 minutter

1. Kopiér skabelonfilerne til `apps/dev/` med sidets navn:
   ```bash
   for f in SITENAME.yaml SITENAME-db.yaml SITENAME-httproute.yaml; do
     cp _wp-template/$(echo $f | sed 's/SITENAME/SITENAME/') apps/dev/${f/SITENAME/<navn>}
   done
   ```
   (eller manuelt: `SITENAME.yaml` → `<navn>.yaml` osv.)
2. Erstaj `SITENAME` i de tre filer: `sed -i 's/SITENAME/<navn>/g' apps/dev/<navn>*.yaml`
3. Tilføj de tre filer til `apps/dev/kustomization.yaml`
4. Opret secret på jump-serveren (se nedenfor)
5. Commit + push — Flux synker inden for ~10 min
6. DNS-record på UDM: `<navn>.kung.dk → 10.22.50.60` (eller wildcard *.kung.dk)

## Secret (oprettes via jump-serveren — kommer ikke i git)

```bash
kubectl create secret generic <navn>-db -n dev \
  --from-literal=root-password="$(openssl rand -base64 24)" \
  --from-literal=wp-password="$(openssl rand -base64 24)" \
  --from-file=wp-config-extra=<fil med defines>
```

`wp-config-extra` er indholdet af `WORDPRESS_CONFIG_EXTRA` — sitespecifikke
defines (eksterne DB-profiler, constants m.m.). Se `apps/dev/usv.yaml` for et
eksempel med ekstern database-adgang; ellers er memory-limits nok.

## Migration af eksisterende site (fra Simply-hosting)

1. DB: `mariadb-dump --single-transaction --skip-lock-tables --no-tablespaces -h mysql40.unoeuro.com -u spot3_dk -p spot3_dk_db_<site> | ssh jsh@10.22.10.120 'kubectl exec -i -n dev sts/<navn>-db -- mariadb -uwordpress -p<wp-password> wordpress'`
2. Filer: FTP-hent `wp-content` → `tar -C <mappe> -cf - . | ssh jsh@10.22.10.120 'kubectl exec -i -n dev deploy/<navn> -- tar -xf - -C /var/www/html/wp-content'`
3. SiteURL: `UPDATE wp_options SET option_value='http://<navn>.kung.dk' WHERE option_name IN ('siteurl','home');`
4. Salts/credentials genereres af imaget — kun sitespecifikke defines skal i `wp-config-extra`

## Eksisterende sites i `dev`

- `usv` — spot3.dk/usv (s3-ads udvikling, ekstern DB-profil mod usvdk02_db @ Curanet)
- `markhaven` — spot3.dk/markhaven
