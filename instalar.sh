#!/usr/bin/env bash
# Instalación del Kraken Bot en un servidor Ubuntu 24.04 (Oracle Cloud gratuito, Hetzner o similar).
# Uso (como root, en el servidor recién creado):
#   1) pega este archivo en el servidor:  nano instalar.sh   (pegar, Ctrl+O, Enter, Ctrl+X)
#   2) bash instalar.sh
#
# Qué deja funcionando:
#   - kraken-noticias : detector de noticias 24/7 (modo medición, no opera). ACTIVO.
#   - kraken-real     : el bot con dinero real. INSTALADO PERO APAGADO.
#                       Solo se enciende cuando Javier lo decida (ver servidor/ACTIVAR_REAL.md).
# El bot en simulación sigue en GitHub Actions como hasta ahora.
set -euo pipefail

echo "== Token de GitHub =="
echo "Crea uno en github.com > Settings > Developer settings > Fine-grained tokens"
echo "con acceso SOLO al repositorio kraken-bot y permiso 'Contents: Read and write'."
read -rsp "Pega el token (no se verá): " GH_TOKEN; echo
REPO="javigvmg-coder/kraken-bot"
DIR=/opt/kraken-bot

echo "== Memoria de reserva (swap 2 GB, para servidores de 1 GB) =="
if [ ! -f /swapfile ]; then fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile && echo "/swapfile none swap sw 0 0" >> /etc/fstab; fi

echo "== Sistema =="
apt-get update -qq && apt-get install -y -qq python3-venv git ufw unattended-upgrades >/dev/null
ufw allow OpenSSH >/dev/null && ufw --force enable >/dev/null          # cortafuegos: solo SSH
dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null        # parches de seguridad automáticos
timedatectl set-timezone Europe/Madrid

echo "== Código =="
useradd -r -m -d /home/kraken kraken 2>/dev/null || true
git clone -q "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git" "$DIR" 2>/dev/null || (cd "$DIR" && git pull -q)
python3 -m venv "$DIR/.venv"
"$DIR/.venv/bin/pip" install -q -r "$DIR/requirements.txt"
mkdir -p "$DIR/medicion" "$DIR/real"
chown -R kraken:kraken "$DIR"
sudo -u kraken git -C "$DIR" config user.name "kraken-servidor"
sudo -u kraken git -C "$DIR" config user.email "bot@users.noreply.github.com"

# Claves (vacías por ahora). Permisos 600: solo el usuario kraken puede leerlas.
if [ ! -f "$DIR/.env" ]; then
cat > "$DIR/.env" <<'EOF'
# Claves de KuCoin: SOLO permiso de trading (nunca retirada), limitadas a la IP de este servidor.
API_KEY=
API_SECRET=
API_PASSPHRASE=
# Telegram (los mismos valores que en los secretos de GitHub)
TELEGRAM_TOKEN=
# Para operar con dinero real hay que escribir aquí exactamente: SI-ENTIENDO-EL-RIESGO
MODO_REAL=
# DCA automático real: off | paper | live
DCA_AUTO_MODO=off
ESTADO_FILE=/opt/kraken-bot/real/estado.json
EOF
fi
chown kraken:kraken "$DIR/.env"; chmod 600 "$DIR/.env"

echo "== Servicios =="
cat > /etc/systemd/system/kraken-noticias.service <<EOF
[Unit]
Description=Kraken Bot - detector de noticias (medicion)
After=network-online.target
[Service]
User=kraken
WorkingDirectory=$DIR/medicion
ExecStart=$DIR/.venv/bin/python -u $DIR/noticias.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/kraken-real.service <<EOF
[Unit]
Description=Kraken Bot - DINERO REAL (apagado hasta que Javier lo active)
After=network-online.target
[Service]
User=kraken
WorkingDirectory=$DIR/real
EnvironmentFile=$DIR/.env
ExecStart=$DIR/.venv/bin/python -u $DIR/bot.py live
Restart=always
RestartSec=30
[Install]
WantedBy=multi-user.target
EOF

# Cada 15 min: trae los vetos del analista y sube los datos medidos de noticias
cat > /etc/cron.d/kraken <<EOF
*/15 * * * * kraken cd $DIR && git pull -q --rebase -X theirs && cp -f vetos.json real/ 2>/dev/null; cp -f medicion/noticias.jsonl . 2>/dev/null && git add noticias.jsonl && (git commit -qm "Datos de noticias" || true) && git push -q
EOF

systemctl daemon-reload
systemctl enable --now kraken-noticias
systemctl disable kraken-real 2>/dev/null || true
sleep 5
echo
systemctl --no-pager status kraken-noticias | head -4
echo
echo "== Listo =="
echo "IP de este servidor (la necesitarás para la API key de KuCoin):  $(curl -s -4 ifconfig.me || hostname -I)"
echo "Ver el detector en directo:  journalctl -u kraken-noticias -f"
echo "El bot con dinero real está instalado pero APAGADO."
